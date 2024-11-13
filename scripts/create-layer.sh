#!/bin/bash

# 设置变量
LAYER_NAME="python-deps"
LAYER_DESC="Python dependencies for Lambda"
AWS_REGION="ap-southeast-2"
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
docker run --rm -v ${BUILD_DIR}:/var/task -v ${PROJECT_ROOT}/requirements.txt:/requirements.txt public.ecr.aws/sam/build-python3.9:latest \
    pip install -r /requirements.txt -t /var/task/python

# 创建 ZIP 文件
echo -e "${YELLOW}Creating layer ZIP file...${NC}"
cd ${BUILD_DIR}
zip -r9 ${PROJECT_ROOT}/layer.zip python/

# 发布 Layer
echo -e "${YELLOW}Publishing layer...${NC}"
LAYER_VERSION=$(aws lambda publish-layer-version \
    --layer-name ${LAYER_NAME} \
    --description "${LAYER_DESC}" \
    --zip-file fileb://${PROJECT_ROOT}/layer.zip \
    --compatible-runtimes python3.9 \
    --region ${AWS_REGION} \
    --query 'Version' \
    --output text)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created layer version: ${LAYER_VERSION}${NC}"
    # 保存 Layer ARN 到环境文件
    LAYER_ARN="arn:aws:lambda:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):layer:${LAYER_NAME}:${LAYER_VERSION}"
    # 更新或添加 LAYER_ARN 到 .env 文件
    if grep -q "LAYER_ARN=" "${PROJECT_ROOT}/.env"; then
        sed -i "s|LAYER_ARN=.*|LAYER_ARN=${LAYER_ARN}|" "${PROJECT_ROOT}/.env"
    else
        echo "LAYER_ARN=${LAYER_ARN}" >> "${PROJECT_ROOT}/.env"
    fi
else
    echo -e "${RED}Failed to create layer${NC}"
    exit 1
fi

# 清理
rm -rf ${BUILD_DIR}
rm -f ${PROJECT_ROOT}/layer.zip

echo -e "${GREEN}Layer creation complete${NC}"
