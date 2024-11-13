import os
import logging

logger = logging.getLogger()

def get_oss_config():
    """获取 OSS 配置"""
    config = {
        'access_key_id': os.environ.get('ALIYUN_ACCESS_KEY'),
        'access_key_secret': os.environ.get('ALIYUN_SECRET_KEY'),
        'endpoint': os.environ.get('OSS_ENDPOINT'),
        'bucket_name': os.environ.get('OSS_BUCKET')
    }
    
    # 验证必要的配置
    missing_configs = [k for k, v in config.items() if not v]
    if missing_configs:
        error_msg = f"Missing OSS configurations: {', '.join(missing_configs)}"
        logger.error(error_msg)
        raise ValueError(error_msg)
    
    logger.info(f"OSS config loaded: endpoint={config['endpoint']}, bucket={config['bucket_name']}")
    return config
