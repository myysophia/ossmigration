import oss2
import logging
from pathlib import Path

logger = logging.getLogger()

class OSSUploader:
    def __init__(self, config):
        """
        初始化 OSS 上传器
        config: 包含 access_key_id, access_key_secret, endpoint, bucket_name 的字典
        """
        self.auth = oss2.Auth(
            config['access_key_id'],
            config['access_key_secret']
        )
        self.bucket = oss2.Bucket(
            self.auth,
            config['endpoint'],
            config['bucket_name']
        )
        logger.info(f"Initialized OSS uploader for bucket: {config['bucket_name']}")
    
    def upload_file(self, local_path: str, oss_path: str) -> bool:
        try:
            if not Path(local_path).exists():
                logger.error(f"Local file not found: {local_path}")
                return False
            
            logger.info(f"Uploading {local_path} to OSS path: {oss_path}")
            self.bucket.put_object_from_file(oss_path, local_path)
            
            if self.bucket.object_exists(oss_path):
                logger.info(f"Successfully uploaded file to OSS: {oss_path}")
                return True
            else:
                logger.error(f"Failed to verify uploaded file in OSS: {oss_path}")
                return False
                
        except Exception as e:
            logger.error(f"Failed to upload file to OSS: {str(e)}")
            return False
