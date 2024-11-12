#!/bin/bash

# 设置变量
FUNCTION_NAME="rds-backup-to-oss"
AWS_REGION="ap-southeast-2"
BUCKETS=("novacloud-devops")
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
CONFIG_DIR="${PROJECT_ROOT}/config"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查必要工具
command -v jq >/dev/null 2>&1 || { echo -e "${RED}jq is required but not installed.${NC}" >&2; exit 1; }

# 检查配置文件
if [ ! -f "${CONFIG_DIR}/s3-notification-template.json" ]; then
    echo -e "${RED}Missing s3-notification-template.json${NC}"
    exit 1
fi

# 检查是否存在 .env 文件
if [ ! -f "${PROJECT_ROOT}/.env" ]; then
    echo -e "${RED}Missing .env file. Please run create-role.sh first.${NC}"
    exit 1
fi

# 加载 ROLE_ARN
source "${PROJECT_ROOT}/.env"

if [ -z "${ROLE_ARN}" ]; then
    echo -e "${RED}Missing ROLE_ARN in .env file${NC}"
    exit 1
fi

# 获取 AWS 账户 ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "${ACCOUNT_ID}" ]; then
    echo -e "${RED}Failed to get AWS account ID${NC}"
    exit 1
fi

echo -e "${YELLOW}Creating Lambda function...${NC}"

# 检查函数是否已存在
if aws lambda get-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION} &>/dev/null; then
    echo -e "${YELLOW}Function already exists. Deleting...${NC}"
    aws lambda delete-function --function-name ${FUNCTION_NAME} --region ${AWS_REGION}
    echo "Waiting for function deletion..."
    sleep 10
fi

# 创建函数
aws lambda create-function \
    --function-name ${FUNCTION_NAME} \
    --runtime python3.9 \
    --handler main.lambda_handler \
    --role ${ROLE_ARN} \
    --timeout 300 \
    --memory-size 512 \
    --region ${AWS_REGION} \
    --zip-file fileb://${PROJECT_ROOT}/function.zip

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created Lambda function${NC}"
    
    # 配置环境变量
    echo "Configuring environment variables..."
    aws lambda update-function-configuration \
        --function-name ${FUNCTION_NAME} \
        --region ${AWS_REGION} \
        --environment "Variables={AWS_REGION=${AWS_REGION}}"
    
    # 获取 Lambda 函数 ARN
    LAMBDA_ARN=$(aws lambda get-function --function-name ${FUNCTION_NAME} \
        --region ${AWS_REGION} --query 'Configuration.FunctionArn' --output text)
    
    if [ -z "${LAMBDA_ARN}" ]; then
        echo -e "${RED}Failed to get Lambda function ARN${NC}"
        exit 1
    fi
    
    # 配置 S3 触发器
    echo "Configuring S3 triggers..."

    
    for BUCKET in "${BUCKETS[@]}"; do
        echo "Processing bucket: ${BUCKET}"
        
        # 1. 添加 Lambda 权限
        echo "Adding Lambda permission for ${BUCKET}..."
        aws lambda add-permission \
            --function-name ${FUNCTION_NAME} \
            --statement-id "S3Trigger${BUCKET}" \
            --action "lambda:InvokeFunction" \
            --principal s3.amazonaws.com \
            --source-arn "arn:aws:s3:::${BUCKET}" \
            --source-account "${ACCOUNT_ID}" \
            --region ${AWS_REGION} || true
        
        # 2. 等待权限生效
        echo "Waiting for permissions to propagate..."
        sleep 5
        
        # 3. 准备通知配置
        echo "Preparing notification configuration..."
        NOTIFICATION_CONFIG=$(cat ${CONFIG_DIR}/s3-notification-template.json | \
            jq --arg arn "${LAMBDA_ARN}" \
            '.LambdaFunctionConfigurations[0].LambdaFunctionArn = $arn')
        
        # 4. 配置 S3 触发器
        echo "Adding S3 trigger for ${BUCKET}..."
        aws s3api put-bucket-notification-configuration \
            --bucket ${BUCKET} \
            --notification-configuration "${NOTIFICATION_CONFIG}" || {
                echo -e "${RED}Failed to configure trigger for ${BUCKET}${NC}"
                continue
            }
        
        echo -e "${GREEN}Successfully configured trigger for ${BUCKET}${NC}"
    done
    
    echo -e "${GREEN}Lambda function setup complete${NC}"
    echo -e "${GREEN}Function ARN: ${LAMBDA_ARN}${NC}"
else
    echo -e "${RED}Failed to create Lambda function${NC}"
    exit 1
fi