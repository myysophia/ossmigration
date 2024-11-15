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

# 检查必要的命令
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Docker is required but not installed.${NC}" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo -e "${RED}zip is required but not installed.${NC}" >&2; exit 1; }

# 检查 requirements.txt
if [ ! -f "${PROJECT_ROOT}/requirements.txt" ]; then
    echo -e "${RED}requirements.txt not found in ${PROJECT_ROOT}${NC}"
    exit 1
fi

# 创建临时目录
echo -e "${YELLOW}Creating temporary directory...${NC}"
BUILD_DIR=$(mktemp -d)
mkdir -p ${BUILD_DIR}/python

# 在 Docker 中构建依赖
echo -e "${YELLOW}Building dependencies in Docker...${NC}"
# docker run --rm \
#     -v ${BUILD_DIR}:/var/task \
#     -v ${PROJECT_ROOT}/requirements.txt:/var/task/requirements.txt \
#     public.ecr.aws/sam/build-python3.9:latest \
#     /bin/bash -c "pip install --target /var/task/python cryptography --platform manylinux2014_x86_64 --only-binary=:all: && pip install -r /var/task/requirements.txt --target /var/task/python"

docker run --rm \
    -v ${BUILD_DIR}:/var/task \
    -v ${PROJECT_ROOT}/requirements.txt:/var/task/requirements.txt \
    public.ecr.aws/sam/build-python3.9:latest \
    /bin/bash -c "pip install --target /var/task/python cryptography --platform manylinux2014_x86_64 --only-binary=:all: && pip install -r /var/task/requirements.txt --target /var/task/python"

# 检查依赖是否安装成功
if [ ! "$(ls -A ${BUILD_DIR}/python)" ]; then
    echo -e "${RED}No dependencies were installed${NC}"
    exit 1
fi

# 显示安装的包
echo -e "${YELLOW}Installed packages:${NC}"
ls -l ${BUILD_DIR}/python

# 创建 ZIP 文件
echo -e "${YELLOW}Creating layer ZIP file...${NC}"
cd ${BUILD_DIR}
zip -r9 ${PROJECT_ROOT}/layer.zip python/

# 检查 ZIP 文件
if [ ! -f "${PROJECT_ROOT}/layer.zip" ]; then
    echo -e "${RED}Failed to create ZIP file${NC}"
    exit 1
fi

# 显示 ZIP 文件大小
ZIP_SIZE=$(ls -lh ${PROJECT_ROOT}/layer.zip | awk '{print $5}')
echo -e "${YELLOW}ZIP file size: ${ZIP_SIZE}${NC}"

# 检查 ZIP 文件内容
echo -e "${YELLOW}ZIP file contents:${NC}"
unzip -l ${PROJECT_ROOT}/layer.zip

# 发布 Layer
echo -e "${YELLOW}Publishing layer to ${AWS_REGION}...${NC}"
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
    # 保存 Layer ARN 到环境文件
    LAYER_ARN="arn:aws:lambda:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):layer:${LAYER_NAME}-${AWS_REGION}:${LAYER_VERSION}"
    
    # 更新或添加 LAYER_ARN 到 .env 文件
    if [ ! -f "${PROJECT_ROOT}/.env" ]; then
        touch "${PROJECT_ROOT}/.env"
    fi
    
    # 更新或添加 LAYER_ARN
    if grep -q "^LAYER_ARN=" "${PROJECT_ROOT}/.env"; then
        # 如果存在则替换
        sed -i "s|^LAYER_ARN=.*|LAYER_ARN=${LAYER_ARN}|" "${PROJECT_ROOT}/.env"
    else
        # 如果不存在则添加
        echo "LAYER_ARN=${LAYER_ARN}" >> "${PROJECT_ROOT}/.env"
    fi
    
    echo -e "${GREEN}Layer ARN: ${LAYER_ARN}${NC}"
else
    echo -e "${RED}Failed to create layer${NC}"
    exit 1
fi

# 清理前显示文件
echo -e "${YELLOW}Files before cleanup:${NC}"
ls -la ${BUILD_DIR}
ls -la ${PROJECT_ROOT}/layer.zip

# 清理
echo -e "${YELLOW}Cleaning up...${NC}"
rm -rf ${BUILD_DIR}
rm -f ${PROJECT_ROOT}/layer.zip

echo -e "${GREEN}Layer creation complete for ${AWS_REGION}${NC}"
