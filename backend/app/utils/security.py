import os
import base64
import hashlib
from typing import Optional

from cryptography.fernet import Fernet

from app.config import settings


def _get_key() -> bytes:
    key_material = settings.SECRET_KEY.encode()
    key = hashlib.sha256(key_material).digest()
    return base64.urlsafe_b64encode(key)


def encrypt_token(token: str) -> str:
    f = Fernet(_get_key())
    return f.encrypt(token.encode()).decode()


def decrypt_token(encrypted: str) -> str:
    f = Fernet(_get_key())
    return f.decrypt(encrypted.encode()).decode()


def generate_api_token() -> str:
    return base64.urlsafe_b64encode(os.urandom(32)).decode()
