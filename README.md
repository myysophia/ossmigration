


查看日志
 aws logs tail "/aws/lambda/rds-backup-to-oss" --follow

 更新函数

cd src
zip -r ../function.zip .
cd ..

aws lambda update-function-code \
    --function-name rds-backup-to-oss \
    --zip-file fileb://function.zip \
    --region ap-southeast-2

测试函数
aws lambda invoke --function-name rds-backup-to-oss --payload '{"Records": [{"s3": {"bucket": {"name": "iotdb-backup"}, "object": {"key": "rds-backup/australia/2024-11-13/iotdb-backup-2024-11-13-16-59-59.sql.gz"}}}]}' response.txt
部署函数
./scripts/update-function.sh

# 报错处理
## 确实配置
root - ERROR - Configuration error: No S3 bucket configured for region:

root - ERROR - Configuration error: Missing required environment variables: ALIYUN_ACCESS_KEY, ALIYUN_SECRET_KEY

## 缺少权限
 这个错误表明 Lambda 函数的 IAM 角色缺少 KMS 解密权限。
 Failed to download file from S3: An error occurred (AccessDenied) when calling the GetObject operation: User: arn:aws:sts::059012766390:assumed-role/rds-backup-to-oss-role/rds-backup-to-oss is not authorized to perform: kms:Decrypt on resource: arn:aws:kms:ap-southeast-2:059012766390:key/22584e80-f470-4c1a-9998-7e84cccf2b01 because no identity-based policy allows the kms:Decrypt action

 获取角色 ARN
ROLE_ARN=$(aws lambda get-function \
    --function-name rds-backup-to-oss \
    --query 'Configuration.Role' \
    --output text)

显示角色策略
aws iam list-attached-role-policies \
    --role-name $(echo $ROLE_ARN | cut -d'/' -f2)



# 架构



```mermaid
graph TD
    subgraph AWS Cloud Region: ap-south-1
        S3_IN[S3 Bucket:<br/>in-novacloud-backup] -->|Object Created Event| EventBridge_IN[EventBridge]
        EventBridge_IN -->|Trigger| Lambda_IN[Lambda Function]
    end

    subgraph AWS Cloud Region: ap-southeast-2
        S3_AU[S3 Bucket:<br/>novacloud-devops] -->|Object Created Event| EventBridge_AU[EventBridge]
        EventBridge_AU -->|Trigger| Lambda_AU[Lambda Function]
    end

    subgraph Lambda Components
        Lambda_IN & Lambda_AU -->|Invoke| IAM[IAM Role:<br/>rds-backup-to-oss-role]
        IAM -->|Permissions| Lambda_Handler[Lambda Handler]
        
        subgraph Lambda Runtime
            Lambda_Handler -->|1. Validate| Validator[Event & Credentials<br/>Validator]
            Lambda_Handler -->|2. Read| S3_Client[AWS S3 Client]
            Lambda_Handler -->|3. Upload| OSS_Client[Aliyun OSS Client]
            
            S3_Client -->|Get Object| S3_Stream[S3 Object Stream]
            S3_Stream -->|Stream Data| OSS_Client
            
            subgraph Memory Management
                S3_Stream -->|Large Files > 100MB| Multipart[Multipart Upload]
                S3_Stream -->|Small Files <= 100MB| Simple[Simple Upload]
            end
        end
    end

    subgraph Aliyun Cloud Region: cn-hangzhou
        OSS_Client -->|Upload| OSS_Bucket[OSS Bucket:<br/>iotdb-backup]
        
        subgraph OSS Storage Structure
            OSS_Bucket -->|India Backups| India[/rds-backup/india/mysql/backups/]
            OSS_Bucket -->|Australia Backups| Australia[/rds-backup/australia/mysql/backups/]
        end
    end

    subgraph Security & Configuration
        KMS[AWS KMS] -->|Encrypt| Secrets[Secrets Manager]
        Secrets -->|Provide| Credentials[AWS & Aliyun<br/>Credentials]
        Credentials -->|Access| Lambda_Handler
    end

    subgraph Monitoring & Logging
        Lambda_Handler -->|Logs| CloudWatch[CloudWatch Logs]
        CloudWatch -->|Metrics| Dashboard[CloudWatch Dashboard]
        Dashboard -->|Alerts| SNS[SNS Topic]
    end

    style Lambda_Handler fill:#f9f,stroke:#333,stroke-width:4px
    style OSS_Bucket fill:#ff9,stroke:#333,stroke-width:4px
    style S3_IN,S3_AU fill:#9cf,stroke:#333,stroke-width:2px
```

