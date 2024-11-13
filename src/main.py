import json
import logging
import os
from services.s3_service import S3Downloader
from services.oss_service import OSSUploader
from config.oss_config import get_oss_config
from config.s3_config import get_s3_config

# 配置日志
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        # 初始化配置
        s3_config = get_s3_config()
        oss_config = get_oss_config()
        
        logger.info("Initializing services...")
        s3_downloader = S3Downloader()
        oss_uploader = OSSUploader(oss_config)
        
        # 处理每个记录
        for record in event['Records']:
            # 获取 S3 对象信息
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # 验证 bucket
            if bucket != s3_config['bucket']:
                logger.warning(f"Skipping event for bucket {bucket}, expected {s3_config['bucket']}")
                continue
                
            # 验证前缀
            if not key.startswith(s3_config['prefix']):
                logger.warning(f"Skipping file {key}, doesn't match prefix {s3_config['prefix']}")
                continue
            
            # 下载和上传
            local_path = f"/tmp/{os.path.basename(key)}"
            logger.info(f"Processing file: {key}")
            
            if s3_downloader.download_file(key, local_path):
                if oss_uploader.upload_file(local_path, key):
                    logger.info(f"Successfully synchronized {key}")
                else:
                    logger.error(f"Failed to upload {key} to OSS")
            else:
                logger.error(f"Failed to download {key} from S3")
                
            # 清理临时文件
            if os.path.exists(local_path):
                os.remove(local_path)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Processing complete')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
