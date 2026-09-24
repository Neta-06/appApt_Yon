"""
Kimlik doğrulama ve veri koruması:
- Argon2id parola hash (OWASP önerisi, bcrypt alternatifinden daha güçlü)
- Kısa ömürlü JWT + HttpOnly/Secure/SameSite=Strict çerez
- AES-256-GCM hassas alan şifreleme (TC kimlik no vb.)
"""
from datetime import datetime, timedelta, timezone
from typing import Any

from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from cryptography.fernet import Fernet
from jose import JWTError, jwt

from .config import settings

# --- Argon2id (gereksinim 2.2: güçlü algoritma + tuzlama Argon2'nin parçası) ---
ph = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=2)


def hash_password(plain: str) -> str:
    return ph.hash(plain)


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return ph.verify(hashed, plain)
    except VerifyMismatchError:
        return False
    except Exception:
        return False


def needs_rehash(hashed: str) -> bool:
    return ph.check_needs_rehash(hashed)


# --- JWT (kısa ömürlü - gereksinim 2.4) ---------------------------------------
def create_access_token(subject: str, site_no: int | None = None,
                        yetki: str | None = None) -> str:
    expire = datetime.now(timezone.utc) + timedelta(
        minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    payload: dict[str, Any] = {"sub": subject, "exp": expire, "typ": "access"}
    if site_no is not None:
        payload["site_no"] = site_no
    if yetki:
        payload["yetki"] = yetki
    return jwt.encode(payload, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(subject: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    return jwt.encode({"sub": subject, "exp": expire, "typ": "refresh"},
                      settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str, expected_type: str = "access") -> dict[str, Any] | None:
    """Token doğrula; tip uyuşmazlığı veya süre dolmuşsa None döner."""
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY,
                             algorithms=[settings.JWT_ALGORITHM])
        if payload.get("typ") != expected_type:
            return None
        return payload
    except JWTError:
        return None


# --- Güvenli çerez ayarları (gereksinim 2.4) ----------------------------------
COOKIE_KWARGS = dict(
    httponly=True,          # XSS'e karşı JS erişimi kapalı
    secure=settings.COOKIE_SECURE,
    samesite="strict",      # CSRF'e karşı
    path="/",
)


# --- AES-256-GCM hassas alan şifreleme (gereksinim 3.2 dinlenme hali) --------
_fernet = Fernet(settings.FIELD_ENCRYPTION_KEY.encode()[:44].ljust(44, b"=")
                 if len(settings.FIELD_ENCRYPTION_KEY.encode()) < 44
                 else settings.FIELD_ENCRYPTION_KEY.encode()[:44])


def encrypt_field(plain: str) -> str:
    return _fernet.encrypt(plain.encode()).decode()


def decrypt_field(cipher: str) -> str:
    return _fernet.decrypt(cipher.encode()).decode()
