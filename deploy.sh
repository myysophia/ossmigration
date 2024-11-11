#!/bin/bash

# 设置变量
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
FUNCTION_NAME="rds-backup-to-oss"
AWS_REGION="ap-southeast-2"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查必要的工具
echo -e "${YELLOW}Checking required tools...${NC}"
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed.${NC}" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo -e "${RED}Python3 is required but not installed.${NC}" >&2; exit 1; }
command -v pip3 >/dev/null 2>&1 || { echo -e "${RED}pip3 is required but not installed.${NC}" >&2; exit 1; }

# 检查 AWS 凭证
echo "Checking AWS credentials..."
aws sts get-caller-identity > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${RED}AWS credentials not configured properly${NC}"
    exit 1
fi

# 创建 IAM 角色（如果不存在）
if [ ! -f .env ] || [ ! -s .env ]; then
    echo -e "${YELLOW}Creating new IAM role...${NC}"
    bash ${SCRIPT_DIR}/scripts/create-role.sh
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to create IAM role${NC}"
        exit 1
    fi
fi

# 加载环境变量
source .env

# 检查 Lambda 函数是否存在
aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Creating new Lambda function...${NC}"
    
    # 创建临时部署包
    BUILD_DIR=$(mktemp -d)
    cp -r src/* ${BUILD_DIR}/
    cp requirements.txt ${BUILD_DIR}/
    
    # 安装依赖
    pip3 install -r requirements.txt -t ${BUILD_DIR} --no-cache-dir
    
    # 创建 zip 包
    cd ${BUILD_DIR}
    zip -r9 ../function.zip .
    cd - > /dev/null
    
    # 创建 Lambda 函数
    aws lambda create-function \
        --function-name ${FUNCTION_NAME} \
        --runtime python3.9 \
        --handler main.lambda_handler \
        --role ${ROLE_ARN} \
        --zip-file fileb://function.zip \
        --timeout 900 \
        --memory-size 1024 \
        --region ${AWS_REGION}
    
    # 清理临时文件
    rm -rf ${BUILD_DIR}
    rm -f function.zip
else
    echo -e "${YELLOW}Updating existing Lambda function...${NC}"
    bash ${SCRIPT_DIR}/scripts/update-function.sh
fi

# 检查必要的环境变量
check_required_env() {
    local missing_vars=()
    
    # AWS 凭证
    [ -z "$AWS_ACCESS_KEY_ID" ] && missing_vars+=("AWS_ACCESS_KEY_ID")
    [ -z "$AWS_SECRET_ACCESS_KEY" ] && missing_vars+=("AWS_SECRET_ACCESS_KEY")
    
    # 阿里云凭证
    [ -z "$ALIYUN_ACCESS_KEY" ] && missing_vars+=("ALIYUN_ACCESS_KEY")
    [ -z "$ALIYUN_SECRET_KEY" ] && missing_vars+=("ALIYUN_SECRET_KEY")
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        echo -e "${RED}Missing required environment variables:${NC}"
        printf '%s\n' "${missing_vars[@]}"
        exit 1
    fi
}

echo -e "${YELLOW}Checking required environment variables...${NC}"
check_required_env

# 配置 Lambda 环境变量
echo "Configuring environment variables..."
aws lambda update-function-configuration \
    --function-name ${FUNCTION_NAME} \
    --environment "Variables={
        ALIYUN_ACCESS_KEY=${ALIYUN_ACCESS_KEY},
        ALIYUN_SECRET_KEY=${ALIYUN_SECRET_KEY},
        AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID},
        AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
    }" \
    --region ${AWS_REGION}

# 配置 S3 触发器
echo "Configuring S3 triggers..."
for BUCKET in "novacloud-devops" "in-novacloud-backup"; do
    aws s3api put-bucket-notification-configuration \
        --bucket ${BUCKET} \
        --notification-configuration file://config/s3-notification.json
done

echo -e "${GREEN}Deployment completed successfully${NC}"
