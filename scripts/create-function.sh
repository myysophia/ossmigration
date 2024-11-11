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

echo -e "${YELLOW}Creating Lambda function...${NC}"

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
    
    # 配置 S3 触发器
    echo "Configuring S3 triggers..."
    # 为每个 bucket 添加触发器
    BUCKETS=("in-novacloud-backup" "novacloud-devops")
    
    for BUCKET in "${BUCKETS[@]}"; do
        echo "Adding trigger for bucket: ${BUCKET}"
        aws s3api put-bucket-notification-configuration \
            --bucket ${BUCKET} \
            --notification-configuration "{
                \"LambdaFunctionConfigurations\": [{
                    \"LambdaFunctionArn\": \"arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}\",
                    \"Events\": [\"s3:ObjectCreated:*\"],
                    \"Filter\": {
                        \"Key\": {
                            \"FilterRules\": [{
                                \"Name\": \"prefix\",
                                \"Value\": \"mysql/\"
                            }]
                        }
                    }
                }]
            }"
    done
    
    echo -e "${GREEN}Lambda function setup complete${NC}"
else
    echo -e "${RED}Failed to create Lambda function${NC}"
    exit 1
fi
