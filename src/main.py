import json
import logging
import os
from services.s3_service import S3Downloader
from services.oss_service import OSSUploader
from config.oss_config import get_oss_config
from config.s3_config import get_s3_config


logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        s3_config = get_s3_config()
        oss_config = get_oss_config()
        
        logger.info("Initializing services...")
        s3_downloader = S3Downloader()
        oss_uploader = OSSUploader(oss_config)

        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            if bucket != s3_config['bucket']:
                logger.warning(f"Skipping event for bucket {bucket}, expected {s3_config['bucket']}")
                continue
                
            if not key.startswith(s3_config['prefix']):
                logger.warning(f"Skipping file {key}, doesn't match prefix {s3_config['prefix']}")
                continue
            local_path = f"/tmp/{os.path.basename(key)}"
            logger.info(f"Processing file: {key}")
            
            if s3_downloader.download_file(key, local_path):
                if oss_uploader.upload_file(local_path, key):
                    logger.info(f"Successfully synchronized {key}")
                else:
                    logger.error(f"Failed to upload {key} to OSS")
            else:
                logger.error(f"Failed to download {key} from S3")
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
