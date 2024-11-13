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
NC='\033[0m'

# 创建测试事件
cat > ${PROJECT_ROOT}/tests/event.json << EOF
{
  "Records": [
    {
      "eventVersion": "2.1",
      "eventSource": "aws:s3",
      "awsRegion": "ap-southeast-2",
      "eventTime": "2024-01-20T00:00:00.000Z",
      "eventName": "ObjectCreated:Put",
      "s3": {
        "bucket": {
          "name": "novacloud-devops",
          "arn": "arn:aws:s3:::novacloud-devops"
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
    --payload file://${PROJECT_ROOT}/tests/event.json \
    --region ${AWS_REGION} \
    --cli-binary-format raw-in-base64-out \
    ${PROJECT_ROOT}/tests/response.json

# 检查响应
if [ $? -eq 0 ]; then
    echo -e "${GREEN}Function invoked successfully${NC}"
    echo "Response:"
    cat ${PROJECT_ROOT}/tests/response.json
    
    # 获取函数日志
    echo -e "\n${YELLOW}Recent function logs:${NC}"
    aws logs get-log-events \
        --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
        --log-stream-name $(aws logs describe-log-streams \
            --log-group-name "/aws/lambda/${FUNCTION_NAME}" \
            --order-by LastEventTime \
            --descending \
            --limit 1 \
            --query 'logStreams[0].logStreamName' \
            --output text) \
        --limit 20

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
endpoint = 'https://oss-ap-southeast-1.aliyuncs.com'
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
fi
