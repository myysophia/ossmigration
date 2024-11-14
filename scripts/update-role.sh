#!/bin/bash

# 设置变量
FUNCTION_NAME="rds-backup-to-oss"
ROLE_NAME="rds-backup-to-oss-role"
AWS_REGION="ap-southeast-2"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR" && pwd )"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 创建 KMS 策略
echo -e "${YELLOW}Creating KMS policy...${NC}"
POLICY_ARN=$(aws iam create-policy \
    --policy-name "${FUNCTION_NAME}-kms-policy" \
    --policy-document file://${PROJECT_ROOT}/policies/kms-policy.json \
    --query 'Policy.Arn' \
    --output text)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully created KMS policy${NC}"
else
    echo -e "${RED}Failed to create KMS policy${NC}"
    exit 1
fi

# 附加策略到角色
echo -e "${YELLOW}Attaching policy to role...${NC}"
aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn ${POLICY_ARN}

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Successfully attached policy to role${NC}"
else
    echo -e "${RED}Failed to attach policy to role${NC}"
    exit 1
fi

# 显示角色策略
echo -e "${YELLOW}Current role policies:${NC}"
aws iam list-attached-role-policies --role-name ${ROLE_NAME}
