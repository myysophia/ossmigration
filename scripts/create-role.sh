#!/bin/bash

# 设置变量
ROLE_NAME="rds-backup-to-oss-role"
POLICY_NAME="rds-backup-to-oss-policy"
FUNCTION_NAME="rds-backup-to-oss"
AWS_REGION="ap-southeast-2"  # 默认区域

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Creating IAM role and policy for Lambda function...${NC}"

# 创建信任策略文档
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 创建 IAM 角色
echo "Creating IAM role..."
aws iam create-role \
    --role-name ${ROLE_NAME} \
    --assume-role-policy-document file://trust-policy.json

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to create IAM role${NC}"
    exit 1
fi

# 附加基础 Lambda 执行角色策略
echo "Attaching basic Lambda execution policy..."
aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# 创建自定义策略
echo "Creating custom policy..."
aws iam create-policy \
    --policy-name ${POLICY_NAME} \
    --policy-document file://policies/lambda-role-policy.json

# 获取账户 ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 附加自定义策略到角色
echo "Attaching custom policy to role..."
aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}

# 等待角色传播
echo "Waiting for role to propagate..."
sleep 10

echo -e "${GREEN}Successfully created IAM role and policy${NC}"

# 清理临时文件
rm -f trust-policy.json

# 输出角色 ARN
ROLE_ARN=$(aws iam get-role --role-name ${ROLE_NAME} --query Role.Arn --output text)
echo -e "${GREEN}Role ARN: ${ROLE_ARN}${NC}"

# 保存角色 ARN 到配置文件
echo "ROLE_ARN=${ROLE_ARN}" > .env
