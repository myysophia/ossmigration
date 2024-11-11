import os
from utils.logger import get_logger

logger = get_logger(__name__)

class OSSConfig:
    def __init__(self, region):
        self.access_key = os.environ.get('ALIYUN_ACCESS_KEY')
        self.secret_key = os.environ.get('ALIYUN_SECRET_KEY')
        
        if not self.access_key or not self.secret_key:
            logger.error("Missing Aliyun credentials")
            raise ValueError("Missing required environment variables: ALIYUN_ACCESS_KEY or ALIYUN_SECRET_KEY")
            
        self.region = region
        self.config = self._get_oss_config()

    def _get_oss_config(self):
        """统一使用杭州的 bucket 配置"""
        return {
            'endpoint': 'oss-cn-hangzhou.aliyuncs.com',  # 杭州 endpoint
            'bucket': 'iotdb-backup',                    # 统一使用的 bucket
            'prefix': self._get_region_prefix()          # 根据源区域设置前缀
        }
    
    def _get_region_prefix(self):
        """根据源区域生成存储前缀，用于区分不同区域的备份"""
        region_mapping = {
            'ap-southeast-2': 'australia',
            'ap-south-1': 'india'
        }
        return f"rds-backup/{region_mapping.get(self.region, 'unknown')}"

def get_oss_config(region):
    return OSSConfig(region)
