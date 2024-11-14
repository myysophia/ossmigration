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

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查环境变量
if [ -z "${ALIYUN_ACCESS_KEY}" ] || [ -z "${ALIYUN_SECRET_KEY}" ]; then
    echo -e "${RED}Please set ALIYUN_ACCESS_KEY and ALIYUN_SECRET_KEY environment variables${NC}"
    exit 1
fi

# 创建测试事件
mkdir -p ${PROJECT_ROOT}/test
cat > ${PROJECT_ROOT}/test/event.json << EOF
{
  "Records": [
    {
      "eventVersion": "2.1",
      "eventSource": "aws:s3",
      "awsRegion": "${AWS_REGION}",
      "eventTime": "2024-01-20T00:00:00.000Z",
      "eventName": "ObjectCreated:Put",
      "s3": {
        "bucket": {
          "name": "${S3_BUCKET}",
          "arn": "arn:aws:s3:::${S3_BUCKET}"
        },
        "object": {
          "key": "mysql/test.sql",
          "size": 1024,
          "eTag": "test-etag"
        }
      }
    }
  ]
}
EOF

# 调用函数
echo -e "${YELLOW}Invoking Lambda function...${NC}"
aws lambda invoke \
    --function-name ${FUNCTION_NAME} \
    --payload file://${PROJECT_ROOT}/test/event.json \
    --region ${AWS_REGION} \
    --cli-binary-format raw-in-base64-out \
    ${PROJECT_ROOT}/test/response.json

# 检查响应
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Function invoked successfully${NC}"
    echo "Response:"
    cat ${PROJECT_ROOT}/test/response.json
    
    # 获取函数日志
    echo -e "\n${YELLOW}Recent function logs:${NC}"
    # 等待几秒让日志可用
    sleep 5
    
    # 获取最新的日志流
    LOG_STREAM=$(aws logs describe-log-streams \
        --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
        --region ${AWS_REGION} \
        --order-by LastEventTime \
        --descending \
        --limit 1 \
        --query 'logStreams[0].logStreamName' \
        --output text)
    
    if [ ! -z "${LOG_STREAM}" ]; then
        aws logs get-log-events \
            --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
            --log-stream-name ${LOG_STREAM} \
            --region ${AWS_REGION} \
            --limit 20 \
            --query 'events[*].message' \
            --output text
    else
        echo -e "${RED}No log streams found${NC}"
    fi

    # 等待几秒让文件同步完成
    echo -e "\n${YELLOW}Waiting for file synchronization...${NC}"
    sleep 5

    # 验证 OSS 文件
    echo -e "\n${YELLOW}Verifying file in Aliyun OSS...${NC}"
    python3 - << EOF
import oss2
import os
from datetime import datetime

# OSS 配置
access_key_id = os.getenv('ALIYUN_ACCESS_KEY')
access_key_secret = os.getenv('ALIYUN_SECRET_KEY')
endpoint = 'https://oss-cn-hangzhou.aliyuncs.com'
bucket_name = 'iotdb-backup'

# 初始化 OSS 客户端
auth = oss2.Auth(access_key_id, access_key_secret)
bucket = oss2.Bucket(auth, endpoint, bucket_name)

# 列出最近的文件
print("Recent files in OSS bucket:")
for obj in bucket.list_objects(prefix='mysql/').object_list:
    # 获取文件的最后修改时间
    last_modified = obj.last_modified.strftime('%Y-%m-%d %H:%M:%S')
    print(f"- {obj.key} (Last modified: {last_modified})")
EOF

else
    echo -e "${RED}Function invocation failed${NC}"
    exit 1
fi
