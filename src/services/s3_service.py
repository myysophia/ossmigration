import boto3
import logging
from config.s3_config import get_s3_config

logger = logging.getLogger()

class S3Downloader:
    def __init__(self):
        self.config = get_s3_config()
        self.s3_client = boto3.client(
            's3',
            region_name=self.config['region']
        )
        logger.info(f"Initialized S3 client for region: {self.config['region']}")

    def download_file(self, key: str, local_path: str) -> bool:
        try:
            logger.info(f"Downloading {key} from bucket {self.config['bucket']} to {local_path}")
            self.s3_client.download_file(
                self.config['bucket'],
                key,
                local_path
            )
            return True
        except Exception as e:
            logger.error(f"Failed to download file from S3: {str(e)}")
            return False
