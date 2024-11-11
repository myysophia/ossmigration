import os
import boto3
from botocore.exceptions import ClientError
from utils.logger import get_logger

logger = get_logger(__name__)

class S3Service:
    def __init__(self):
        self.access_key = os.environ.get('AWS_ACCESS_KEY_ID')
        self.secret_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
        
        if not self.access_key or not self.secret_key:
            logger.error("Missing AWS credentials")
            raise ValueError("Missing required environment variables: AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY")
        
        # S3 bucket 配置
        self.bucket_mapping = {
            'ap-south-1': 'in-novacloud-backup',
            'ap-southeast-2': 'novacloud-devops'
        }
            
        self.client = boto3.client(
            's3',
            aws_access_key_id=self.access_key,
            aws_secret_access_key=self.secret_key
        )

    def get_bucket_for_region(self, region):
        """根据区域获取对应的 bucket 名称"""
        bucket = self.bucket_mapping.get(region)
        if not bucket:
            raise ValueError(f"No S3 bucket configured for region: {region}")
        return bucket

    def get_file_info(self, region, key):
        """根据区域和文件键获取文件信息"""
        try:
            bucket = self.get_bucket_for_region(region)
            head = self.client.head_object(Bucket=bucket, Key=key)
            
            return {
                'size': head['ContentLength'],
                'etag': head['ETag'],
                'region': region,
                'bucket': bucket
            }
        except ClientError as e:
            logger.error(f"Failed to get file info: {str(e)}")
            raise

    def get_object(self, region, key):
        """根据区域和文件键获取对象"""
        bucket = self.get_bucket_for_region(region)
        return self.client.get_object(
            Bucket=bucket,
            Key=key
        )['Body']

    def get_object_range(self, region, key, start, size):
        """获取对象的指定范围"""
        bucket = self.get_bucket_for_region(region)
        response = self.client.get_object(
            Bucket=bucket,
            Key=key,
            Range=f'bytes={start}-{start+size-1}'
        )
        return response['Body'].read()
