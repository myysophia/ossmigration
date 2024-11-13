import os
import logging

logger = logging.getLogger()

def get_s3_config():
    """获取 S3 配置"""
    config = {
        'region': os.environ.get('S3_REGION'),
        'bucket': os.environ.get('S3_BUCKET'),
        'prefix': os.environ.get('S3_PREFIX', 'mysql/')
    }
    
    # 验证必要的配置
    if not config['region'] or not config['bucket']:
        error_msg = f"Configuration error: Missing S3 configuration. region: {config['region']}, bucket: {config['bucket']}"
        logger.error(error_msg)
        raise ValueError(error_msg)
        
    logger.info(f"S3 config loaded: region={config['region']}, bucket={config['bucket']}, prefix={config['prefix']}")
    return config
