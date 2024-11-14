#!/bin/bash

# 设置变量
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查命令行参数
if [ "$#" -ne 2 ]; then
    echo -e "${RED}Usage: $0 <region> <bucket>${NC}"
    echo -e "Example: $0 ap-south-1 in-novacloud-backup"
    exit 1
fi

AWS_REGION="$1"
S3_BUCKET="$2"

# 检查函数是否存在
if aws lambda get-function \
    --function-name rds-backup-to-oss \
    --region ${AWS_REGION} >/dev/null 2>&1; then
    
    echo -e "${YELLOW}Function exists in ${AWS_REGION}, updating...${NC}"
    ./update-function.sh "${AWS_REGION}" "${S3_BUCKET}"
else
    echo -e "${YELLOW}Function does not exist in ${AWS_REGION}, creating...${NC}"
    ./create-function.sh "${AWS_REGION}" "${S3_BUCKET}"
fi
