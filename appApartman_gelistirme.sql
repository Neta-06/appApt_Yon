-- ============================================================================
--  YÖNETİMCELL MODÜLLERİNE UYgun ÇOKLU APARTMAN (MULTI-TENANT) VERİTABANI
--  MySQL 8.x | utf8mb4 | Tek yönetim firması -> birden çok site/apartman
-- ============================================================================

CREATE DATABASE IF NOT EXISTS appApartman_gelistirme
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE appApartman_gelistirme;

-- ============================================================================
-- 0. YÖNETİM FİRMASI  (bir firma / muhasebeci birden çok siteyi yönetir)
-- ============================================================================

CREATE TABLE yonetim_firmasi (
    firma_no       INT AUTO_INCREMENT PRIMARY KEY,
    firma_adi      VARCHAR(150) NOT NULL,
    vergi_no       VARCHAR(20) UNIQUE,
    adres          VARCHAR(255),
    telefon        VARCHAR(15),
    e_posta        VARCHAR(100),
    yetkili_kisi   VARCHAR(100),
    olusturma_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ============================================================================
-- 1. SİTELER / APARTMANLAR  (HER İŞLEM SİTEYE BAĞLANIR = multi-tenant)
-- ============================================================================

CREATE TABLE site (
    site_no        INT AUTO_INCREMENT PRIMARY KEY,
    firma_no       INT NOT NULL,
    site_adi       VARCHAR(150) NOT NULL,
    site_tipi      ENUM('APARTMAN','SİTE','REZİDANS','PLAZA') NOT NULL DEFAULT 'APARTMAN',
    adres          VARCHAR(255),
    il             VARCHAR(30),
    ilce           VARCHAR(30),
    daire_sayisi   SMALLINT NOT NULL DEFAULT 0,
    aylik_aidat    DECIMAL(10,2) NOT NULL DEFAULT 0,
    aidat_gunu     TINYINT NOT NULL DEFAULT 5 COMMENT 'Otomatik borçlandırma günü',
    otomatik_borclandir BOOLEAN NOT NULL DEFAULT TRUE,
    aktif_mi       BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (firma_no) REFERENCES yonetim_firmasi(firma_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 2. KULLANICILAR VE SİTE YETKİLERİ (cross-site yetki: kişi A sitesinde sakin,
--    B sitesinde yönetici olabilir)
-- ============================================================================

CREATE TABLE kullanici (
    kullanici_no     INT AUTO_INCREMENT PRIMARY KEY,
    firma_no         INT COMMENT 'Firma çalışanı ise dolu',
    ad               VARCHAR(50)  NOT NULL,
    soyad            VARCHAR(50)  NOT NULL,
    tc_kimlik_no     VARCHAR(11)  UNIQUE,
    e_posta          VARCHAR(100) NOT NULL UNIQUE,
    telefon          VARCHAR(15),
    sifre_hash       VARCHAR(255) NOT NULL,
    rol              ENUM('YÖNETİCİ','SAKİN','MUHASEBECİ','PERSONEL') NOT NULL DEFAULT 'SAKİN',
    aktif_mi         BOOLEAN NOT NULL DEFAULT TRUE,
    son_giris_tarihi DATETIME,
    olusturma_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (firma_no) REFERENCES yonetim_firmasi(firma_no)
) ENGINE=InnoDB;

-- Hangi kullanıcı hangi sitede hangi yetkiyle (bir kişi birden çok sitede olabilir)
CREATE TABLE kullanici_site (
    kayit_no       INT AUTO_INCREMENT PRIMARY KEY,
    kullanici_no   INT NOT NULL,
    site_no        INT NOT NULL,
    daire_no       INT COMMENT 'SAKİN ise otomatik doldurulur',
    yetki          ENUM('YÖNETİCİ','MUHASEBECİ','SAKİN','PERSONEL') NOT NULL,
    baslangic_tarihi DATE NOT NULL,
    bitis_tarihi   DATE,
    aktif_mi       BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (kullanici_no) REFERENCES kullanici(kullanici_no),
    FOREIGN KEY (site_no)     REFERENCES site(site_no),
    UNIQUE (kullanici_no, site_no, yetki)
) ENGINE=InnoDB;

-- ============================================================================
-- 3. BLOKLAR VE DAİRELER (site altında)
-- ============================================================================

CREATE TABLE blok (
    blok_no       INT AUTO_INCREMENT PRIMARY KEY,
    site_no       INT NOT NULL,
    blok_adi      VARCHAR(20) NOT NULL,
    kat_sayisi    TINYINT NOT NULL DEFAULT 5,
    FOREIGN KEY (site_no) REFERENCES site(site_no),
    UNIQUE (site_no, blok_adi)
) ENGINE=InnoDB;

CREATE TABLE daire (
    daire_no         INT AUTO_INCREMENT PRIMARY KEY,
    site_no          INT NOT NULL,
    blok_no          INT NOT NULL,
    daire_numarasi   VARCHAR(10) NOT NULL,
    kat              TINYINT NOT NULL,
    daire_tipi       ENUM('1+0','1+1','2+1','3+1','4+1') NOT NULL DEFAULT '2+1',
    brut_metrekare   DECIMAL(6,2),
    ozel_aidat       DECIMAL(10,2) COMMENT 'NULL ise site aidatı geçerli',
    durumu           ENUM('DOLU','BOŞ','KİRADA') NOT NULL DEFAULT 'DOLU',
    FOREIGN KEY (site_no) REFERENCES site(site_no),
    FOREIGN KEY (blok_no) REFERENCES blok(blok_no),
    UNIQUE (blok_no, daire_numarasi)
) ENGINE=InnoDB;

-- Daire-sakin eşleşmesi (site içinde geçmiş sakincilik)
CREATE TABLE daire_sakin (
    kayit_no       INT AUTO_INCREMENT PRIMARY KEY,
    daire_no       INT NOT NULL,
    kullanici_no   INT NOT NULL,
    mulk_sahibi_mi BOOLEAN NOT NULL DEFAULT FALSE,
    giris_tarihi   DATE NOT NULL,
    cikis_tarihi   DATE,
    FOREIGN KEY (daire_no)     REFERENCES daire(daire_no),
    FOREIGN KEY (kullanici_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 4. AİDAT MODÜLÜ (otomatik borçlandırma + tahsilat + online ödeme)
-- ============================================================================

CREATE TABLE aidat (
    aidat_no            INT AUTO_INCREMENT PRIMARY KEY,
    site_no             INT NOT NULL,
    daire_no            INT NOT NULL,
    donem_yil           SMALLINT NOT NULL,
    donem_ay            TINYINT NOT NULL CHECK (donem_ay BETWEEN 1 AND 12),
    tutar               DECIMAL(10,2) NOT NULL,
    son_odeme_tarihi    DATE NOT NULL,
    durum               ENUM('BEKLİYOR','ÖDENDİ','GECİKMİŞ','İPTAL') NOT NULL DEFAULT 'BEKLİYOR',
    otomatik_islendi_mi BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Otomatik borçlandırma işareti',
    olusturma_tarihi    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (site_no)  REFERENCES site(site_no),
    FOREIGN KEY (daire_no) REFERENCES daire(daire_no),
    UNIQUE (daire_no, donem_yil, donem_ay),
    INDEX idx_aidat_site_donem (site_no, donem_yil, donem_ay)
) ENGINE=InnoDB;

CREATE TABLE odeme (
    odeme_no         INT AUTO_INCREMENT PRIMARY KEY,
    aidat_no         INT NOT NULL,
    odeme_tarihi     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    odeme_tutari     DECIMAL(10,2) NOT NULL,
    odeme_kanali     ENUM('HAVALE','EFT','NAKİT','KREDİ KARTI','SANAL POS','OTOMATİK TALEP') NOT NULL,
    dekont_no        VARCHAR(50),
    referans_no      VARCHAR(50) COMMENT 'Sanal POS / banka referansı',
    onay_durumu      ENUM('ONAYLANDI','BEKLİYOR','REDDEDİLDİ') NOT NULL DEFAULT 'ONAYLANDI',
    onaylayan_no     INT,
    FOREIGN KEY (aidat_no)     REFERENCES aidat(aidat_no),
    FOREIGN KEY (onaylayan_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 5. BANKA HESABI VE HAREKETLERİ (banka entegrasyonu)
-- ============================================================================

CREATE TABLE banka_hesabi (
    hesap_no        INT AUTO_INCREMENT PRIMARY KEY,
    site_no         INT NOT NULL,
    banka_adi       VARCHAR(50) NOT NULL,
    sube_adi        VARCHAR(50),
    iban            VARCHAR(34) NOT NULL UNIQUE,
    hesap_sahibi    VARCHAR(150),
    aktif_mi        BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (site_no) REFERENCES site(site_no)
) ENGINE=InnoDB;

CREATE TABLE banka_hareketi (
    hareket_no       INT AUTO_INCREMENT PRIMARY KEY,
    hesap_no         INT NOT NULL,
    hareket_tarihi   DATE NOT NULL,
    aciklama         VARCHAR(255) NOT NULL,
    tutar            DECIMAL(12,2) NOT NULL COMMENT '+ giriş / - çıkış',
    bakiye           DECIMAL(12,2) NOT NULL,
    karsi_hesap      VARCHAR(100),
    odeme_no         INT COMMENT 'Eşleşen tahsilat',
    gider_no         INT COMMENT 'Eşleşen gider',
    eslesti_mi       BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (hesap_no) REFERENCES banka_hesabi(hesap_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 6. CARİ HESAP MODÜLÜ (tedarikçi / firma borç-alacak)
-- ============================================================================

CREATE TABLE cari_hesap (
    cari_no       INT AUTO_INCREMENT PRIMARY KEY,
    site_no       INT NOT NULL,
    unvan         VARCHAR(150) NOT NULL,
    vergi_no      VARCHAR(20),
    telefon       VARCHAR(15),
    e_posta       VARCHAR(100),
    adres         VARCHAR(255),
    FOREIGN KEY (site_no) REFERENCES site(site_no)
) ENGINE=InnoDB;

CREATE TABLE cari_hareket (
    hareket_no      INT AUTO_INCREMENT PRIMARY KEY,
    cari_no         INT NOT NULL,
    hareket_tarihi  DATE NOT NULL,
    islem_tipi      ENUM('BORÇ','ALACAK') NOT NULL,
    tutar           DECIMAL(12,2) NOT NULL,
    aciklama        VARCHAR(255),
    belge_no        VARCHAR(50),
    gider_no        INT,
    odeme_no        INT,
    FOREIGN KEY (cari_no) REFERENCES cari_hesap(cari_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 7. SAYAÇ MODÜLÜ (sayaç okuma + gider paylaşımı + faturalandırma)
-- ============================================================================

CREATE TABLE sayac_turu (
    sayac_turu_no INT AUTO_INCREMENT PRIMARY KEY,
    adi           VARCHAR(50) NOT NULL UNIQUE,
    birimi        VARCHAR(10) NOT NULL DEFAULT 'm³'
) ENGINE=InnoDB;

CREATE TABLE daire_sayaci (
    daire_sayac_no INT AUTO_INCREMENT PRIMARY KEY,
    daire_no       INT NOT NULL,
    sayac_turu_no  INT NOT NULL,
    seri_no        VARCHAR(50) NOT NULL,
    montaj_tarihi  DATE,
    aktif_mi       BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (daire_no)      REFERENCES daire(daire_no),
    FOREIGN KEY (sayac_turu_no) REFERENCES sayac_turu(sayac_turu_no)
) ENGINE=InnoDB;

CREATE TABLE sayac_okuma (
    okuma_no         INT AUTO_INCREMENT PRIMARY KEY,
    daire_sayac_no   INT NOT NULL,
    okuma_tarihi     DATE NOT NULL,
    onceki_deger     DECIMAL(10,2) NOT NULL,
    guncel_deger     DECIMAL(10,2) NOT NULL,
    tuketim          DECIMAL(10,2) GENERATED ALWAYS AS (guncel_deger - onceki_deger) STORED,
    okuyan_no        INT,
    FOREIGN KEY (daire_sayac_no) REFERENCES daire_sayaci(daire_sayac_no),
    FOREIGN KEY (okuyan_no)      REFERENCES kullanici(kullanici_no),
    INDEX idx_okuma_donem (okuma_tarihi)
) ENGINE=InnoDB;

-- Sayaç tüketiminden doğan daire faturası
CREATE TABLE sayac_faturasi (
    fatura_no        INT AUTO_INCREMENT PRIMARY KEY,
    site_no          INT NOT NULL,
    sayac_turu_no    INT NOT NULL,
    donem_yil        SMALLINT NOT NULL,
    donem_ay         TINYINT NOT NULL,
    toplam_tutar     DECIMAL(12,2) NOT NULL COMMENT 'Abone faturası toplamı',
    ortak_alan_tutar DECIMAL(12,2) NOT NULL DEFAULT 0 COMMENT 'Asansör/ortak alan payı',
    dagitim_sekli    ENUM('TÜKETİME GÖRE','EŞİT','METREKARE') NOT NULL DEFAULT 'TÜKETİME GÖRE',
    FOREIGN KEY (site_no)       REFERENCES site(site_no),
    FOREIGN KEY (sayac_turu_no) REFERENCES sayac_turu(sayac_turu_no)
) ENGINE=InnoDB;

CREATE TABLE sayac_fatura_payi (
    pay_no        INT AUTO_INCREMENT PRIMARY KEY,
    fatura_no     INT NOT NULL,
    daire_no      INT NOT NULL,
    tuketim       DECIMAL(10,2) NOT NULL DEFAULT 0,
    daire_tutari  DECIMAL(10,2) NOT NULL,
    tahakkuk_no   INT COMMENT 'Aidata dönüştüyse bağlantı',
    FOREIGN KEY (fatura_no) REFERENCES sayac_faturasi(fatura_no),
    FOREIGN KEY (daire_no)  REFERENCES daire(daire_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 8. GELİR - GİDER MODÜLÜ
-- ============================================================================

CREATE TABLE gider_kalemi (
    kalem_no    INT AUTO_INCREMENT PRIMARY KEY,
    kalem_adi   VARCHAR(100) NOT NULL,
    kategori    ENUM('ASANSÖR','TEMİZLİK','GÜVENLİK','BAKIM','ONARIM','ENERJİ','SU','DOĞALGAZ','PEYZAJ','DİĞER') NOT NULL
) ENGINE=InnoDB;

CREATE TABLE gider (
    gider_no      INT AUTO_INCREMENT PRIMARY KEY,
    site_no       INT NOT NULL,
    kalem_no      INT NOT NULL,
    cari_no       INT COMMENT 'Tedarikçi cari hesabı',
    tutar         DECIMAL(12,2) NOT NULL,
    gider_tarihi  DATE NOT NULL,
    belge_no      VARCHAR(50),
    aciklama      VARCHAR(255),
    kaydeden_no   INT NOT NULL,
    FOREIGN KEY (site_no)     REFERENCES site(site_no),
    FOREIGN KEY (kalem_no)    REFERENCES gider_kalemi(kalem_no),
    FOREIGN KEY (cari_no)     REFERENCES cari_hesap(cari_no),
    FOREIGN KEY (kaydeden_no) REFERENCES kullanici(kullanici_no),
    INDEX idx_gider_site_tarih (site_no, gider_tarihi)
) ENGINE=InnoDB;

CREATE TABLE gelir (
    gelir_no      INT AUTO_INCREMENT PRIMARY KEY,
    site_no       INT NOT NULL,
    kaynak        VARCHAR(100) NOT NULL,
    tutar         DECIMAL(12,2) NOT NULL,
    gelir_tarihi  DATE NOT NULL,
    aciklama      VARCHAR(255),
    kaydeden_no   INT NOT NULL,
    FOREIGN KEY (site_no)     REFERENCES site(site_no),
    FOREIGN KEY (kaydeden_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 9. İŞ TAKİP MODÜLÜ (personel iş atama + süreç takibi)
-- ============================================================================

CREATE TABLE is_emri (
    is_no            INT AUTO_INCREMENT PRIMARY KEY,
    site_no          INT NOT NULL,
    daire_no         INT COMMENT 'Daireye bağlı iş ise',
    acan_no          INT NOT NULL COMMENT 'İşi açan yönetici',
    atanan_no        INT NOT NULL COMMENT 'İşi yapacak personel',
    baslik           VARCHAR(150) NOT NULL,
    aciklama         TEXT,
    oncelik          ENUM('DÜŞÜK','ORTA','YÜKSEK','ACİL') NOT NULL DEFAULT 'ORTA',
    durum            ENUM('AÇIK','ATANDI','ÜZERİNDE ÇALIŞIYOR','TAMAMLANDI','İPTAL') NOT NULL DEFAULT 'AÇIK',
    olusturma_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    termin_tarihi    DATETIME,
    tamamlanma_tarihi DATETIME,
    FOREIGN KEY (site_no)   REFERENCES site(site_no),
    FOREIGN KEY (daire_no)  REFERENCES daire(daire_no),
    FOREIGN KEY (acan_no)   REFERENCES kullanici(kullanici_no),
    FOREIGN KEY (atanan_no) REFERENCES kullanici(kullanici_no),
    INDEX idx_is_durum (durum)
) ENGINE=InnoDB;

CREATE TABLE is_emri_guncelleme (
    guncelleme_no    INT AUTO_INCREMENT PRIMARY KEY,
    is_no            INT NOT NULL,
    yazan_no         INT NOT NULL,
    durum            VARCHAR(30) NOT NULL,
    notlar           VARCHAR(500),
    guncelleme_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (is_no)    REFERENCES is_emri(is_no),
    FOREIGN KEY (yazan_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 10. DUYURU, MESAJ, TALEP, TOPLANTI, ANKET (site kapsamlı)
-- ============================================================================

CREATE TABLE duyuru (
    duyuru_no      INT AUTO_INCREMENT PRIMARY KEY,
    site_no        INT NOT NULL,
    baslik         VARCHAR(150) NOT NULL,
    icerik         TEXT NOT NULL,
    onem_derecesi  ENUM('NORMAL','ÖNEMLİ','ACİL') NOT NULL DEFAULT 'NORMAL',
    yayin_tarihi   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    bitis_tarihi   DATE,
    yayinlayan_no  INT NOT NULL,
    FOREIGN KEY (site_no)       REFERENCES site(site_no),
    FOREIGN KEY (yayinlayan_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

CREATE TABLE mesaj (
    mesaj_no        INT AUTO_INCREMENT PRIMARY KEY,
    gonderen_no     INT NOT NULL,
    alici_no        INT NOT NULL,
    site_no         INT NOT NULL COMMENT 'Hangi site bağlamında',
    konu            VARCHAR(150) NOT NULL,
    icerik          TEXT NOT NULL,
    gonderim_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    okundu_mu       BOOLEAN NOT NULL DEFAULT FALSE,
    okunma_tarihi   DATETIME,
    FOREIGN KEY (gonderen_no) REFERENCES kullanici(kullanici_no),
    FOREIGN KEY (alici_no)    REFERENCES kullanici(kullanici_no),
    FOREIGN KEY (site_no)     REFERENCES site(site_no),
    INDEX idx_mesaj_site_alici (site_no, alici_no, okundu_mu)
) ENGINE=InnoDB;

CREATE TABLE talep (
    talep_no         INT AUTO_INCREMENT PRIMARY KEY,
    site_no          INT NOT NULL,
    acan_no          INT NOT NULL,
    daire_no         INT,
    kategori         ENUM('ARIZA','ŞİKAYET','ÖNERİ','İZİN','DİĞER') NOT NULL DEFAULT 'ARIZA',
    konu             VARCHAR(150) NOT NULL,
    aciklama         TEXT NOT NULL,
    oncelik          ENUM('DÜŞÜK','ORTA','YÜKSEK','ACİL') NOT NULL DEFAULT 'ORTA',
    durum            ENUM('AÇIK','İNCELENİYOR','ÇÖZÜLDÜ','REDEDİLDİ','KAPANDI') NOT NULL DEFAULT 'AÇIK',
    acilis_tarihi    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    cozum_tarihi     DATETIME,
    cozen_no         INT,
    cozum_notu       VARCHAR(500),
    FOREIGN KEY (site_no)  REFERENCES site(site_no),
    FOREIGN KEY (acan_no)  REFERENCES kullanici(kullanici_no),
    FOREIGN KEY (daire_no) REFERENCES daire(daire_no),
    FOREIGN KEY (cozen_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

CREATE TABLE toplanti (
    toplanti_no     INT AUTO_INCREMENT PRIMARY KEY,
    site_no         INT NOT NULL,
    baslik          VARCHAR(150) NOT NULL,
    aciklama        TEXT,
    toplanti_tarihi DATETIME NOT NULL,
    yer             VARCHAR(100),
    olusturan_no    INT NOT NULL,
    durum           ENUM('PLANLANDI','YAPILDI','İPTAL') NOT NULL DEFAULT 'PLANLANDI',
    FOREIGN KEY (site_no)      REFERENCES site(site_no),
    FOREIGN KEY (olusturan_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

CREATE TABLE anket (
    anket_no         INT AUTO_INCREMENT PRIMARY KEY,
    site_no          INT NOT NULL,
    soru             VARCHAR(300) NOT NULL,
    aciklama         VARCHAR(500),
    baslangic_tarihi DATETIME NOT NULL,
    bitis_tarihi     DATETIME NOT NULL,
    olusturan_no     INT NOT NULL,
    aktif_mi         BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (site_no)      REFERENCES site(site_no),
    FOREIGN KEY (olusturan_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

CREATE TABLE anket_secenegi (
    secenek_no    INT AUTO_INCREMENT PRIMARY KEY,
    anket_no      INT NOT NULL,
    secenek_metni VARCHAR(200) NOT NULL,
    FOREIGN KEY (anket_no) REFERENCES anket(anket_no)
) ENGINE=InnoDB;

CREATE TABLE anket_oyu (
    oy_no        INT AUTO_INCREMENT PRIMARY KEY,
    secenek_no   INT NOT NULL,
    kullanici_no INT NOT NULL,
    oy_tarihi    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (secenek_no)   REFERENCES anket_secenegi(secenek_no),
    FOREIGN KEY (kullanici_no) REFERENCES kullanici(kullanici_no),
    UNIQUE (secenek_no, kullanici_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 11. SMS / E-POSTA BİLDİRİM MODÜLÜ
-- ============================================================================

CREATE TABLE bildirim (
    bildirim_no     INT AUTO_INCREMENT PRIMARY KEY,
    site_no         INT NOT NULL,
    gonderen_no     INT NOT NULL,
    hedef           ENUM('TÜM SAKİNLER','BELİRLİ DAİRE','YÖNETİM','PERSONEL') NOT NULL,
    daire_no        INT COMMENT 'BELİRLİ DAİRE ise',
    bildirim_tipi   ENUM('SMS','E_POSTA','BOTH') NOT NULL,
    konu            VARCHAR(150),
    icerik          TEXT NOT NULL,
    gonderim_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    durum           ENUM('GÖNDERİLDİ','BEKLİYOR','BAŞARISIZ') NOT NULL DEFAULT 'BEKLİYOR',
    FOREIGN KEY (site_no)     REFERENCES site(site_no),
    FOREIGN KEY (gonderen_no) REFERENCES kullanici(kullanici_no),
    FOREIGN KEY (daire_no)    REFERENCES daire(daire_no)
) ENGINE=InnoDB;

-- ============================================================================
-- 12. PERSONEL, BELGE, DEMİRBAŞ
-- ============================================================================

CREATE TABLE personel (
    personel_no      INT AUTO_INCREMENT PRIMARY KEY,
    firma_no         INT NOT NULL,
    ad               VARCHAR(50) NOT NULL,
    soyad            VARCHAR(50) NOT NULL,
    gorevi           VARCHAR(50) NOT NULL,
    telefon          VARCHAR(15),
    maas             DECIMAL(10,2),
    ise_baslama_tarihi DATE NOT NULL,
    aktif_mi         BOOLEAN NOT NULL DEFAULT TRUE,
    FOREIGN KEY (firma_no) REFERENCES yonetim_firmasi(firma_no)
) ENGINE=InnoDB;

-- Personelin hangi sitelerde çalıştığı (cross-site personel)
CREATE TABLE personel_site (
    kayit_no    INT AUTO_INCREMENT PRIMARY KEY,
    personel_no INT NOT NULL,
    site_no     INT NOT NULL,
    FOREIGN KEY (personel_no) REFERENCES personel(personel_no),
    FOREIGN KEY (site_no)     REFERENCES site(site_no),
    UNIQUE (personel_no, site_no)
) ENGINE=InnoDB;

CREATE TABLE belge (
    belge_no       INT AUTO_INCREMENT PRIMARY KEY,
    site_no        INT NOT NULL,
    belge_adi      VARCHAR(150) NOT NULL,
    dosya_yolu     VARCHAR(255) NOT NULL,
    kategori       ENUM('SÖZLEŞME','FATURA','RAPOR','TUTANAK','DİĞER') NOT NULL DEFAULT 'DİĞER',
    yukleme_tarihi DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    yukleyen_no    INT NOT NULL,
    FOREIGN KEY (site_no)     REFERENCES site(site_no),
    FOREIGN KEY (yukleyen_no) REFERENCES kullanici(kullanici_no)
) ENGINE=InnoDB;

CREATE TABLE demirbas (
    demirbas_no   INT AUTO_INCREMENT PRIMARY KEY,
    site_no       INT NOT NULL,
    ad            VARCHAR(100) NOT NULL,
    kategori      VARCHAR(50),
    adet          SMALLINT NOT NULL DEFAULT 1,
    alis_fiyati   DECIMAL(12,2),
    bulundugu_yer VARCHAR(100),
    durum         ENUM('ÇALIŞIYOR','ARIZALI','HURDA') NOT NULL DEFAULT 'ÇALIŞIYOR',
    FOREIGN KEY (site_no) REFERENCES site(site_no)
) ENGINE=InnoDB;

-- ============================================================================
-- ÖRNEK VERİLER (1 firma - 2 site - cross-site işlemler)
-- ============================================================================

INSERT INTO yonetim_firmasi (firma_adi, vergi_no, adres, telefon, e_posta, yetkili_kisi) VALUES
('Örnek Yönetim Ltd. Şti.', '1234567890', 'Atatürk Cad. No:45 Kadıköy/İstanbul', '02161234567', 'info@ornekyonetim.com', 'Ahmet Yılmaz');

-- İKİ FARKLI SİTE
INSERT INTO site (firma_no, site_adi, site_tipi, adres, il, ilce, daire_sayisi, aylik_aidat, aidat_gunu) VALUES
(1, 'Gül Sitesi',     'SİTE',     'Cumhuriyet Mah. Gül Sok. No:1', 'İstanbul', 'Kadıköy', 24, 1500.00, 5),
(1, 'Yıldız Apartmanı','APARTMAN','Barış Mah. Yıldız Cad. No:12',  'Ankara',   'Çankaya', 12, 2000.00, 10);

-- Kullanıcılar (firma çalışanı yönetici: her iki siteyi de yönetir)
INSERT INTO kullanici (firma_no, ad, soyad, tc_kimlik_no, e_posta, telefon, sifre_hash, rol) VALUES
(1, 'Ahmet', 'Yılmaz', '10000000111', 'ahmet@ornekyonetim.com', '05011110001', '$2b$12$OrnekHash1234567890abcdef', 'YÖNETİCİ'),
(1, 'Zeynep','Kaya',   '10000000222', 'zeynep@ornekyonetim.com','05011110002', '$2b$12$OrnekHash1234567890abcdef', 'MUHASEBECİ'),
(1, 'Mehmet','Demir',  NULL,          'mehmet@ornekyonetim.com','05011110003', '$2b$12$OrnekHash1234567890abcdef', 'PERSONEL'),
(NULL,'Ayşe', 'Şahin', '10000000333', 'ayse.sahin@mail.com',   '05011110004', '$2b$12$OrnekHash1234567890abcdef', 'SAKİN'),
(NULL,'Fatma', 'Çelik','10000000444', 'fatma.celik@mail.com',  '05011110005', '$2b$12$OrnekHash1234567890abcdef', 'SAKİN'),
(NULL,'Mustafa','Toprak','10000000555','mustafa.toprak@mail.com','05011110006','$2b$12$OrnekHash1234567890abcdef', 'SAKİN');

-- Bloklar
INSERT INTO blok (site_no, blok_adi, kat_sayisi) VALUES
(1, 'A Blok', 4), (1, 'B Blok', 4),
(2, 'Tek Blok', 6);

-- Daireler (Gül: site_no=1, Yıldız: site_no=2)
INSERT INTO daire (site_no, blok_no, daire_numarasi, kat, daire_tipi, brut_metrekare, ozel_aidat, durumu) VALUES
(1, 1, '1', 0, '2+1', 85.00,  NULL,    'DOLU'),
(1, 1, '2', 0, '3+1', 110.00, 1800.00,'DOLU'),
(1, 2, '1', 0, '2+1', 85.00,  NULL,    'KİRADA'),
(1, 2, '5', 1, '3+1', 115.00, NULL,    'BOŞ'),
(2, 3, '1', 0, '2+1', 90.00,  NULL,    'DOLU'),
(2, 3, '3', 1, '4+1', 140.00, NULL,    'DOLU');

-- Site yetkileri (cross-site yetki örneği: Ahmet her iki sitede de yönetici)
INSERT INTO kullanici_site (kullanici_no, site_no, daire_no, yetki, baslangic_tarihi) VALUES
(1, 1, NULL, 'YÖNETİCİ',  '2025-01-01'),
(1, 2, NULL, 'YÖNETİCİ',  '2025-01-01'),
(2, 1, NULL, 'MUHASEBECİ','2025-01-01'),
(2, 2, NULL, 'MUHASEBECİ','2025-06-01'),
(3, 1, NULL, 'PERSONEL',  '2025-01-01'),
(3, 2, NULL, 'PERSONEL',  '2025-06-01'),
(4, 1, 1,    'SAKİN',     '2025-02-01'),
(5, 1, 3,    'SAKİN',     '2025-03-01'),
(6, 2, 5,    'SAKİN',     '2025-02-01');

INSERT INTO daire_sakin (daire_no, kullanici_no, mulk_sahibi_mi, giris_tarihi) VALUES
(1, 4, TRUE, '2025-02-01'),
(3, 5, FALSE,'2025-03-01'),
(5, 6, TRUE, '2025-02-01');

-- Sayaç türleri ve daire sayaçları
INSERT INTO sayac_turu (adi, birimi) VALUES ('Soğuk Su','m³'), ('Sıcak Su','m³'), ('Doğalgaz','m³');

INSERT INTO daire_sayaci (daire_no, sayac_turu_no, seri_no, montaj_tarihi) VALUES
(1, 1, 'SS-0001', '2025-01-01'), (2, 1, 'SS-0002', '2025-01-01'), (3, 1, 'SS-0003', '2025-01-01'),
(5, 1, 'SS-0004', '2025-01-01'), (6, 1, 'SS-0005', '2025-01-01');

INSERT INTO sayac_okuma (daire_sayac_no, okuma_tarihi, onceki_deger, guncel_deger, okuyan_no) VALUES
(1, '2026-08-31', 120.00, 145.50, 3),
(2, '2026-08-31', 200.00, 234.00, 3),
(3, '2026-08-31',  90.00, 112.25, 3),
(4, '2026-08-31', 150.00, 171.00, 3),
(5, '2026-08-31', 310.00, 348.75, 3);

-- Sayaç faturası ve daire paylaşımı (Gül Sitesi Ağustos su faturası)
INSERT INTO sayac_faturasi (site_no, sayac_turu_no, donem_yil, donem_ay, toplam_tutar, ortak_alan_tutar, dagitim_sekli) VALUES
(1, 1, 2026, 8, 2500.00, 300.00, 'TÜKETİME GÖRE');

INSERT INTO sayac_fatura_payi (fatura_no, daire_no, tuketim, daire_tutari) VALUES
(1, 1, 25.50,  260.25),
(1, 2, 34.00,  346.99),
(1, 3, 22.25,  227.11),
(1, 4, 21.00,  214.35);

-- Banka hesapları (her site kendi hesabını kullanır)
INSERT INTO banka_hesabi (site_no, banka_adi, sube_adi, iban, hesap_sahibi) VALUES
(1, 'Ziraat Bankası', 'Kadıköy Şubesi', 'TR330006100519786457841326', 'Gül Sitesi Yönetimi'),
(2, 'İş Bankası',     'Çankaya Şubesi', 'TR980006701119843061785214', 'Yıldız Apartmanı Yönetimi');

INSERT INTO banka_hareketi (hesap_no, hareket_tarihi, aciklama, tutar, bakiye, karsi_hesap, eslesti_mi) VALUES
(1, '2026-09-05', 'A Blok 1 Daire - Eylül Aidat', 1500.00,  1500.00, 'Ayşe Şahin',  TRUE),
(1, '2026-09-08', 'B Blok 1 Daire - Eylül Aidat', 1500.00,  3000.00, 'Fatma Çelik', TRUE),
(1, '2026-09-10', 'Asansör Teknik Ltd. ödeme',    -2500.00,  500.00,  'Asansör Teknik', TRUE),
(2, '2026-09-10', '1. Kat 1 Daire - Eylül Aidat', 2000.00,  2000.00, 'Mustafa Toprak', FALSE);

-- Cari hesaplar ve hareketler
INSERT INTO cari_hesap (site_no, unvan, vergi_no, telefon) VALUES
(1, 'Asansör Teknik Ltd.', '1111111111', '02165550001'),
(1, 'Temizlik Hizmetleri A.Ş.', '2222222222', '02165550002'),
(2, 'Güvenlik Sistemleri A.Ş.', '3333333333', '03125550003');

INSERT INTO cari_hareket (cari_no, hareket_tarihi, islem_tipi, tutar, aciklama, belge_no) VALUES
(1, '2026-09-01', 'BORÇ',   2500.00, 'Eylül asansör bakımı',  'FTR-1001'),
(1, '2026-09-10', 'ALACAK', 2500.00, 'Ödeme yapıldı',         'BK-1001'),
(2, '2026-09-01', 'BORÇ',   6000.00, 'Eylül temizlik hizmeti','FTR-1002'),
(3, '2026-09-01', 'BORÇ',   8000.00, 'Eylül güvenlik hizmeti','FTR-2001');

-- Gider kalemleri
INSERT INTO gider_kalemi (kalem_adi, kategori) VALUES
('Asansör Periyodik Bakımı','ASANSÖR'), ('Site Temizlik Hizmeti','TEMİZLİK'),
('Özel Güvenlik Hizmeti','GÜVENLİK'), ('Elektrik Faturası','ENERJİ'),
('Su Faturası','SU'), ('Doğalgaz Faturası','DOĞALGAZ');

-- Giderler (her siteden)
INSERT INTO gider (site_no, kalem_no, cari_no, tutar, gider_tarihi, belge_no, aciklama, kaydeden_no) VALUES
(1, 1, 1, 2500.00, '2026-09-01', 'FTR-1001', 'Eylül asansör bakımı', 2),
(1, 2, 2, 6000.00, '2026-09-01', 'FTR-1002', 'Eylül temizlik',       2),
(1, 4, NULL, 3200.00, '2026-09-05', 'FTR-1003', 'Ortak alan elektrik', 2),
(2, 3, 3, 8000.00, '2026-09-01', 'FTR-2001', 'Eylül güvenlik',       2);

INSERT INTO gelir (site_no, kaynak, tutar, gelir_tarihi, aciklama, kaydeden_no) VALUES
(1, 'Aidat Tahsilatı', 3000.00, '2026-09-08', 'Eylül aidatı tahsilatları', 2),
(1, 'Kira Geliri',     1500.00, '2026-09-01', 'Kapıcı dairesi kirası',     2),
(2, 'Aidat Tahsilatı', 2000.00, '2026-09-10', 'Eylül aidatı tahsilatı',    2);

-- Aidatlar (otomatik borçlandırma örneği: Gül Ağustos otomatik, Eylül bekliyor)
INSERT INTO aidat (site_no, daire_no, donem_yil, donem_ay, tutar, son_odeme_tarihi, durum, otomatik_islendi_mi) VALUES
(1, 1, 2026, 9, 1500.00, '2026-09-30', 'ÖDENDİ', TRUE),
(1, 2, 2026, 9, 1800.00, '2026-09-30', 'BEKLİYOR', TRUE),
(1, 3, 2026, 9, 1500.00, '2026-09-30', 'ÖDENDİ', TRUE),
(1, 4, 2026, 9, 1500.00, '2026-09-30', 'BEKLİYOR', TRUE),
(2, 5, 2026, 9, 2000.00, '2026-09-30', 'BEKLİYOR', TRUE),
(2, 6, 2026, 9, 2000.00, '2026-09-30', 'GECİKMİŞ', TRUE),
(1, 1, 2026, 8, 1500.00, '2026-08-30', 'ÖDENDİ', TRUE);

INSERT INTO odeme (aidat_no, odeme_tarihi, odeme_tutari, odeme_kanali, dekont_no, referans_no, onay_durumu, onaylayan_no) VALUES
(1, '2026-09-05 10:30:00', 1500.00, 'SANAL POS', NULL, 'POS-778899', 'ONAYLANDI', 2),
(3, '2026-09-08 09:15:00', 1500.00, 'OTOMATİK TALEP', NULL, 'OTM-445566', 'ONAYLANDI', 2),
(7, '2026-08-25 14:00:00', 1500.00, 'HAVALE', 'HB-2026-0001', NULL, 'ONAYLANDI', 2);

-- İş takip (cross-site personel örneği: Mehmet her iki sitede de görevli)
INSERT INTO is_emri (site_no, daire_no, acan_no, atanan_no, baslik, aciklama, oncelik, durum, termin_tarihi) VALUES
(1, 1,    1, 3, 'Balkon Suyu Sızıntısı', 'Daire 1 balkon drenaj kontrolü.', 'ACİL', 'TAMAMLANDI', '2026-09-10 18:00:00'),
(1, NULL, 1, 3, 'Bahçe Sulama Arızası',  'Sulama vanası değişimi.',         'ORTA', 'ÜZERİNDE ÇALIŞIYOR', '2026-09-20 18:00:00'),
(2, 6,    1, 3, 'Klozet Rezervuar Arızası', 'Rezervuar iç takım değişimi.', 'YÜKSEK', 'ATANDI', '2026-09-18 18:00:00');

INSERT INTO is_emri_guncelleme (is_no, yazan_no, durum, notlar) VALUES
(1, 3, 'ÜZERİNDE ÇALIŞIYOR', 'Drenaj borusu değiştiriliyor.'),
(1, 3, 'TAMAMLANDI', 'Test edildi, sorun çözüldü.'),
(3, 3, 'ATANDI', 'Malzeme temin edilecek.');

-- Duyurular (her siteye özel)
INSERT INTO duyuru (site_no, baslik, icerik, onem_derecesi, bitis_tarihi, yayinlayan_no) VALUES
(1, 'Su Kesintisi', '25 Eylül 09:00-15:00 ana hat bakımı nedeniyle su kesintisi olacaktır.', 'ACİL', '2026-09-25', 1),
(2, 'Asansör Bakımı', 'Asansör periyodik bakımı 22 Eylül yapılacaktır.', 'ÖNEMLİ', '2026-09-22', 1);

-- Mesajlar (site bağlamlı)
INSERT INTO mesaj (gonderen_no, alici_no, site_no, konu, icerik, okundu_mu) VALUES
(4, 1, 1, 'Aidat Dekontu', 'Eylül aidat ödeme dekontumu iletiyorum.', TRUE),
(1, 4, 1, 'Re: Aidat Dekontu', 'Ödemeniz onaylanmıştır, teşekkürler.', TRUE),
(6, 1, 2, 'Otopark Talebi', 'Araç kaydı için plaka bilgilerimi iletiyorum.', FALSE);

-- Talepler
INSERT INTO talep (site_no, acan_no, daire_no, kategori, konu, aciklama, oncelik, durum) VALUES
(1, 4, 1, 'ARIZA', 'Merdiven Aydınlatması', '2. kat merdiven lambası yanmıyor.', 'ORTA', 'AÇIK'),
(2, 6, 6, 'ŞİKAYET', 'Ortak Alan Temizliği', 'Giriş holü zemini kirli.', 'DÜŞÜK', 'İNCELENİYOR');

-- Toplantı + anket + oy
INSERT INTO toplanti (site_no, baslik, aciklama, toplanti_tarihi, yer, olusturan_no) VALUES
(1, 'Eylül Yönetim Toplantısı', 'Aylık gider-gider değerlendirmesi.', '2026-09-15 19:00:00', 'Site Toplantı Salonu', 1);

INSERT INTO anket (site_no, soru, aciklama, baslangic_tarihi, bitis_tarihi, olusturan_no) VALUES
(1, 'Bahçeye oyun parkı yapalım mı?', 'Tahmini maliyet aidattan karşılanacak.', '2026-09-10 09:00:00', '2026-09-30 23:59:59', 1);

INSERT INTO anket_secenegi (anket_no, secenek_metni) VALUES (1,'EVET'), (1,'HAYIR'), (1,'KARARSIZIM');

INSERT INTO anket_oyu (secenek_no, kullanici_no) VALUES (1, 4), (1, 5);

-- Bildirimler (SMS/e-posta)
INSERT INTO bildirim (site_no, gonderen_no, hedef, bildirim_tipi, konu, icerik, durum) VALUES
(1, 1, 'TÜM SAKİNLER', 'BOTH', 'Su Kesintisi', '25 Eylül 09:00-15:00 su kesintisi olacaktır.', 'GÖNDERİLDİ'),
(2, 1, 'TÜM SAKİNLER', 'E_POSTA', 'Aidat Hatırlatma', 'Eylül aidatlarınızın son ödeme tarihi 30 Eylül''dür.', 'GÖNDERİLDİ');

-- Personel ve site atamaları
INSERT INTO personel (firma_no, ad, soyad, gorevi, telefon, maas, ise_baslama_tarihi) VALUES
(1, 'Mehmet', 'Demir', 'TEKNİK PERSONEL', '05011110003', 30000.00, '2025-01-01'),
(1, 'Emine',  'Temiz', 'TEMİZLİK PERSONELİ', '05011110007', 24000.00, '2025-03-01');

INSERT INTO personel_site (personel_no, site_no) VALUES (1, 1), (1, 2), (2, 1);

-- Belgeler ve demirbaşlar
INSERT INTO belge (site_no, belge_adi, dosya_yolu, kategori, yukleyen_no) VALUES
(1, 'Asansör Bakım Sözleşmesi 2026.pdf', '/belgeler/gul/asansor-sozlesme.pdf', 'SÖZLEŞME', 2),
(2, 'Güvenlik Sözleşmesi 2026.pdf', '/belgeler/yildiz/guvenlik-sozlesme.pdf', 'SÖZLEŞME', 2);

INSERT INTO demirbas (site_no, ad, kategori, adet, alis_fiyati, bulundugu_yer, durum) VALUES
(1, 'Asansör', 'TAŞIMA', 2, 800000.00, 'Bloklar', 'ÇALIŞIYOR'),
(2, 'Jeneratör', 'ENERJİ', 1, 350000.00, 'Bodrum', 'ÇALIŞIYOR');

-- ============================================================================
-- CROSS-SITE (APARTMANLAR ARASI) RAPOR SORGULARI
-- ============================================================================

-- 1) FİRMA GENELİ: tüm sitelerin aylık gelir-gider özeti
SELECT s.site_adi,
       IFNULL(g.toplam_gelir, 0)  AS toplam_gelir,
       IFNULL(x.toplam_gider, 0)  AS toplam_gider,
       IFNULL(g.toplam_gelir,0) - IFNULL(x.toplam_gider,0) AS net_durum
FROM site s
LEFT JOIN (SELECT site_no, SUM(tutar) toplam_gelir FROM gelir  WHERE gelir_tarihi  BETWEEN '2026-09-01' AND '2026-09-30' GROUP BY site_no) g ON g.site_no = s.site_no
LEFT JOIN (SELECT site_no, SUM(tutar) toplam_gider FROM gider  WHERE gider_tarihi  BETWEEN '2026-09-01' AND '2026-09-30' GROUP BY site_no) x ON x.site_no = s.site_no;

-- 2) CROSS-SITE BORÇ DURUMU: her sitenin toplam tahakkuk / tahsilat / bakiye
SELECT s.site_adi,
       SUM(a.tutar) AS tahakkuk,
       SUM(CASE WHEN a.durum = 'ÖDENDİ' THEN a.tutar ELSE 0 END) AS tahsilat,
       SUM(CASE WHEN a.durum IN ('BEKLİYOR','GECİKMİŞ') THEN a.tutar ELSE 0 END) AS bakiye
FROM aidat a JOIN site s ON a.site_no = s.site_no
GROUP BY s.site_no;

-- 3) TÜM SİTELERDEKİ AÇIK İŞLER (cross-site iş takip ekranı)
SELECT s.site_adi, i.baslik, i.oncelik, i.durum, k.ad AS atanan
FROM is_emri i
JOIN site s      ON i.site_no = s.site_no
JOIN kullanici k ON i.atanan_no = k.kullanici_no
WHERE i.durum NOT IN ('TAMAMLANDI','İPTAL')
ORDER BY FIELD(i.oncelik,'ACİL','YÜKSEK','ORTA','DÜŞÜK');

-- 4) PERSONELİN TÜM SİTELERDEKİ İŞ YÜKÜ (aynı personel birden çok sitede)
SELECT k.ad, k.soyad, s.site_adi, COUNT(*) AS acik_is
FROM is_emri i
JOIN kullanici k ON i.atanan_no = k.kullanici_no
JOIN site s      ON i.site_no = s.site_no
WHERE i.durum NOT IN ('TAMAMLANDI','İPTAL')
GROUP BY k.kullanici_no, s.site_no;

-- 5) SİTE BAZLI CARI BAKİYE (borç - alacak)
SELECT s.site_adi, c.unvan,
       SUM(CASE WHEN h.islem_tipi='BORÇ'   THEN h.tutar ELSE 0 END) -
       SUM(CASE WHEN h.islem_tipi='ALACAK' THEN h.tutar ELSE 0 END) AS bakiye
FROM cari_hareket h
JOIN cari_hesap c ON h.cari_no = c.cari_no
JOIN site s       ON c.site_no = s.site_no
GROUP BY c.cari_no;

-- 6) KULLANICININ YETKİLİ OLDUĞU SİTELER (login sonrası site listesi)
SELECT k.e_posta, s.site_adi, ks.yetki
FROM kullanici_site ks
JOIN kullanici k ON ks.kullanici_no = k.kullanici_no
JOIN site s      ON ks.site_no = s.site_no
WHERE k.kullanici_no = 1 AND ks.aktif_mi = TRUE;

-- 7) SAYAÇ FATURASI PAYLAŞIMI (tüketime göre dağıtım doğrulaması)
SELECT f.donem_yil, f.donem_ay, SUM(p.tuketim) AS toplam_tuketim,
       SUM(p.daire_tutari) AS toplam_paylasim
FROM sayac_fatura_payi p JOIN sayac_faturasi f ON p.fatura_no = f.fatura_no
GROUP BY f.fatura_no;