import aiosmtplib
from email.mime.text import MIMEText
from app.core.config import settings

async def send_email(to_email: str, subject: str, body: str):
    msg = MIMEText(body)
    msg["Subject"] = subject
    msg["From"] = settings.EMAIL_FROM
    msg["To"] = to_email
    smtp_kwargs = {}
    if getattr(settings, "EMAIL_USE_TLS", False):
        smtp_kwargs["start_tls"] = True
    server = aiosmtplib.SMTP(
        hostname=settings.EMAIL_HOST,
        port=settings.EMAIL_PORT,
        **smtp_kwargs
    )
    await server.connect()
    if getattr(settings, "EMAIL_HOST_USER", None):
        await server.login(settings.EMAIL_HOST_USER, settings.EMAIL_HOST_PASSWORD)
    await server.send_message(msg)
    await server.quit() 