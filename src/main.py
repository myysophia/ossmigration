import json
from services.oss_service import OSSUploader
from services.s3_service import S3Service
from config.oss_config import get_oss_config
from utils.logger import setup_logger
from utils.validators import validate_credentials, validate_s3_event

logger = setup_logger()

def lambda_handler(event, context):
    try:
        logger.info("Starting lambda handler execution")
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # 验证环境变量
        logger.info("Validating environment variables...")
        validate_credentials()
        logger.info("Environment variables validation successful")
        
        # 验证事件
        logger.info("Validating S3 event...")
        s3_info = validate_s3_event(event)
        if not s3_info:
            logger.warning("Invalid or skipped S3 event")
            return {
                'statusCode': 400,
                'body': 'Invalid S3 event'
            }

        source_key = s3_info['key']
        region = s3_info['region']
        logger.info(f"Processing file: {source_key} from region: {region}")

        # 初始化服务
        logger.info("Initializing S3 service...")
        s3_service = S3Service()
        
        # 获取源文件信息
        logger.info(f"Getting file info for {source_key}")
        file_info = s3_service.get_file_info(region, source_key)
        logger.info(f"File info: size={file_info['size']} bytes, bucket={file_info['bucket']}")
        
        # 获取 OSS 配置
        logger.info("Getting OSS configuration...")
        oss_config = get_oss_config(region)
        logger.info(f"OSS configuration: bucket={oss_config.config['bucket']}, endpoint={oss_config.config['endpoint']}")
        
        # 初始化 OSS 上传器
        logger.info("Initializing OSS uploader...")
        uploader = OSSUploader(oss_config)
        
        # 执行上传
        logger.info(f"Starting file upload to OSS, file size: {file_info['size']} bytes")
        result = uploader.upload_from_s3(
            s3_service,
            region,
            source_key,
            file_info['size']
        )
        logger.info("File upload completed successfully")

        response = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'File successfully copied to OSS',
                'source': {
                    'bucket': file_info['bucket'],
                    'key': source_key,
                    'region': region
                },
                'destination': {
                    'bucket': oss_config.config['bucket'],
                    'key': result['oss_key'],
                    'region': 'cn-hangzhou'
                },
                'details': result
            }, indent=2)
        }
        logger.info(f"Lambda execution completed successfully: {json.dumps(response, indent=2)}")
        return response

    except ValueError as e:
        error_msg = f"Configuration error: {str(e)}"
        logger.error(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Configuration error',
                'message': str(e)
            }, indent=2)
        }
    except Exception as e:
        error_msg = f"Error in lambda_handler: {str(e)}"
        logger.error(error_msg, exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal error',
                'message': str(e)
            }, indent=2)
        }
