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
CONFIG_DIR="${PROJECT_ROOT}/config"
ZIP_FILE="${PROJECT_ROOT}/function.zip"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 创建 IAM 角色
echo -e "${YELLOW}Creating IAM role...${NC}"
ROLE_NAME="rds-backup-to-oss-role"
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}'

# 创建角色
aws iam create-role \
    --role-name ${ROLE_NAME} \
    --assume-role-policy-document "${TRUST_POLICY}" || true

# 添加策略
aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/AWSLambdaExecute

# 创建 S3 访问策略
S3_POLICY='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::'${S3_BUCKET}'",
                "arn:aws:s3:::'${S3_BUCKET}'/mysql/*"
            ]
        }
    ]
}'

aws iam put-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-name "S3Access" \
    --policy-document "${S3_POLICY}"

# 等待角色创建完成
echo "Waiting for role to be ready..."
sleep 10

# 获取角色 ARN
ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query 'Role.Arn' --output text)

if [ -z "${ROLE_ARN}" ]; then
    echo -e "${RED}Failed to get role ARN${NC}"
    exit 1
fi

# 创建部署包
echo -e "${YELLOW}Creating deployment package...${NC}"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf ${BUILD_DIR}' EXIT

# 复制源代码
cp -r ${PROJECT_ROOT}/src/* ${BUILD_DIR}/

# 安装依赖
pip3 install -r ${PROJECT_ROOT}/requirements.txt -t ${BUILD_DIR} --no-cache-dir

# 创建 ZIP 文件
cd ${BUILD_DIR}
zip -r9 ${ZIP_FILE} .
cd - > /dev/null

# 创建函数
aws lambda create-function \
    --function-name ${FUNCTION_NAME} \
    --runtime python3.9 \
    --handler main.lambda_handler \
    --role ${ROLE_ARN} \
    --timeout 300 \
    --memory-size 512 \
    --region ${AWS_REGION} \
    --environment "Variables={
        ALIYUN_ACCESS_KEY=${ALIYUN_ACCESS_KEY},
        ALIYUN_SECRET_KEY=${ALIYUN_SECRET_KEY},
        OSS_ENDPOINT=https://oss-cn-hangzhou.aliyuncs.com,
        OSS_BUCKET=iotdb-backup,
        S3_REGION=${AWS_REGION},
        S3_BUCKET=${S3_BUCKET},
        S3_PREFIX=mysql/
    }" \
    --zip-file fileb://${ZIP_FILE}

# 配置 S3 触发器函数
configure_s3_trigger() {
    local FUNCTION_NAME=$1
    local AWS_REGION=$2
    local S3_BUCKET=$3
    local LAMBDA_ARN=$4
    local ACCOUNT_ID=$5
    
    echo "Configuring S3 trigger for bucket: ${S3_BUCKET}"
    
    # 1. 添加 Lambda 权限
    echo "Adding Lambda permission for ${S3_BUCKET}..."
    aws lambda add-permission \
        --function-name ${FUNCTION_NAME} \
        --statement-id "S3Trigger${S3_BUCKET}" \
        --action "lambda:InvokeFunction" \
        --principal s3.amazonaws.com \
        --source-arn "arn:aws:s3:::${S3_BUCKET}" \
        --source-account "${ACCOUNT_ID}" \
        --region ${AWS_REGION} 2>/dev/null || true
    
    # 2. 等待权限生效
    echo "Waiting for permissions to propagate..."
    sleep 5
    
    # 3. 准备通知配置
    echo "Preparing notification configuration..."
    NOTIFICATION_CONFIG=$(cat ${CONFIG_DIR}/s3-notification-template.json | \
        jq --arg arn "${LAMBDA_ARN}" \
        '.LambdaFunctionConfigurations[0].LambdaFunctionArn = $arn')
    
    # 4. 配置 S3 触发器
    echo "Adding S3 trigger for ${S3_BUCKET}..."
    if aws s3api put-bucket-notification-configuration \
        --bucket ${S3_BUCKET} \
        --notification-configuration "${NOTIFICATION_CONFIG}"; then
        echo -e "${GREEN}Successfully configured trigger for ${S3_BUCKET}${NC}"
        return 0
    else
        echo -e "${RED}Failed to configure trigger for ${S3_BUCKET}${NC}"
        return 1
    fi
}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created Lambda function${NC}"
    
    # 获取 Lambda 函数 ARN
    LAMBDA_ARN=$(aws lambda get-function --function-name ${FUNCTION_NAME} \
        --region ${AWS_REGION} --query 'Configuration.FunctionArn' --output text)
    
    if [ -z "${LAMBDA_ARN}" ]; then
        echo -e "${RED}Failed to get Lambda function ARN${NC}"
        exit 1
    fi
    
    # 配置 S3 触发器
    echo "Configuring S3 trigger..."
    configure_s3_trigger "${FUNCTION_NAME}" "${AWS_REGION}" "${S3_BUCKET}" "${LAMBDA_ARN}" "${ACCOUNT_ID}"
    
    echo -e "${GREEN}Lambda function setup complete${NC}"
    echo -e "${GREEN}Function ARN: ${LAMBDA_ARN}${NC}"
else
    echo -e "${RED}Failed to create Lambda function${NC}"
    exit 1
fi