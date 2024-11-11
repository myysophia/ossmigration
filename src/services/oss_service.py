import oss2
from utils.logger import get_logger

logger = get_logger(__name__)

class OSSUploader:
    def __init__(self, oss_config):
        self.config = oss_config
        self.auth = oss2.Auth(
            oss_config.access_key,
            oss_config.secret_key
        )
        self.bucket = oss2.Bucket(
            self.auth,
            oss_config.config['endpoint'],
            oss_config.config['bucket']
        )

    def _get_oss_key(self, source_key):
        """生成带区域前缀的 OSS 对象键"""
        return f"{self.config.config['prefix']}/{source_key}"

    def upload_from_s3(self, s3_service, source_bucket, source_key, file_size):
        try:
            # 生成带区域前缀的目标键
            target_key = self._get_oss_key(source_key)
            logger.info(f"Preparing to upload file to OSS")
            logger.info(f"Source: s3://{source_bucket}/{source_key}")
            logger.info(f"Target: oss://{self.config.config['bucket']}/{target_key}")
            logger.info(f"File size: {file_size/1024/1024:.2f} MB")

            if file_size > 100 * 1024 * 1024:  # 100MB
                logger.info("Using multipart upload due to large file size")
                return self._multipart_upload(
                    s3_service,
                    source_bucket,
                    source_key,
                    target_key,
                    file_size
                )
            else:
                logger.info("Using simple upload for small file")
                return self._simple_upload(
                    s3_service,
                    source_bucket,
                    source_key,
                    target_key
                )
        except Exception as e:
            logger.error(f"Upload failed: {str(e)}", exc_info=True)
            raise

    def _simple_upload(self, s3_service, source_bucket, source_key, target_key):
        logger.info("Starting simple upload...")
        try:
            with s3_service.get_object(source_bucket, source_key) as s3_stream:
                logger.info("Successfully got object from S3")
                logger.info("Uploading to OSS...")
                result = self.bucket.put_object(target_key, s3_stream)
                logger.info(f"Upload completed with status: {result.status}")
                return {
                    'etag': result.etag,
                    'status': result.status,
                    'request_id': result.request_id,
                    'oss_key': target_key
                }
        except Exception as e:
            logger.error(f"Simple upload failed: {str(e)}", exc_info=True)
            raise

    def _multipart_upload(self, s3_service, source_bucket, source_key, target_key, total_size):
        logger.info("Starting multipart upload...")
        upload_id = self.bucket.init_multipart_upload(target_key).upload_id
        logger.info(f"Initialized multipart upload with ID: {upload_id}")
        
        try:
            part_size = 20 * 1024 * 1024  # 20MB per part
            total_parts = (total_size + part_size - 1) // part_size
            parts = []

            logger.info(f"Total parts: {total_parts}, Part size: {part_size/1024/1024:.2f} MB")

            for i in range(total_parts):
                start = i * part_size
                size = min(part_size, total_size - start)
                
                logger.info(f"Uploading part {i + 1}/{total_parts} ({size/1024/1024:.2f} MB)")
                
                # 从 S3 读取部分数据
                logger.info(f"Reading part from S3...")
                part_data = s3_service.get_object_range(
                    source_bucket,
                    source_key,
                    start,
                    size
                )
                
                # 上传分片
                logger.info(f"Uploading part to OSS...")
                result = self.bucket.upload_part(
                    target_key,
                    upload_id,
                    i + 1,
                    part_data
                )
                
                parts.append(oss2.models.PartInfo(i + 1, result.etag))
                logger.info(f"Successfully uploaded part {i + 1}/{total_parts}")
            
            # 完成分片上传
            logger.info("Completing multipart upload...")
            result = self.bucket.complete_multipart_upload(target_key, upload_id, parts)
            logger.info("Multipart upload completed successfully")
            
            return {
                'etag': result.etag,
                'status': result.status,
                'request_id': result.request_id,
                'oss_key': target_key
            }
            
        except Exception as e:
            logger.error(f"Multipart upload failed: {str(e)}", exc_info=True)
            logger.info(f"Aborting multipart upload: {upload_id}")
            self.bucket.abort_multipart_upload(target_key, upload_id)
            raise e
