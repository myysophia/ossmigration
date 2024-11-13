import os
from utils.logger import get_logger
from services.oss_service import OSSUploader
from config.oss_config import get_oss_config

logger = get_logger(__name__)

def validate_credentials():
    """验证所需的环境变量是否存在"""
    required_vars = [
        'AWS_ACCESS_KEY_ID',
        'AWS_SECRET_ACCESS_KEY',
        'ALIYUN_ACCESS_KEY',
        'ALIYUN_SECRET_KEY'
    ]
    
    missing_vars = [var for var in required_vars if not os.environ.get(var)]
    
    if missing_vars:
        error_msg = f"Missing required environment variables: {', '.join(missing_vars)}"
        logger.error(error_msg)
        raise ValueError(error_msg)

def validate_s3_event(event):
    """验证并提取 S3 事件信息"""
    try:
        if 'Records' not in event or len(event['Records']) == 0:
            return None
            
        record = event['Records'][0]['s3']
        source_key = record['object']['key']
        
        # 从 S3 ARN 中提取区域
        bucket_arn = record['bucket']['arn']
        region = bucket_arn.split(':')[3]
        
        # 验证是否是 RDS 备份文件
        if not source_key.startswith('mysql/'):
            logger.info(f"Skipping non-backup file: {source_key}")
            return None
            
        return {
            'key': source_key,
            'region': region
        }
    except Exception as e:
        logger.error(f"Event validation failed: {str(e)}")
        return None

def test_oss_connection():
    try:
        config = get_oss_config()
        uploader = OSSUploader(config)
        # 测试列出 bucket
        bucket_info = uploader.bucket.get_bucket_info()
        print(f"Successfully connected to OSS bucket: {bucket_info.name}")
        return True
    except Exception as e:
        print(f"Failed to connect to OSS: {str(e)}")
        return False

if __name__ == "__main__":
    test_oss_connection()
