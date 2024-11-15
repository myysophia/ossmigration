#!/bin/bash

# 检查命令行参数
if [ "$#" -ne 1 ]; then
    echo -e "${RED}Usage: $0 <region>${NC}"
    echo -e "Example: $0 ap-south-1"
    exit 1
fi

# 设置变量
LAYER_NAME="python-deps"
LAYER_DESC="Python dependencies for Lambda"
AWS_REGION="$1"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 创建临时目录
echo -e "${YELLOW}Creating temporary directory...${NC}"
BUILD_DIR=$(mktemp -d)
mkdir -p ${BUILD_DIR}/python

# 在 Docker 中构建依赖
echo -e "${YELLOW}Building dependencies in Docker...${NC}"
docker run --rm \
    -v ${BUILD_DIR}:/var/task \
    -v ${PROJECT_ROOT}/requirements.txt:/var/task/requirements.txt \
    public.ecr.aws/sam/build-python3.9:latest \
    /bin/bash -c "
        pip install --target /var/task/python \
            --platform manylinux2014_x86_64 \
            --implementation cp \
            --python-version 3.9 \
            --only-binary=:all: \
            --no-cache-dir \
            -r /var/task/requirements.txt && \
        find /var/task/python -type d -name \"tests\" -exec rm -rf {} + 2>/dev/null || true && \
        find /var/task/python -type d -name \"__pycache__\" -exec rm -rf {} + 2>/dev/null || true
    "

# 创建 ZIP 文件
cd ${BUILD_DIR}
zip -r9 ${PROJECT_ROOT}/layer.zip python/

# 发布 Layer
LAYER_VERSION=$(aws lambda publish-layer-version \
    --layer-name "${LAYER_NAME}-${AWS_REGION}" \
    --description "${LAYER_DESC} for ${AWS_REGION}" \
    --zip-file fileb://${PROJECT_ROOT}/layer.zip \
    --compatible-runtimes python3.9 \
    --region ${AWS_REGION} \
    --query 'Version' \
    --output text)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created layer version: ${LAYER_VERSION}${NC}"
    LAYER_ARN="arn:aws:lambda:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):layer:${LAYER_NAME}-${AWS_REGION}:${LAYER_VERSION}"
    echo "LAYER_ARN=${LAYER_ARN}" > "${PROJECT_ROOT}/.env"
    echo -e "${GREEN}Layer ARN saved to .env file${NC}"
else
    echo -e "${RED}Failed to create layer${NC}"
    exit 1
fi

# 清理
rm -rf ${BUILD_DIR}
rm -f ${PROJECT_ROOT}/layer.zip
