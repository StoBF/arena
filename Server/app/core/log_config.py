import logging.config

def setup_logging():
    logging_config = {
        'version': 1,
        'disable_existing_loggers': False,
        'formatters': {
            'default': {
                'format': '[%(asctime)s] %(levelname)s in %(module)s: %(message)s',
            },
        },
        'handlers': {
            'console': {
                'class': 'logging.StreamHandler',
                'formatter': 'default',
                'level': 'INFO',
            },
            'file': {
                'class': 'logging.FileHandler',
                'formatter': 'default',
                'filename': 'server.log',
                'level': 'INFO',
                'mode': 'a',
            },
        },
        'root': {
            'handlers': ['console', 'file'],
            'level': 'INFO',
        },
        'loggers': {
            'uvicorn.error': {
                'level': 'INFO',
                'handlers': ['console', 'file'],
                'propagate': False,
            },
            'uvicorn.access': {
                'level': 'WARNING',
                'handlers': ['console', 'file'],
                'propagate': False,
            },
        },
    }
    logging.config.dictConfig(logging_config) 