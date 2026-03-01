import logging.config
import os
import sys


def _configure_console_encoding() -> None:
    """
    Make console logging safe on Windows cp1251 terminals.
    If UTF-8 cannot be applied, fallback to backslash escapes instead of crashing.
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            if hasattr(stream, "reconfigure"):
                stream.reconfigure(encoding="utf-8", errors="backslashreplace")
        except Exception:
            # Keep startup resilient even if stream cannot be reconfigured
            pass

def setup_logging():
    _configure_console_encoding()

    # Keep log file next to server code and enforce UTF-8 on all platforms.
    log_file = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "server.log")

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
                'filename': log_file,
                'encoding': 'utf-8',
                'errors': 'backslashreplace',
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