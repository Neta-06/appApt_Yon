# Yönetimcell — Çoklu Apartman (Multi-Tenant) Yönetim Sistemi

Güvenlik gereksinimleri (OWASP Top 10 / Mobile Top 10) mimarinin merkezine yerleştirilmiş
FastAPI backend iskeleti.

## Mimari

```
İnternet ──► WAF (ModSecurity/Cloudflare) ──► NGINX (TLS 1.3)
      │                                          │
      │   Mobil App ──TLS Pinning───────────────►│
      ▼                                          ▼
   Hız sınırı (Redis) ──► FastAPI ──► RBAC/MFA ──► MySQL 8 + Redis
```

## Güvenlik Kontrolleri — Gereksinim Karşılıkları

### 1. Kaynak Kod ve Geliştirme Güvenliği
| Kontrol | Durum | Konum |
|---|---|---|
| Beyaz liste input validation | ✅ | `app/schemas/auth.py` (regex beyaz listeler, Pydantic v2) |
| SQL Injection önlemi | ✅ | SQLAlchemy ORM, yalnızca parametrik sorgu |
| XSS önlemi | ✅ | CSP `default-src 'none'`, `X-Frame-Options: DENY`, `httponly` çerez |
| SAST (Bandit/Safety) | 🔧 CI'a eklenecek | requirements içinde yorumlu |
| Penetration test | 📋 Yılda 1 bağımsız firma (canlıya almadan önce 1 kez) | — |

### 2. Kimlik Doğrulama ve Yetkilendirme
| Kontrol | Durum | Konum |
|---|---|---|
| MFA (TOTP Authenticator / SMS) | ✅ altyapı hazır | `pyotp`, `auth.py` mfa akışı |
| Argon2id parola hash + tuz | ✅ | `core/security.py` |
| PoLP / RBAC | ✅ | `core/rbac.py` — `require_yetki()`, site bazlı yetki |
| Kısa ömürlü JWT (15 dk) | ✅ | `core/security.py` |
| HttpOnly + Secure + SameSite=Strict | ✅ | `COOKIE_KWARGS` |

### 3. Veri ve İletişim Güvenliği
| Kontrol | Durum | Konum |
|---|---|---|
| TLS 1.3 (transit) | 🔧 reverse proxy'de sonlandırılır | NGINX (deploy) |
| AES-256 dinlenme şifreleme (TC no vb.) | ✅ | `encrypt_field/decrypt_field` |
| SSL Pinning (mobil) | 📋 mobil tarafta uygulanacak | sertifika public key sabitlenir |
| API Gateway + Rate Limiting | ✅ | `middleware/rate_limit.py` (login: 5 deneme/5 dk) |

### 4. Mobil Uygulamaya Özel
| Kontrol | Durum |
|---|---|
| Obfuscation (R8/ProGuard, SwiftShield) | 📋 mobil build ayarlarında |
| RASP (root/jailbreak/debugger tespiti) | 📋 öneri: Promon / Appdome / native kontroller |
| Güvenli yerel depolama (Keychain / EncryptedSharedPreferences) | 📋 mobil tarafta zorunlu |

### 5. Altyapı ve İzleme
| Kontrol | Durum |
|---|---|
| WAF | 🔧 ModSecurity (OWASP CRS) veya Cloudflare |
| SIEM + merkezi log | 🔧 JSON log -> ELK/OpenSearch; logda ham parola/kart YOK |
| Anomali tespiti | 📋 SIEM korelasyon kuralları |
| Veritabanı erişimi | ✅ yalnızca internal network, ayrık DB kullanıcısı |

## Çalıştırma

```bash
cd backend
cp .env.example .env   # değerleri doldurun (JWT_SECRET_KEY ve FIELD_ENCRYPTION_KEY üretin)
pip install -r requirements.txt
alembic upgrade head   # şema migrasyonu
uvicorn app.main:app --reload
```

## Proje Yapısı

```
backend/
├── app/
│   ├── main.py                  # Uygulama girişi (CORS + güvenlik başlıkları)
│   ├── core/
│   │   ├── config.py            # Ortam değişkenli ayarlar (.env)
│   │   ├── security.py          # Argon2, JWT, AES-256, güvenli çerez
│   │   └── rbac.py              # PoLP yetki bağımlılıkları + tenant koruması
│   ├── db/
│   │   ├── base.py / session.py # Async MySQL, parametrik sorgu
│   ├── models/identity.py       # Kullanıcı / Site / KullaniciSite (cross-site yetki)
│   ├── schemas/auth.py          # Beyaz liste doğrulama şemaları
│   ├── middleware/
│   │   ├── security_headers.py  # CSP, HSTS, nosniff...
│   │   └── rate_limit.py        # Redis tabanlı oran sınırı
│   └── api/v1/endpoints/
│       ├── auth.py              # Login → MFA → token (HttpOnly cookie)
│       └── sites.py             # Tenant kapsamlı site uçları
└── requirements.txt / Dockerfile / .env.example
```

## Sonraki Adımlar
1. `alembic` migrasyonlarını tüm tablolar için üret (şema dosyasındaki 30 tablo)
2. MFA SMS/e-posta sağlayıcı entegrasyonu (Celery görevi)
3. Kalan modüller: aidat, sayaç, cari, gider-gelir, iş takip, bildirim
4. WAF + SIEM kurulumu, mobil tarafta SSL Pinning / RASP
