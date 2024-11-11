#!/bin/bash

# 设置变量
FUNCTION_NAME="rds-backup-to-oss"
AWS_REGION="ap-southeast-2"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否安装了必要的工具
command -v python3 >/dev/null 2>&1 || { echo -e "${RED}Python3 is required but not installed.${NC}" >&2; exit 1; }
command -v pip3 >/dev/null 2>&1 || { echo -e "${RED}pip3 is required but not installed.${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed.${NC}" >&2; exit 1; }

# 创建临时构建目录
BUILD_DIR=$(mktemp -d)
echo -e "${YELLOW}Creating temporary build directory: ${BUILD_DIR}${NC}"

# 清理函数
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

# 复制源代码到构建目录
echo "Copying source files..."
cp -r ${PROJECT_ROOT}/src/* ${BUILD_DIR}/
cp ${PROJECT_ROOT}/requirements.txt ${BUILD_DIR}/

# 安装依赖
echo "Installing dependencies..."
pip3 install -r ${BUILD_DIR}/requirements.txt -t ${BUILD_DIR} --no-cache-dir

# 删除不必要的文件
echo "Cleaning up unnecessary files..."
find ${BUILD_DIR} -type d -name "__pycache__" -exec rm -rf {} +
find ${BUILD_DIR} -type f -name "*.pyc" -delete
find ${BUILD_DIR} -type f -name "*.pyo" -delete
find ${BUILD_DIR} -type f -name "*.dist-info" -exec rm -rf {} +
find ${BUILD_DIR} -type f -name "*.egg-info" -exec rm -rf {} +

# 创建部署包
echo "Creating deployment package..."
cd ${BUILD_DIR}
zip -r9 ../function.zip .
cd - > /dev/null

# 更新函数代码
echo "Updating Lambda function..."
aws lambda update-function-code \
    --function-name ${FUNCTION_NAME} \
    --zip-file fileb://function.zip \
    --region ${AWS_REGION}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully updated Lambda function${NC}"
else
    echo -e "${RED}Failed to update Lambda function${NC}"
    exit 1
fi

# 等待函数更新完成
echo "Waiting for function update to complete..."
aws lambda wait function-updated \
    --function-name ${FUNCTION_NAME} \
    --region ${AWS_REGION}

# 验证更新
echo "Verifying function update..."
FUNCTION_STATE=$(aws lambda get-function \
    --function-name ${FUNCTION_NAME} \
    --region ${AWS_REGION} \
    --query 'Configuration.State' \
    --output text)

if [ "${FUNCTION_STATE}" = "Active" ]; then
    echo -e "${GREEN}Function is active and ready${NC}"
else
    echo -e "${RED}Function is in state: ${FUNCTION_STATE}${NC}"
fi
