"""
En Az Yetki Prensibi (PoLP) + Çok Kiracılı (multi-tenant) yetki kontrolü.

Şema gereksinimi: kişi A sitesinde SAKİN, B sitesinde YÖNETİCİ olabilir
(kullanici_site tablosu). Bu nedenle yetki HER ZAMAN (kullanici, site) çiftiyle
kontrol edilir; site_no URL'den gelen değere değil, TOKEN'daki site_no'ya göre
doğrulanır (IDOR / kiralık sızdırma önlemi).
"""
from dataclasses import dataclass

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .security import decode_token

bearer = HTTPBearer(auto_error=True)


@dataclass
class Principal:
    kullanici_no: int
    site_no: int
    yetki: str           # YÖNETİCİ | MUHASEBECİ | SAKİN | PERSONEL
    firma_no: int | None

    def can_write(self) -> bool:
        return self.yetki in ("YÖNETİCİ", "MUHASEBECİ")


def get_current_principal(
    creds: HTTPAuthorizationCredentials = Depends(bearer),
) -> Principal:
    payload = decode_token(creds.credentials, expected_type="access")
    if payload is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Geçersiz veya süresi dolmuş oturum.")
    return Principal(
        kullanici_no=int(payload["sub"]),
        site_no=int(payload.get("site_no", 0)),
        yetki=str(payload.get("yetki", "")),
        firma_no=payload.get("firma_no"),
    )


def require_yetki(*roller: str):
    """Belirtilen rollerden birine sahipse geçer; değilse 403."""
    allowed = set(roller)

    def checker(p: Principal = Depends(get_current_principal)) -> Principal:
        if p.yetki not in allowed:
            raise HTTPException(status.HTTP_403_FORBIDDEN,
                                "Bu işlem için yetkiniz bulunmuyor.")
        return p
    return checker


# --- Yazma/yönetim işlemleri: YÖNETİCİ ve MUHASEBECİ ---------------------------
yonetim_yetkili = require_yetki("YÖNETİCİ", "MUHASEBECİ")
sadece_yonetici = require_yetki("YÖNETİCİ")


def tenant_scope(site_no: int, principal: Principal) -> None:
    """İstenen site, token'daki kiracı ile eşleşmiyorsa reddet (IDOR koruması)."""
    if principal.site_no != site_no:
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Bu siteye erişim yetkiniz yok.")
