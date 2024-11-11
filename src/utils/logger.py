import logging

def setup_logger():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    
    # 移除现有的处理器
    for handler in logger.handlers:
        logger.removeHandler(handler)
    
    # 添加控制台处理器
    handler = logging.StreamHandler()
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)
    
    return logger

def get_logger(name):
    return logging.getLogger(name)
