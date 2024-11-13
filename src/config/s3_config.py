import os
import logging

logger = logging.getLogger()

def get_s3_config():
    """获取 S3 配置"""
    region = os.environ.get('S3_REGION')
    bucket = os.environ.get('S3_BUCKET')
    prefix = os.environ.get('S3_PREFIX', 'mysql/')
    
    # 打印调试信息
    logger.info(f"Loading S3 config - region: {region}, bucket: {bucket}, prefix: {prefix}")
    logger.info(f"All environment variables: {dict(os.environ)}")
    
    if not region or not bucket:
        error_msg = f"Configuration error: No S3 bucket configured for region: {region}, bucket: {bucket}"
        logger.error(error_msg)
        raise ValueError(error_msg)
    
    return {
        'region': region,
        'bucket': bucket,
        'prefix': prefix
    }
