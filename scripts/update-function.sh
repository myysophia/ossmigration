#!/bin/bash

# 检查命令行参数
if [ "$#" -ne 2 ]; then
    echo -e "${RED}Usage: $0 <region> <bucket>${NC}"
    echo -e "Example: $0 ap-south-1 in-novacloud-backup"
    exit 1
fi

# 设置变量
FUNCTION_NAME="rds-backup-to-oss"
AWS_REGION="$1"
S3_BUCKET="$2"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
ZIP_FILE="${PROJECT_ROOT}/function.zip"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否安装了必要的工具
command -v python3 >/dev/null 2>&1 || { echo -e "${RED}Python3 is required but not installed.${NC}" >&2; exit 1; }
command -v pip3 >/dev/null 2>&1 || { echo -e "${RED}pip3 is required but not installed.${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed.${NC}" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo -e "${RED}zip is required but not installed.${NC}" >&2; exit 1; }

# 创建临时构建目录
BUILD_DIR=$(mktemp -d)
echo -e "${YELLOW}Creating temporary build directory: ${BUILD_DIR}${NC}"

# 清理函数
cleanup() {
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    rm -rf "${BUILD_DIR}"
    # 不要删除 ZIP 文件，可能需要用于调试
    echo -e "${YELLOW}Deployment package saved at: ${ZIP_FILE}${NC}"
}
trap cleanup EXIT

# 检查并创建必要的目录
echo "Checking directory structure..."
if [ ! -d "${PROJECT_ROOT}/src" ]; then
    echo -e "${RED}Source directory not found: ${PROJECT_ROOT}/src${NC}"
    exit 1
fi

# 复制源代码到构建目录
echo "Copying source files..."
cp -r ${PROJECT_ROOT}/src/* ${BUILD_DIR}/
cp ${PROJECT_ROOT}/requirements.txt ${BUILD_DIR}/

# 安装依赖
echo "Installing dependencies..."
pip3 install -r ${BUILD_DIR}/requirements.txt -t ${BUILD_DIR} --no-cache-dir

# 删除不必要的文件
echo "Cleaning up unnecessary files..."
find ${BUILD_DIR} -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
find ${BUILD_DIR} -type f -name "*.pyc" -delete
find ${BUILD_DIR} -type f -name "*.pyo" -delete
find ${BUILD_DIR} -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null
find ${BUILD_DIR} -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null

# 创建部署包
echo "Creating deployment package..."
cd ${BUILD_DIR}
if ! zip -r9 "${ZIP_FILE}" . > /dev/null; then
    echo -e "${RED}Failed to create deployment package${NC}"
    exit 1
fi
cd - > /dev/null

# 检查 ZIP 文件是否创建成功
if [ ! -f "${ZIP_FILE}" ]; then
    echo -e "${RED}Failed to create deployment package: ${ZIP_FILE}${NC}"
    exit 1
fi

echo -e "${GREEN}Successfully created deployment package: ${ZIP_FILE}${NC}"
echo "Package size: $(du -h "${ZIP_FILE}" | cut -f1)"

# 更新函数代码
echo "Updating Lambda function..."
if ! aws lambda update-function-code \
    --function-name ${FUNCTION_NAME} \
    --zip-file fileb://${ZIP_FILE} \
    --region ${AWS_REGION}; then
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
    echo -e "${GREEN}Successfully updated Lambda function${NC}"
else
    echo -e "${RED}Function is in state: ${FUNCTION_STATE}${NC}"
    exit 1
fi

# 更新函数配置
echo "Updating Lambda function configuration..."
aws lambda update-function-configuration \
    --function-name ${FUNCTION_NAME} \
    --region ${AWS_REGION} \
    --environment "Variables={
        ALIYUN_ACCESS_KEY=${ALIYUN_ACCESS_KEY},
        ALIYUN_SECRET_KEY=${ALIYUN_SECRET_KEY},
        OSS_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com,
        OSS_BUCKET=iotdb-backup,
        S3_REGION=${AWS_REGION},
        S3_BUCKET=${S3_BUCKET},
        S3_PREFIX=mysql/
    }"
