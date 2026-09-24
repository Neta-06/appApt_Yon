"""
Kimlik doğrulama akışı:
1) POST /login          -> parola doğrulanır, MFA açıksa geçici token + 6 haneli kod
2) POST /mfa/verify     -> TOTP/sms kodu doğrulanır, access+refresh token (HttpOnly cookie)
3) POST /refresh        -> yenileme tokenıyla yeni access token
4) POST /logout         -> çerezler silinir (istemci tokenı da atmalı)
"""
import pyotp
from fastapi import APIRouter, Depends, HTTPException, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.rbac import Principal
from app.core.security import (COOKIE_KWARGS, create_access_token,
                               create_refresh_token, decode_token,
                               verify_password)
from app.db.session import get_db
from app.middleware.rate_limit import login_rate_limit
from app.models.identity import Kullanici, KullaniciSite
from app.schemas.auth import (LoginRequest, MfaVerifyRequest, TokenPair)

router = APIRouter(prefix="/auth", tags=["auth"])
bearer = HTTPBearer(auto_error=False)

ACCESS_COOKIE = "yc_access"
REFRESH_COOKIE = "yc_refresh"


def _site_claim(kullanici_no: int) -> tuple[int | None, str | None]:
    """Kullanıcının aktif site yetkisini çöz (örnek: ilk aktif kayıt)."""
    # Not: gerçek uygulamada kullanıcı site seçimi yapar; burada basitleştirildi.
    # TODO: kullanicinin aktif kullanici_site kaydini sec
    return None, None


@router.post("/login", status_code=status.HTTP_200_OK)
async def login(request: Request, body: LoginRequest,
                db: AsyncSession = Depends(get_db)):
    await login_rate_limit(request)                      # brute-force sınırı

    result = await db.execute(select(Kullanici).where(
        Kullanici.e_posta == body.e_posta.lower()))
    user = result.scalar_one_or_none()

    # Kullanıcı yoksa veya parola yanlışsa AYNI hata mesajı (kullanıcı numarası sızdırmaz)
    if user is None or not verify_password(body.sifre, user.sifre_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "E-posta veya parola hatalı.")
    if not user.aktif_mi:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Hesap pasif.")

    if user.mfa_aktif_mi:
        # Geçici MFA tokeni (kısa ömürlü) + OTP gönderimi (SMS/e-posta servisi entegre edilir)
        gecici = create_access_token(str(user.kullanici_no))
        return {"mfa_gerekli": True, "gecici_token": gecici}

    site_no, yetki = _site_claim(user.kullanici_no)
    return _token_response(user.kullanici_no, site_no, yetki)


@router.post("/mfa/verify")
async def mfa_verify(body: MfaVerifyRequest, response: Response):
    payload = decode_token(body.gecici_token, expected_type="access")
    if payload is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "MFA oturumu süresi dolmuş.")

    # TOTP doğrulama (user.mfa_sirri ile pyotp.TOTP(...).verify(kod))
    # one_time_window ile saat kayması toleransı: verify(kod, valid_window=1)
    raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED,
                        "TOTP doğrulama servisi entegrasyonu bekleniyor.")


def _token_response(kullanici_no: int, site_no: int | None,
                    yetki: str | None) -> dict:
    access = create_access_token(str(kullanici_no), site_no, yetki)
    refresh = create_refresh_token(str(kullanici_no))
    return {"mfa_gerekli": False, "access_token": access,
            "refresh_token": refresh, "token_type": "bearer"}


@router.post("/refresh")
async def refresh(request: Request, response: Response):
    token = request.cookies.get(REFRESH_COOKIE)
    if token is None:
        creds = bearer(request)
        token = creds.credentials if creds else None
    payload = decode_token(token or "", expected_type="refresh")
    if payload is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Oturum yenileme başarısız.")

    access = create_access_token(payload["sub"])
    response.set_cookie(ACCESS_COOKIE, access, max_age=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
                        **COOKIE_KWARGS)
    return {"access_token": access, "token_type": "bearer"}


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(response: Response):
    response.delete_cookie(ACCESS_COOKIE, path="/")
    response.delete_cookie(REFRESH_COOKIE, path="/")
    # Sunucu tarafı: refresh token kara liste (Redis) ile iptal edilir.
