import asyncio
import smtplib
from email.message import EmailMessage
from pathlib import Path

from app.config import settings


def _render_verification_subject(purpose: str) -> str:
    if str(purpose) == "bind":
        return "FCM 账号邮箱绑定验证"
    return "FCM 账号邮箱验证"


def _render_verification_body(recipient: str, verification_url: str, purpose: str) -> str:
    action = "完成邮箱绑定" if str(purpose) == "bind" else "完成账号注册"
    return (
        f"你好，{recipient}：\n\n"
        f"请打开下面的链接以{action}：\n"
        f"{verification_url}\n\n"
        f"如果这不是你的操作，请忽略这封邮件。\n"
    )


def _send_via_smtp(recipient: str, subject: str, body: str) -> None:
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = settings.smtp_from
    msg["To"] = recipient
    msg.set_content(body)

    with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
        if settings.smtp_use_tls:
            smtp.starttls()
        if settings.smtp_username:
            smtp.login(settings.smtp_username, settings.smtp_password)
        smtp.send_message(msg)


def _append_debug_mail(recipient: str, subject: str, body: str) -> None:
    path = Path(settings.email_log_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as fp:
        fp.write(f"TO: {recipient}\n")
        fp.write(f"SUBJECT: {subject}\n")
        fp.write(body)
        fp.write("\n---\n")


async def send_verification_email(recipient: str, verification_url: str, purpose: str) -> None:
    subject = _render_verification_subject(purpose)
    body = _render_verification_body(recipient, verification_url, purpose)
    if settings.smtp_host and settings.smtp_from:
        await asyncio.to_thread(_send_via_smtp, recipient, subject, body)
        return
    await asyncio.to_thread(_append_debug_mail, recipient, subject, body)
