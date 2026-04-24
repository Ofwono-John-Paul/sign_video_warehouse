import asyncio
import json
import math
import os
import re
import shutil
import subprocess
import tempfile
import uuid
import threading
from pathlib import Path
from datetime import datetime, timedelta, timezone
from typing import Optional
from urllib.parse import quote, urlsplit, urlunsplit
from urllib.request import Request as UrlRequest, urlopen

import cloudinary
import cloudinary.api
import cloudinary.uploader

try:
    import imageio_ffmpeg
except ImportError:
    imageio_ffmpeg = None

from fastapi import (
    FastAPI, Depends, HTTPException, UploadFile, File,
    Form, Query, Request, status
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from sqlalchemy import (
    create_engine, Column, Integer, String, Float, Boolean,
    Text, DateTime, func, or_, distinct
)
from sqlalchemy.orm import sessionmaker, Session, declarative_base

from dotenv import load_dotenv
from jose import jwt, JWTError
from werkzeug.security import generate_password_hash, check_password_hash

load_dotenv()

# ── DATABASE CONFIG ────────────────────────────────────────────────────────────
database_url = os.getenv("DATABASE_URL")

if not database_url:
    raise RuntimeError("DATABASE_URL is missing. Set it in .env or hosting platform settings.")

if os.getenv("DATABASE_SSLMODE", "").strip():
    from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

    parts = urlsplit(database_url)
    query = dict(parse_qsl(parts.query, keep_blank_values=True))
    query["sslmode"] = os.getenv("DATABASE_SSLMODE", "require").strip() or "require"
    database_url = urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query), parts.fragment))

print(f"DATABASE_URL loaded: {'yes' if database_url else 'no'}")

# ── JWT CONFIG ───────────────────────────────────────────
JWT_SECRET = os.getenv("JWT_SECRET_KEY", "usl-secret-2026")
JWT_ALGO = "HS256"
JWT_EXPIRE = timedelta(days=7)

# ── CLOUDINARY CONFIG─────────────────────────────────────
cloudinary.config(
    cloud_name=os.getenv("CLOUDINARY_CLOUD_NAME"),
    api_key=os.getenv("CLOUDINARY_API_KEY"),
    api_secret=os.getenv("CLOUDINARY_API_SECRET"),
    secure=True,
)

REGIONS      = ['Central', 'Western', 'Eastern', 'Northern']
SCHOOL_TYPES = ['Primary', 'Secondary', 'Vocational']
CATEGORIES   = ['Education', 'Health']
VERIFIED     = ['pending', 'approved', 'rejected', 'replaced']

# ── DATABASE ───────────────────────────────────────────────────────────────────
engine       = create_engine(database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base         = declarative_base()

VIDEO_STORAGE_ROOT = Path(__file__).resolve().parent / 'uploads'
VIDEO_ORIGINAL_DIR = VIDEO_STORAGE_ROOT / 'original'
VIDEO_RAW_DIR = VIDEO_STORAGE_ROOT / 'raw'
VIDEO_CONVERTED_DIR = VIDEO_STORAGE_ROOT / 'converted'
VIDEO_ARCHIVE_DIR = VIDEO_STORAGE_ROOT / 'archive'
for _directory in (
    VIDEO_STORAGE_ROOT,
    VIDEO_ORIGINAL_DIR,
    VIDEO_RAW_DIR,
    VIDEO_CONVERTED_DIR,
    VIDEO_ARCHIVE_DIR,
):
    _directory.mkdir(parents=True, exist_ok=True)

ARCHIVE_ORIGINAL_UPLOADS = os.getenv('ARCHIVE_ORIGINAL_UPLOADS', '').strip().lower() in {
    '1', 'true', 'yes', 'on',
}

SUPPORTED_VIDEO_EXTENSIONS = {
    '.mp4', '.mov', '.avi', '.mkv', '.m4v', '.3gp', '.webm', '.mpeg', '.mpg', '.mts', '.m2ts',
}

SUPPORTED_VIDEO_CONTENT_TYPES = {
    'video/mp4',
    'video/quicktime',
    'video/x-msvideo',
    'video/x-matroska',
    'video/webm',
    'video/3gpp',
    'video/mpeg',
    'application/octet-stream',
}

OVERPASS_ENDPOINTS = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
]


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ── FASTAPI APP ────────────────────────────────────────────────────────────────
app = FastAPI(title='USL Crowdsource API', version='2.0')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'], allow_methods=['*'],
    allow_headers=['*'], allow_credentials=True,
)


@app.on_event('startup')
def startup_fix_cloudinary_urls():
    """Log reminder to fix Cloudinary URLs if needed."""
    print(
        '\n=== Video URL Fix ===\n'
        'If you have videos stored in Cloudinary, call:\n'
        '  POST /api/admin/fix-video-urls\n'
        'as an admin user to fix Cloudinary video URLs for browser playback.\n'
    )



# ══════════════════════════════════════════════════════════════════════════════
#  ORM MODELS  (mirrors existing DB schema – no FK constraints so migrations run)
# ══════════════════════════════════════════════════════════════════════════════

class School(Base):
    __tablename__ = 'schools'
    id               = Column(Integer, primary_key=True)
    name             = Column(String(200), nullable=False, unique=True)
    region           = Column(String(50),  nullable=False)
    district         = Column(String(100), nullable=False)
    contact_email    = Column(String(150), unique=True, nullable=False)
    phone            = Column(String(30))
    address          = Column(Text)
    latitude         = Column(Float)
    longitude        = Column(Float)
    school_type      = Column(String(30),  default='Primary')
    deaf_students    = Column(Integer,     default=0)
    year_established = Column(Integer)
    verified         = Column(Boolean,     default=False)
    created_at       = Column(DateTime,    default=datetime.utcnow)


class User(Base):
    __tablename__ = 'users'
    user_id    = Column('user_id', Integer, primary_key=True)
    username   = Column(String(80),  unique=True, nullable=False)
    email      = Column(String(150), unique=True, nullable=False)
    password   = Column(String(256), nullable=False)
    role       = Column(String(20),  default='SCHOOL_USER')
    school_id  = Column(Integer,     nullable=True)
    created_at = Column(DateTime,    default=datetime.utcnow)


class Video(Base):
    __tablename__ = 'videos'
    id               = Column(Integer, primary_key=True)
    school_id        = Column(Integer, nullable=True)
    uploader_id      = Column(Integer, nullable=True)
    file_path        = Column(Text,    nullable=False)
    converted        = Column(Boolean, default=False, nullable=False)
    converted_video_url = Column(Text, nullable=True)
    original_format  = Column(String(50), nullable=True)
    conversion_status = Column(String(20), nullable=False, default='completed')
    gloss_label      = Column(String(200))
    language_variant = Column(String(100))
    sign_category    = Column(String(100))
    sentence_type    = Column(String(50))
    region           = Column(String(50))
    district         = Column(String(100))
    uploader_latitude  = Column(Float, nullable=True)
    uploader_longitude = Column(Float, nullable=True)
    geo_source         = Column(String(50), nullable=True)
    duration         = Column(Float,   default=0)
    file_size_kb     = Column(Float,   default=0)
    verified_status  = Column(String(20), default='pending')
    status           = Column(String(20), default='pending')
    replaced_by      = Column(Integer, nullable=True)
    replaced_from    = Column(Integer, nullable=True)
    replaced_reason  = Column(Text, nullable=True)
    replaced_at      = Column(DateTime, nullable=True)
    replacement_admin_id = Column(Integer, nullable=True)
    upload_timestamp = Column(DateTime,   default=datetime.utcnow)


class HealthService(Base):
    __tablename__ = 'health_services'
    id                 = Column(Integer, primary_key=True)
    name               = Column(String(200), nullable=False)
    facility_type      = Column(String(100))
    district           = Column(String(100))
    region             = Column(String(50))
    latitude           = Column(Float)
    longitude          = Column(Float)
    services_available = Column(Text)
    deaf_friendly      = Column(Boolean, default=False)


# ── Data Warehouse ─────────────────────────────────────────────────────────────

class DimSchool(Base):
    __tablename__ = 'dim_school'
    school_key    = Column('school_id', Integer, primary_key=True)
    name          = Column(String(200))
    region        = Column(String(50))
    district      = Column(String(100))
    school_type   = Column(String(30))
    deaf_students = Column(Integer)
    latitude      = Column(Float)
    longitude     = Column(Float)


class DimRegion(Base):
    __tablename__ = 'dim_region'
    region_key  = Column(Integer, primary_key=True)
    region_name = Column(String(50))
    country     = Column(String(50), default='Uganda')


class DimDate(Base):
    __tablename__ = 'dim_date'
    date_id  = Column(Integer, primary_key=True)
    day      = Column(Integer)
    month    = Column(Integer)
    year     = Column(Integer)
    quarter  = Column(Integer)
    week     = Column(Integer)


class DimCategory(Base):
    __tablename__ = 'dim_category'
    category_id   = Column(Integer, primary_key=True)
    category_name = Column(String(100))


class FactVideoUpload(Base):
    __tablename__ = 'fact_video_uploads'
    fact_id         = Column(Integer, primary_key=True)
    video_id        = Column(Integer)
    school_key      = Column(Integer, nullable=True)
    region_key      = Column(Integer, nullable=True)
    date_id         = Column(Integer)
    category_id     = Column(Integer, nullable=True)
    total_uploads   = Column(Integer, default=1)
    total_duration  = Column(Float,   default=0)
    file_size_kb    = Column(Float,   default=0)
    verified_status = Column(String(20), default='pending')


class VideoReplacementAudit(Base):
    __tablename__ = 'video_replacement_audit'
    id                = Column(Integer, primary_key=True)
    original_video_id = Column(Integer, nullable=False)
    replaced_video_id = Column(Integer, nullable=False)
    admin_id          = Column(Integer, nullable=False)
    reason            = Column(Text, nullable=True)
    created_at        = Column(DateTime, default=datetime.utcnow)


# ── Legacy (read-only) ──────────────────────────────────────────────────────

class DimVideo(Base):
    __tablename__ = 'dim_video'
    video_id      = Column(Integer, primary_key=True)
    file_path     = Column(Text)
    language      = Column(String(50))
    gloss_label   = Column(String(100))
    sentence_type = Column(String(50))


# ── Create tables if missing ───────────────────────────────────────────────────
Base.metadata.create_all(bind=engine)


def _ensure_video_conversion_schema():
    if not database_url or engine.dialect.name != 'postgresql':
        return

    with engine.begin() as connection:
        connection.exec_driver_sql(
            """
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public' AND table_name = 'videos'
                ) THEN
                    ALTER TABLE public.videos
                        ADD COLUMN IF NOT EXISTS converted BOOLEAN,
                        ADD COLUMN IF NOT EXISTS converted_video_url TEXT,
                        ADD COLUMN IF NOT EXISTS original_format VARCHAR(50),
                        ADD COLUMN IF NOT EXISTS conversion_status VARCHAR(20);

                    UPDATE public.videos
                    SET converted = COALESCE(converted, false),
                        conversion_status = COALESCE(conversion_status, 'pending');
                END IF;
            END $$;
            """
        )


def _ensure_video_replacement_schema():
    if not database_url or engine.dialect.name != 'postgresql':
        return

    with engine.begin() as connection:
        connection.exec_driver_sql(
            """
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public' AND table_name = 'videos'
                ) THEN
                    ALTER TABLE public.videos
                        ADD COLUMN IF NOT EXISTS status VARCHAR(20),
                        ADD COLUMN IF NOT EXISTS replaced_by INTEGER,
                        ADD COLUMN IF NOT EXISTS replaced_from INTEGER,
                        ADD COLUMN IF NOT EXISTS replaced_reason TEXT,
                        ADD COLUMN IF NOT EXISTS replaced_at TIMESTAMP,
                        ADD COLUMN IF NOT EXISTS replacement_admin_id INTEGER;

                    UPDATE public.videos
                    SET status = COALESCE(status, verified_status, 'pending')
                    WHERE status IS NULL;
                END IF;
            END $$;
            """
        )


def _ensure_school_location_schema():
    if not database_url or engine.dialect.name != 'postgresql':
        return

    with engine.begin() as connection:
        connection.exec_driver_sql(
            """
            DO $$
            BEGIN
                IF EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public' AND table_name = 'schools'
                ) THEN
                    ALTER TABLE public.schools
                        ADD COLUMN IF NOT EXISTS address TEXT,
                        ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
                        ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
                END IF;
            END $$;
            """
        )


_ensure_video_conversion_schema()
_ensure_video_replacement_schema()
_ensure_school_location_schema()


def _geocode_address(address: str, district: str = '', region: str = '') -> tuple[float | None, float | None]:
    query_parts = [part.strip() for part in (address, district, region, 'Uganda') if part and part.strip()]
    if not query_parts:
        return None, None

    query = ', '.join(query_parts)
    url = (
        'https://nominatim.openstreetmap.org/search?'
        f'format=jsonv2&limit=1&countrycodes=ug&q={quote(query)}'
    )
    request = urlopen(
        UrlRequest(
            url,
            headers={'User-Agent': 'sign-video-warehouse/1.0 (school geocoding)'},
        ),
        timeout=15,
    )
    payload = json.loads(request.read().decode('utf-8'))
    if not payload:
        return None, None

    result = payload[0]
    return float(result['lat']), float(result['lon'])


def _normalize_original_format(filename: str, content_type: str) -> str:
    ext = Path(filename or '').suffix.lower().lstrip('.')
    if ext:
        return ext
    if content_type:
        return content_type.split('/', 1)[-1].replace('x-', '')
    return 'unknown'


def _looks_like_supported_video(filename: str, content_type: str) -> bool:
    ext = Path(filename or '').suffix.lower()
    normalized_content_type = (content_type or '').strip().lower()
    return ext in SUPPORTED_VIDEO_EXTENSIONS or normalized_content_type in SUPPORTED_VIDEO_CONTENT_TYPES


def _validate_video_file(path: Path) -> None:
    ffmpeg_path = _resolve_ffmpeg_binary('ffmpeg')
    probe = subprocess.run(
        [
            ffmpeg_path,
            '-v', 'error',
            '-i',
            str(path),
            '-f',
            'null',
            '-',
        ],
        capture_output=True,
        text=True,
    )
    if probe.returncode != 0:
        raise HTTPException(
            status_code=400,
            detail='Uploaded file is not a valid or readable video.',
        )

    if probe.returncode != 0:
        raise HTTPException(
            status_code=400,
            detail='Uploaded file is not a valid or readable video.',
        )


def _convert_to_browser_mp4(input_path: Path, output_path: Path) -> None:
    ffmpeg_path = _resolve_ffmpeg_binary('ffmpeg')
    command = [
        ffmpeg_path,
        '-y',
        '-nostdin',
        '-hide_banner',
        '-loglevel', 'error',
        '-i', str(input_path),
        '-map', '0:v:0',
        '-map', '0:a?',
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', '23',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac',
        '-b:a', '128k',
        '-movflags', '+faststart',
        str(output_path),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        message = (result.stderr or result.stdout or 'FFmpeg conversion failed').strip()
        raise HTTPException(status_code=400, detail=message)


def _normalize_conversion_status(value: Optional[str]) -> str:
    status_value = (value or '').strip().lower()
    if status_value == 'converted':
        return 'completed'
    if status_value in {'pending', 'processing', 'completed', 'failed'}:
        return status_value
    return 'pending'


def _resolve_ffmpeg_binary(binary_name: str) -> str:
    cached = shutil.which(binary_name)
    if cached:
        return cached

    local_app_data = Path(os.getenv('LOCALAPPDATA', ''))
    if local_app_data:
        win_get_packages = local_app_data / 'Microsoft' / 'WinGet' / 'Packages'
        if win_get_packages.exists():
            candidates = sorted(
                win_get_packages.glob(f'**/{binary_name}.exe'),
                key=lambda path: len(path.parts),
            )
            if candidates:
                return str(candidates[0])

    program_files = Path(os.getenv('ProgramFiles', r'C:\Program Files'))
    fallback_dir = program_files / 'ffmpeg' / 'bin'
    fallback_exe = fallback_dir / f'{binary_name}.exe'
    if fallback_exe.exists():
        return str(fallback_exe)

    if binary_name == 'ffmpeg':
        if imageio_ffmpeg is not None:
            bundled = Path(imageio_ffmpeg.get_ffmpeg_exe())
            if bundled.exists():
                return str(bundled)

    raise HTTPException(
        status_code=500,
        detail='FFmpeg must be installed on the server.',
    )


def _store_upload_as_mp4(upload: UploadFile) -> tuple[Path, str, float]:
    filename = upload.filename or 'upload.video'
    content_type = upload.content_type or ''
    if not _looks_like_supported_video(filename, content_type):
        raise HTTPException(
            status_code=400,
            detail='Unsupported video type. Upload MP4, MOV, AVI, MKV, M4V, 3GP, WebM, MPEG or MPG files.',
        )

    original_format = _normalize_original_format(filename, content_type)
    suffix = Path(filename).suffix.lower() or '.video'
    raw_path: Path | None = None
    converted_path: Path | None = None

    try:
        with tempfile.NamedTemporaryFile(
            mode='wb',
            suffix=suffix,
            dir=VIDEO_RAW_DIR,
            delete=False,
        ) as temp_file:
            upload.file.seek(0)
            shutil.copyfileobj(upload.file, temp_file)
            raw_path = Path(temp_file.name)

        _validate_video_file(raw_path)

        converted_name = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}_{uuid.uuid4().hex}.mp4"
        converted_path = VIDEO_CONVERTED_DIR / converted_name
        _convert_to_browser_mp4(raw_path, converted_path)

        if ARCHIVE_ORIGINAL_UPLOADS:
            archived_path = VIDEO_ARCHIVE_DIR / f'{converted_path.stem}{suffix}'
            shutil.move(str(raw_path), str(archived_path))
        elif raw_path.exists():
            raw_path.unlink()

        return converted_path, original_format, round(converted_path.stat().st_size / 1024, 1)
    except HTTPException:
        if converted_path and converted_path.exists():
            converted_path.unlink(missing_ok=True)
        raise
    except Exception as exc:
        if converted_path and converted_path.exists():
            converted_path.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=f'Video conversion failed: {exc}')
    finally:
        if raw_path and raw_path.exists() and not ARCHIVE_ORIGINAL_UPLOADS:
            raw_path.unlink(missing_ok=True)


def _public_video_url(video: Video, db: Session = None) -> str:
    if not video:
        return ''

    if video.converted_video_url:
        converted_path = Path(video.converted_video_url)
        if converted_path.exists():
            return f'/api/videos/{video.id}/stream'
        if video.converted_video_url.startswith('http://') or video.converted_video_url.startswith('https://'):
            # Ensure Cloudinary URLs are transformed for browser playback
            transformed = _to_browser_playable_video_url(video.converted_video_url)
            if transformed and transformed != video.converted_video_url and db is not None:
                video.converted_video_url = transformed
                db.commit()
            return transformed or video.converted_video_url

    file_path = (video.file_path or '').strip()
    if not file_path:
        return ''

    if file_path.startswith('http://') or file_path.startswith('https://'):
        transformed = _to_browser_playable_video_url(file_path)
        if transformed and transformed != file_path and db is not None:
            video.file_path = transformed
            video.converted_video_url = transformed
            video.conversion_status = 'completed'
            video.converted = True
            db.commit()
        return transformed or file_path

    if file_path.startswith('/api/'):
        return file_path

    if Path(file_path).exists():
        return f'/api/videos/{video.id}/stream'

    return file_path


def _video_conversion_source(video: Video) -> str:
    converted = (video.converted_video_url or '').strip()
    if converted:
        if converted.startswith('http://') or converted.startswith('https://'):
            return converted
        if converted.startswith('/api/'):
            return converted
        if Path(converted).exists():
            return converted

    file_path = (video.file_path or '').strip()
    if file_path:
        return file_path

    return converted


def _candidate_cloudinary_public_ids_from_path(path_value: str) -> list[str]:
    raw_value = (path_value or '').strip()
    if not raw_value:
        return []

    parsed = urlsplit(raw_value)
    candidate = parsed.path if parsed.scheme else raw_value
    if not candidate:
        return []

    stem = Path(candidate).stem
    if not stem:
        return []

    candidates = [
        stem,
        f'converted/{stem}',
        f'uploads/converted/{stem}',
        f'videos/{stem}',
    ]

    # Keep order while removing duplicates.
    seen = set()
    unique: list[str] = []
    for item in candidates:
        if item in seen:
            continue
        seen.add(item)
        unique.append(item)
    return unique


def _resolve_cloudinary_url_from_paths(*path_values: str) -> str:
    all_candidates: list[str] = []
    for value in path_values:
        all_candidates.extend(_candidate_cloudinary_public_ids_from_path(value))

    seen = set()
    ordered_candidates: list[str] = []
    for candidate in all_candidates:
        if candidate in seen:
            continue
        seen.add(candidate)
        ordered_candidates.append(candidate)

    for public_id in ordered_candidates:
        try:
            cloudinary.api.resource(public_id, resource_type='video', type='upload')
        except Exception:
            continue

        transformed, _ = cloudinary.utils.cloudinary_url(
            public_id,
            resource_type='video',
            type='upload',
            secure=True,
            format='mp4',
            transformation='f_mp4,vc_h264,q_auto',
        )
        return transformed or ''

    return ''


def _repair_video_source_from_cloudinary(video: Video, db: Session) -> bool:
    local_file = (video.file_path or '').strip()
    local_converted = (video.converted_video_url or '').strip()

    cloud_url = _resolve_cloudinary_url_from_paths(local_converted, local_file)
    if not cloud_url:
        return False

    video.converted_video_url = cloud_url
    video.file_path = cloud_url
    video.conversion_status = 'completed'
    video.converted = True
    db.commit()
    return True


def _cloudinary_delivery_mp4_url(public_id: str) -> str:
    if not public_id:
        return ''
    transformed, _ = cloudinary.utils.cloudinary_url(
        public_id,
        resource_type='video',
        type='upload',
        secure=True,
        format='mp4',
        transformation='f_mp4,vc_h264,q_auto',
    )
    return transformed or ''


def _fetch_cloudinary_video_resources(max_items: int = 500) -> list[dict]:
    resources: list[dict] = []
    next_cursor = None
    while len(resources) < max_items:
        search = cloudinary.search.Search().expression('resource_type:video').max_results(100)
        if next_cursor:
            search = search.next_cursor(next_cursor)
        payload = search.execute()
        batch = payload.get('resources') or []
        if not batch:
            break
        resources.extend(batch)
        next_cursor = payload.get('next_cursor')
        if not next_cursor:
            break
    return resources[:max_items]


def _extract_timestamp_from_video_path(path_value: str) -> Optional[datetime]:
    text = (path_value or '').strip()
    if not text:
        return None
    basename = Path(text).name
    match = re.match(r'^(\d{20})_', basename)
    if not match:
        return None
    try:
        parsed = datetime.strptime(match.group(1), '%Y%m%d%H%M%S%f')
        return parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def _parse_cloudinary_created_at(value: str) -> Optional[datetime]:
    raw = (value or '').strip()
    if not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace('Z', '+00:00')).astimezone(timezone.utc)
    except ValueError:
        return None


def _relink_missing_videos_from_cloudinary(db: Session, dry_run: bool = True) -> dict:
    resources = _fetch_cloudinary_video_resources(max_items=500)
    if not resources:
        return {
            'updated': 0,
            'checked': 0,
            'message': 'No Cloudinary video resources found for relink',
            'matches': [],
        }

    indexed = []
    for item in resources:
        public_id = (item.get('public_id') or '').strip()
        if not public_id:
            continue
        created_at = _parse_cloudinary_created_at(item.get('created_at') or '')
        bytes_value = int(item.get('bytes') or 0)
        indexed.append({'public_id': public_id, 'created_at': created_at, 'bytes': bytes_value})

    linked_urls = {
        (v.converted_video_url or '').strip()
        for v in db.query(Video).all()
        if (v.converted_video_url or '').strip().startswith('http')
    }
    used_public_ids = {
        row['public_id']
        for row in indexed
        if _cloudinary_delivery_mp4_url(row['public_id']) in linked_urls
    }

    candidates = []
    videos = db.query(Video).order_by(Video.id.asc()).all()
    for video in videos:
        current_source = _video_conversion_source(video).strip()
        if current_source.startswith('http://') or current_source.startswith('https://'):
            continue
        if current_source and Path(current_source).exists():
            continue

        expected_at = _extract_timestamp_from_video_path(video.file_path or '')
        if expected_at is None and video.upload_timestamp is not None:
            expected_at = video.upload_timestamp.replace(tzinfo=timezone.utc)

        expected_bytes = int(round((video.file_size_kb or 0) * 1024))
        best = None
        best_score = None
        for row in indexed:
            public_id = row['public_id']
            if public_id in used_public_ids:
                continue

            time_penalty = 0
            if expected_at is not None and row['created_at'] is not None:
                time_penalty = abs((row['created_at'] - expected_at).total_seconds())
            elif expected_at is not None:
                time_penalty = 86400 * 7

            size_penalty = 0
            if expected_bytes > 0 and row['bytes'] > 0:
                size_penalty = abs(row['bytes'] - expected_bytes) / expected_bytes * 3600

            score = time_penalty + size_penalty
            if best_score is None or score < best_score:
                best_score = score
                best = row

        if not best:
            continue

        # Prevent clearly unrelated matches.
        if best_score is not None and best_score > 86400 * 3:
            continue

        delivery_url = _cloudinary_delivery_mp4_url(best['public_id'])
        if not delivery_url:
            continue

        candidates.append({
            'video_id': video.id,
            'public_id': best['public_id'],
            'delivery_url': delivery_url,
            'score': round(float(best_score or 0), 2),
        })
        used_public_ids.add(best['public_id'])

    if not dry_run:
        for item in candidates:
            video = db.get(Video, item['video_id'])
            if not video:
                continue
            video.file_path = item['delivery_url']
            video.converted_video_url = item['delivery_url']
            video.converted = True
            video.conversion_status = 'completed'
        db.commit()

    return {
        'updated': 0 if dry_run else len(candidates),
        'checked': len(videos),
        'cloudinary_resources': len(indexed),
        'matches': candidates,
        'dry_run': dry_run,
    }


def _has_recoverable_video_source(video: Video) -> bool:
    source = _video_conversion_source(video).strip()
    if not source:
        return False
    if source.startswith('http://') or source.startswith('https://'):
        return True
    if source.startswith('/api/'):
        return True
    return Path(source).exists()


def _is_video_playable(video: Video) -> bool:
    path_value = _video_conversion_source(video).strip()
    if not path_value:
        return False

    if path_value.startswith('http://') or path_value.startswith('https://'):
        transformed = _to_browser_playable_video_url(path_value)
        return bool(transformed)

    if path_value.startswith('/api/'):
        return True

    local_path = Path(path_value)
    return local_path.exists() and local_path.suffix.lower() == '.mp4'


def _queue_existing_video_conversion(video_id: int) -> None:
    thread = threading.Thread(
        target=_convert_existing_video_record,
        args=(video_id,),
        daemon=True,
    )
    thread.start()


def _download_source_to_temp(source: str, target_dir: Path) -> Path:
    target_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='wb', delete=False, dir=target_dir) as temp_file:
        if source.startswith('http://') or source.startswith('https://'):
            with urlopen(source) as response:
                shutil.copyfileobj(response, temp_file)
        else:
            source_path = Path(source)
            if not source_path.exists():
                raise FileNotFoundError(source)
            with source_path.open('rb') as input_file:
                shutil.copyfileobj(input_file, temp_file)
        return Path(temp_file.name)


def _convert_existing_video_record(video_id: int) -> None:
    db: Session = SessionLocal()
    try:
        video = db.get(Video, video_id)
        if not video:
            return

        if _is_video_playable(video):
            video.conversion_status = 'completed'
            video.converted = True
            if not video.converted_video_url and video.file_path:
                video.converted_video_url = video.file_path
            db.commit()
            return

        video.conversion_status = 'processing'
        db.commit()

        source_ref = _video_conversion_source(video)
        if not source_ref:
            raise FileNotFoundError('missing source')

        source_name = Path(source_ref).name or f'video_{video.id}'
        temp_input = _download_source_to_temp(source_ref, VIDEO_RAW_DIR)
        converted_name = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}_{uuid.uuid4().hex}.mp4"
        converted_path = VIDEO_CONVERTED_DIR / converted_name
        _convert_to_browser_mp4(temp_input, converted_path)

        if temp_input.exists():
            temp_input.unlink(missing_ok=True)

        video.file_path = str(converted_path)
        video.converted_video_url = str(converted_path)
        video.converted = True
        video.original_format = video.original_format or Path(source_name).suffix.lower().lstrip('.') or 'unknown'
        video.file_size_kb = round(converted_path.stat().st_size / 1024, 1)
        video.conversion_status = 'completed'
        db.commit()
    except Exception as exc:
        db.rollback()
        video = db.get(Video, video_id)
        if video:
            video.conversion_status = 'failed'
            db.commit()
        print(f'ERROR converting existing video {video_id}: {type(exc).__name__}: {exc}')
    finally:
        db.close()

# Seed admin user if not present
_seed_db = SessionLocal()
try:
    if not _seed_db.query(User).filter_by(role='ADMIN').first():
        _seed_db.add(User(
            username='admin', email='admin@usl.ug',
            password=generate_password_hash('Admin@2026'),
            role='ADMIN'
        ))
        _seed_db.commit()
finally:
    _seed_db.close()

#  AUTH / JWT
_bearer = HTTPBearer(auto_error=False)


def _create_token(user_id: int) -> str:
    exp = datetime.utcnow() + JWT_EXPIRE
    return jwt.encode({'sub': str(user_id), 'exp': exp}, JWT_SECRET, algorithm=JWT_ALGO)


def _decode_token(token: str) -> int:
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGO])
        return int(payload['sub'])
    except (JWTError, KeyError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail='Invalid or expired token')


def get_current_user(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    if not creds:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail='Authorization header missing')
    uid  = _decode_token(creds.credentials)
    user = db.query(User).filter_by(user_id=uid).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED,
                            detail='User not found')
    return user


def require_admin(user: User = Depends(get_current_user)) -> User:
    if user.role != 'ADMIN':
        raise HTTPException(status_code=403, detail='Admin access required')
    return user


def _is_admin_email(email: str) -> bool:
    """Treat emails containing '.admin' in local-part as admin accounts."""
    e = (email or '').strip().lower()
    if '@' not in e:
        return False
    local = e.split('@', 1)[0]
    return '.admin' in local


def _to_browser_playable_video_url(url: str) -> str:
    """Return a Cloudinary delivery URL transformed to MP4/H264 for browser playback."""
    if not url:
        return ''

    parsed = urlsplit(url)
    if 'res.cloudinary.com' not in (parsed.netloc or '').lower():
        return url

    # Already MP4 delivery; keep as-is so transformation is idempotent.
    lower_path = (parsed.path or '').lower()
    if lower_path.endswith('.mp4') and '/video/upload/' in lower_path:
        return url

    segments = [s for s in parsed.path.split('/') if s]
    try:
        upload_idx = segments.index('upload')
    except ValueError:
        return url

    if upload_idx < 1 or segments[upload_idx - 1] != 'video':
        return url

    tail = segments[upload_idx + 1:]
    if not tail:
        return url

    version = None
    version_idx = next((i for i, p in enumerate(tail) if re.fullmatch(r'v\d+', p)), -1)
    if version_idx >= 0:
        version = tail[version_idx]
        public_parts = tail[version_idx + 1:]
    else:
        public_parts = tail

    if not public_parts:
        return url

    public_parts = public_parts.copy()
    public_parts[-1] = os.path.splitext(public_parts[-1])[0]
    if not public_parts[-1]:
        return url

    transformed = segments[:upload_idx + 1] + ['f_mp4,vc_h264,q_auto']
    if version:
        transformed.append(version)
    transformed.extend(public_parts)
    transformed[-1] = f"{transformed[-1]}.mp4"

    return urlunsplit((parsed.scheme, parsed.netloc, '/' + '/'.join(transformed), parsed.query, parsed.fragment))


def _legacy_video_playback_url(dim_video: DimVideo) -> str:
    source = (dim_video.file_path or '').strip()
    if not source:
        return ''

    if source.startswith('http://') or source.startswith('https://'):
        transformed = _to_browser_playable_video_url(source)
        return transformed or source

    if source.startswith('/api/'):
        return source

    if Path(source).exists():
        return f'/api/videos/{dim_video.video_id}/stream'

    return ''


def _legacy_video_file_for_stream(dim_video: DimVideo) -> Path:
    source = (dim_video.file_path or '').strip()
    source_path = Path(source)
    if not source or not source_path.exists():
        raise HTTPException(404, detail='Legacy video file not found')

    if source_path.suffix.lower() == '.mp4':
        return source_path

    converted_path = VIDEO_CONVERTED_DIR / f'legacy_{dim_video.video_id}.mp4'
    if not converted_path.exists():
        _convert_to_browser_mp4(source_path, converted_path)
    return converted_path

#  DW HELPERS
def _haversine(lat1, lon1, lat2, lon2) -> float:
    R = 6371
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp, dl = math.radians(lat2-lat1), math.radians(lon2-lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))


def _overpass_location(tags: dict, latitude: float, longitude: float) -> str:
    parts = [
        tags.get('addr:housenumber'),
        tags.get('addr:street'),
        tags.get('addr:suburb'),
        tags.get('addr:district'),
        tags.get('addr:city'),
        tags.get('addr:state'),
    ]
    address = ', '.join(part for part in parts if part)
    if address:
        return address

    place = tags.get('name') or tags.get('operator') or tags.get('brand') or 'Unknown location'
    return f'{place} ({latitude:.5f}, {longitude:.5f})'


def _fetch_overpass_health_facilities(latitude: float, longitude: float, radius_m: int = 5000) -> list[dict]:
    overpass_query = f'''
[out:json][timeout:25];
(
  node["amenity"~"^(hospital|clinic)$"](around:{radius_m},{latitude},{longitude});
  way["amenity"~"^(hospital|clinic)$"](around:{radius_m},{latitude},{longitude});
  relation["amenity"~"^(hospital|clinic)$"](around:{radius_m},{latitude},{longitude});
);
out center tags;
'''.strip()

    payload = None
    last_error = None
    for endpoint in OVERPASS_ENDPOINTS:
        request = UrlRequest(
            endpoint,
            data=f'data={quote(overpass_query)}'.encode('utf-8'),
            headers={
                'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                'User-Agent': 'sign_video_warehouse/1.0',
            },
        )

        try:
            with urlopen(request, timeout=30) as response:
                payload = json.load(response)
            break
        except Exception as error:
            last_error = error

    if payload is None:
        raise last_error or RuntimeError('Overpass query failed')

    facilities = []
    for element in payload.get('elements', []):
        tags = element.get('tags') or {}
        facility_lat = element.get('lat')
        facility_lon = element.get('lon')
        if facility_lat is None or facility_lon is None:
            center = element.get('center') or {}
            facility_lat = center.get('lat')
            facility_lon = center.get('lon')
        if facility_lat is None or facility_lon is None:
            continue

        facility_name = tags.get('name') or tags.get('operator') or tags.get('brand') or 'Health facility'
        distance_km = round(_haversine(latitude, longitude, facility_lat, facility_lon), 2)

        facilities.append({
            'name': facility_name,
            'location': _overpass_location(tags, facility_lat, facility_lon),
            'latitude': facility_lat,
            'longitude': facility_lon,
            'distance_km': distance_km,
            'amenity': tags.get('amenity', 'healthcare'),
        })

    facilities.sort(key=lambda item: item['distance_km'])
    return facilities


def _fallback_health_facilities(db: Session, latitude: float, longitude: float) -> list[dict]:
    facilities = []
    for h in db.query(HealthService).all():
        if h.latitude is None or h.longitude is None:
            continue
        location_bits = [h.district, h.region]
        facilities.append({
            'name': h.name,
            'location': ', '.join(bit for bit in location_bits if bit) or f'({h.latitude:.5f}, {h.longitude:.5f})',
            'latitude': h.latitude,
            'longitude': h.longitude,
            'distance_km': round(_haversine(latitude, longitude, h.latitude, h.longitude), 2),
            'amenity': h.facility_type or 'healthcare',
        })

    facilities.sort(key=lambda item: item['distance_km'])
    return facilities


def _ensure_date_key(dt: datetime, db: Session) -> int:
    e = db.query(DimDate).filter_by(day=dt.day, month=dt.month, year=dt.year).first()
    if not e:
        e = DimDate(day=dt.day, month=dt.month, year=dt.year,
                    quarter=(dt.month-1)//3+1, week=dt.isocalendar()[1])
        db.add(e); db.flush()
    return e.date_id


def _ensure_category_key(name: str, db: Session) -> int:
    n = name or 'Other'
    e = db.query(DimCategory).filter_by(category_name=n).first()
    if not e:
        e = DimCategory(category_name=n)
        db.add(e); db.flush()
    return e.category_id


def _ensure_school_key(school_id: Optional[int], db: Session) -> Optional[int]:
    if not school_id:
        return None
    e = db.query(DimSchool).filter(DimSchool.school_key == school_id).first()
    if not e:
        s = db.get(School, school_id)
        if s:
            e = DimSchool(school_key=s.id, name=s.name, region=s.region,
                          district=s.district, school_type=s.school_type,
                          deaf_students=s.deaf_students,
                          latitude=s.latitude, longitude=s.longitude)
            db.add(e); db.flush()
    return e.school_key if e else None


def _ensure_region_key(region_name: Optional[str], db: Session) -> Optional[int]:
    if not region_name:
        return None
    e = db.query(DimRegion).filter_by(region_name=region_name).first()
    if not e:
        e = DimRegion(region_name=region_name)
        db.add(e); db.flush()
    return e.region_key


def _parse_iso_datetime(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    raw = value.strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace('Z', '+00:00'))
        if parsed.tzinfo is not None:
            parsed = parsed.replace(tzinfo=None)
        return parsed
    except ValueError:
        return None


def _apply_video_scope(
    query,
    *,
    region: str = '',
    school_id: Optional[int] = None,
    start_date: str = '',
    end_date: str = '',
):
    if region:
        query = query.filter(Video.region == region)
    if school_id:
        query = query.filter(Video.school_id == school_id)

    start_dt = _parse_iso_datetime(start_date)
    if start_dt:
        query = query.filter(Video.upload_timestamp >= start_dt)

    end_dt = _parse_iso_datetime(end_date)
    if end_dt:
        query = query.filter(Video.upload_timestamp < end_dt + timedelta(days=1))

    return query


def _period_label(value: datetime, granularity: str) -> str:
    if granularity == 'day':
        return value.strftime('%Y-%m-%d')
    if granularity == 'week':
        year, week, _ = value.isocalendar()
        return f'{year}-W{week:02d}'
    return value.strftime('%Y-%m')

#  AUTH ENDPOINTS
@app.get('/api/health')
def health_check():
    return {'status': 'ok', 'version': '2.0', 'framework': 'FastAPI'}


@app.get('/api/meta/categories')
def meta_categories():
    return {'categories': CATEGORIES, 'regions': REGIONS, 'school_types': SCHOOL_TYPES}


@app.post('/api/register-school', status_code=201)
def register_school(data: dict, db: Session = Depends(get_db)):
    required = ['school_name', 'region', 'district', 'contact_email', 'username', 'password']
    missing  = [f for f in required if not (data.get(f) or '').strip()]
    if missing:
        raise HTTPException(400, detail=f'Fields required: {", ".join(missing)}')
    if data['region'] not in REGIONS:
        raise HTTPException(400, detail=f'Region must be one of: {", ".join(REGIONS)}')
    contact_email = data['contact_email'].strip()
    username = data['username'].strip()

    if db.query(School).filter_by(contact_email=contact_email).first():
        raise HTTPException(409, detail='School email already registered')
    if db.query(User).filter(
        or_(User.username == username, User.email == contact_email)
    ).first():
        raise HTTPException(409, detail='Username or email already exists')

    role = 'ADMIN' if _is_admin_email(contact_email) else 'SCHOOL_USER'

    def _optional_float(value):
        if value in (None, ''):
            return None
        try:
            return float(value)
        except (TypeError, ValueError):
            raise HTTPException(400, detail='Latitude and longitude must be valid numbers')

    address = (data.get('address') or '').strip()
    latitude = _optional_float(data.get('latitude'))
    longitude = _optional_float(data.get('longitude'))

    if (latitude is None) != (longitude is None):
        raise HTTPException(400, detail='Enter both latitude and longitude, or leave both blank')

    if latitude is None and longitude is None and address:
        latitude, longitude = _geocode_address(address, data['district'].strip(), data['region'])
        if latitude is None or longitude is None:
            raise HTTPException(
                400,
                detail='Could not locate that address. Please refine it or enter coordinates manually.',
            )

    school = School(
        name=data['school_name'].strip(), region=data['region'],
        district=data['district'].strip(), contact_email=contact_email,
        phone=(data.get('phone') or '').strip(),
        address=address or None,
        latitude=latitude, longitude=longitude,
        school_type=data.get('school_type', 'Primary'),
        deaf_students=int(data.get('deaf_students') or 0),
        year_established=int(data.get('year_established') or 0) or None,
    )
    db.add(school); db.flush()

    user = User(
        username=username,
        email=contact_email,
        password=generate_password_hash(data['password']),
        role=role,
        school_id=school.id,
    )
    db.add(user); db.commit()
    return {
        'message': 'School registered successfully',
        'school_id': school.id,
        'role': role,
    }


@app.post('/api/register', status_code=201)
def register(data: dict, db: Session = Depends(get_db)):
    u = (data.get('username') or '').strip()
    e = (data.get('email')    or '').strip()
    p = (data.get('password') or '').strip()
    if not u or not e or not p:
        raise HTTPException(400, detail='username, email and password required')
    if db.query(User).filter(or_(User.username == u, User.email == e)).first():
        raise HTTPException(409, detail='Username or email already exists')
    role = 'ADMIN' if _is_admin_email(e) else 'SCHOOL_USER'
    db.add(User(username=u, email=e,
                password=generate_password_hash(p), role=role))
    db.commit()
    return {'message': 'Registered successfully', 'role': role}


@app.post('/api/login')
def login(data: dict, db: Session = Depends(get_db)):
    ident = (data.get('username') or '').strip()
    pwd   = (data.get('password') or '').strip()
    user  = db.query(User).filter(
        or_(User.username == ident, User.email == ident)
    ).first()
    if not user or not check_password_hash(user.password, pwd):
        raise HTTPException(401, detail='Invalid credentials')

    # Backfill older accounts so .admin emails always get admin access.
    if user.role != 'ADMIN' and _is_admin_email(user.email):
        user.role = 'ADMIN'
        db.commit()
        db.refresh(user)

    token       = _create_token(user.user_id)
    school_info = None
    if user.school_id:
        s = db.get(School, user.school_id)
        if s:
            school_info = {'id': s.id, 'name': s.name,
                           'region': s.region, 'district': s.district}
    return {
        'access_token': token,
        'user': {
            'id': user.user_id, 'username': user.username,
            'email': user.email, 'role': user.role, 'school': school_info,
        },
    }

#  VIDEO
async def _handle_upload(
    file: UploadFile,
    gloss_label:     str,
    language:        str,
    sentence_type:   str,
    sign_category:   str,
    region:          str,
    district:        str,
    latitude:        Optional[float],
    longitude:       Optional[float],
    geo_source:      str,
    duration:        float,
    user: User,
    db:  Session,
):
    try:
        converted_path, original_format, size_kb = await asyncio.to_thread(
            _store_upload_as_mp4,
            file,
        )

        # If region/district not provided, fall back to school's values
        if not region and user.school_id:
            s = db.get(School, user.school_id)
            region = (s.region   or '') if s else ''
        if not district and user.school_id:
            s = db.get(School, user.school_id)
            district = (s.district or '') if s else ''

        resolved_geo_source = (geo_source or '').strip() or (
            'device_gps' if latitude is not None and longitude is not None
            else 'declared_region_district'
        )

        video = Video(
            school_id=user.school_id, uploader_id=user.user_id,
            file_path=str(converted_path),
            converted=True,
            converted_video_url=str(converted_path),
            original_format=original_format,
            conversion_status='completed',
            gloss_label=gloss_label,
            language_variant=language,
            sign_category=sign_category or 'Other',
            sentence_type=sentence_type,
            region=region, district=district,
            uploader_latitude=latitude,
            uploader_longitude=longitude,
            geo_source=resolved_geo_source,
            duration=duration, file_size_kb=size_kb,
            verified_status='pending',
            status='pending',
        )
        db.add(video); db.flush()

        now = datetime.utcnow()
        fact = FactVideoUpload(
            video_id=video.id,
            school_key=_ensure_school_key(user.school_id, db),
            region_key=_ensure_region_key(region, db),
            date_id=_ensure_date_key(now, db),
            category_id=_ensure_category_key(sign_category, db),
            total_uploads=1, total_duration=duration,
            file_size_kb=size_kb, verified_status='pending',
        )
        db.add(fact); db.commit()
        playback_url = _public_video_url(video, db)
        return {'message': 'Video uploaded successfully',
            'video_id': video.id,
            'verified_status': 'pending',
            'status': 'pending',
            'video_url': playback_url,
            'playback_url': playback_url,
            'file_path': str(converted_path),
            'converted': True,
            'converted_video_url': str(converted_path),
            'original_format': original_format,
            'conversion_status': 'completed',
            'uploader_latitude': video.uploader_latitude,
            'uploader_longitude': video.uploader_longitude,
            'geo_source': resolved_geo_source}
    except Exception as e:
        db.rollback()
        print(f"ERROR in _handle_upload: {type(e).__name__}: {str(e)}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Upload failed: {str(e)}")


@app.post('/api/upload', status_code=201)
async def upload_video(
    file:          UploadFile = File(...),
    gloss_label:   str = Form(''),
    language:      str = Form(''),
    language_variant: str = Form(''),
    sentence_type: str = Form(''),
    category:      str = Form(''),
    sign_category: str = Form(''),
    region:        str = Form(''),
    district:      str = Form(''),
    latitude:      Optional[float] = Form(None),
    longitude:     Optional[float] = Form(None),
    geo_source:    str = Form(''),
    duration:      float = Form(0.0),
    # legacy fields ignored but accepted
    organization:  str = Form(''),
    sector:        str = Form(''),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    lang = language or language_variant
    cat  = sign_category or category or 'Other'
    return await _handle_upload(file, gloss_label, lang, sentence_type,
                                cat, region, district, latitude, longitude,
                                geo_source, duration, user, db)


@app.post('/api/upload-video', status_code=201)
async def upload_video_alt(
    file:          UploadFile = File(...),
    gloss_label:   str = Form(''),
    language:      str = Form(''),
    language_variant: str = Form(''),
    sentence_type: str = Form(''),
    category:      str = Form(''),
    sign_category: str = Form(''),
    region:        str = Form(''),
    district:      str = Form(''),
    latitude:      Optional[float] = Form(None),
    longitude:     Optional[float] = Form(None),
    geo_source:    str = Form(''),
    duration:      float = Form(0.0),
    organization:  str = Form(''),
    sector:        str = Form(''),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    lang = language or language_variant
    cat  = sign_category or category or 'Other'
    return await _handle_upload(file, gloss_label, lang, sentence_type,
                                cat, region, district, latitude, longitude,
                                geo_source, duration, user, db)


def _fmt_video(v: Video, db: Session) -> dict:
    school   = db.get(School, v.school_id) if v.school_id else None
    uploader = db.query(User).filter_by(user_id=v.uploader_id).first() if v.uploader_id else None
    playback_url = _public_video_url(v, db)
    return {
        'video_id':        v.id,
        'gloss_label':     v.gloss_label,
        'language':        v.language_variant,
        'language_variant': v.language_variant,
        'sign_category':   v.sign_category,
        'category':        v.sign_category,
        'sentence_type':   v.sentence_type,
        'region':          v.region,
        'district':        v.district,
        'uploader_latitude': v.uploader_latitude,
        'uploader_longitude': v.uploader_longitude,
        'geo_source':      v.geo_source,
        'file_path':       v.file_path,
        'converted':       bool(v.converted),
        'converted_video_url': v.converted_video_url or '',
        'original_format':  v.original_format or '',
        'conversion_status': _normalize_conversion_status(v.conversion_status),
        'video_url':       playback_url,
        'playback_url':    playback_url,
        'file_size_kb':    round(v.file_size_kb or 0, 1),
        'duration':        v.duration,
        'verified_status': v.verified_status,
        'status':          v.status or v.verified_status,
        'replaced_by':     v.replaced_by,
        'replaced_from':   v.replaced_from,
        'replaced_reason': v.replaced_reason,
        'replaced_at':     str(v.replaced_at) if v.replaced_at else '',
        'replacement_admin_id': v.replacement_admin_id,
        'upload_date':     str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
        'created_at':      str(v.upload_timestamp) if v.upload_timestamp else '',
        'school_name':     school.name if school else 'Individual',
        'uploader':        uploader.username if uploader else '',
    }


@app.get('/api/videos')
def list_videos(
    search:   str = Query(''),
    language: str = Query(''),
    category: str = Query(''),
    region:   str = Query(''),
    status:   str = Query(''),
    page:     int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    q = db.query(Video)
    if user.role != 'ADMIN' and user.school_id:
        q = q.filter(Video.school_id == user.school_id)

    if search:   q = q.filter(Video.gloss_label.ilike(f'%{search}%'))
    if language: q = q.filter(Video.language_variant.ilike(f'%{language}%'))
    if category: q = q.filter(Video.sign_category.ilike(f'%{category}%'))
    if region:   q = q.filter(Video.region.ilike(f'%{region}%'))
    if status:   q = q.filter(Video.verified_status == status)

    total  = q.count()
    videos = q.order_by(Video.upload_timestamp.desc()) \
               .offset((page-1)*per_page).limit(per_page).all()

    return {'videos': [_fmt_video(v, db) for v in videos],
            'total': total, 'page': page, 'per_page': per_page}


@app.get('/api/videos/{video_id}')
def get_video(video_id: int,
              user: User = Depends(get_current_user),
              db:   Session = Depends(get_db)):
    v = db.get(Video, video_id)
    if not v:
        # fallback to legacy DimVideo
        dv = db.get(DimVideo, video_id)
        if dv:
            playback_url = _legacy_video_playback_url(dv)
            return {'video_id': dv.video_id, 'gloss_label': dv.gloss_label,
                    'language': dv.language,
                    'file_path': dv.file_path,
                'video_url': playback_url,
                'playback_url': playback_url,
                    'verified_status': 'approved'}
        raise HTTPException(404, detail='Video not found')
    if not _is_video_playable(v):
        # Recover legacy records that still reference old local paths by
        # resolving the same filename in Cloudinary and persisting that URL.
        if _repair_video_source_from_cloudinary(v, db):
            db.refresh(v)
            return _fmt_video(v, db)

        if not _has_recoverable_video_source(v):
            return JSONResponse(
                status_code=404,
                content={
                    'message': 'Video source is unavailable in this environment. Re-upload this video to restore playback.',
                    'video_id': v.id,
                    'converted': bool(v.converted),
                    'conversion_status': 'failed',
                    'video_url': '',
                    'playback_url': '',
                },
            )
        if _normalize_conversion_status(v.conversion_status) != 'processing':
            _queue_existing_video_conversion(video_id)
        return JSONResponse(
            status_code=202,
            content={
                'message': 'Video is being processed, please try again shortly',
                'video_id': v.id,
                'converted': bool(v.converted),
                'conversion_status': 'processing',
                'video_url': '',
                'playback_url': '',
            },
        )
    return _fmt_video(v, db)


@app.get('/api/videos/{video_id}/stream')
def stream_video(
    video_id: int,
    db:   Session = Depends(get_db),
):
    video = db.get(Video, video_id)
    if not video:
        # fallback to legacy DimVideo
        dim_video = db.get(DimVideo, video_id)
        if not dim_video:
            raise HTTPException(404, detail='Video not found')

        source = (dim_video.file_path or '').strip()
        if source.startswith('http://') or source.startswith('https://'):
            transformed = _to_browser_playable_video_url(source)
            return RedirectResponse(url=transformed or source, status_code=302)

        if source.startswith('/api/'):
            return RedirectResponse(url=source, status_code=302)

        file_path = _legacy_video_file_for_stream(dim_video)
        return FileResponse(
            path=str(file_path),
            media_type='video/mp4',
            filename=file_path.name,
        )

    if not _is_video_playable(video):
        if _repair_video_source_from_cloudinary(video, db):
            db.refresh(video)
            return RedirectResponse(url=_public_video_url(video, db), status_code=302)

        if not _has_recoverable_video_source(video):
            return JSONResponse(
                status_code=404,
                content={
                    'message': 'Video source is unavailable in this environment. Re-upload this video to restore playback.',
                },
            )
        if _normalize_conversion_status(video.conversion_status) != 'processing':
            _queue_existing_video_conversion(video_id)
        return JSONResponse(
            status_code=202,
            content={'message': 'Video is being processed, please try again shortly'},
        )

    # Prefer a real playable source. This avoids stale converted paths
    # blocking playback when an original remote URL still exists.
    video_url = _video_conversion_source(video)
    if video_url.startswith('http://') or video_url.startswith('https://'):
        transformed = _to_browser_playable_video_url(video_url)
        if transformed and transformed != video_url:
            video.converted_video_url = transformed
            if (video.file_path or '').strip() == video_url:
                video.file_path = transformed
            video.conversion_status = 'completed'
            video.converted = True
            db.commit()
        return RedirectResponse(url=transformed or video_url, status_code=302)

    file_path = Path(video_url)
    if not file_path.exists():
        raise HTTPException(404, detail='Video file not found')

    return FileResponse(
        path=str(file_path),
        media_type='video/mp4',
        filename=file_path.name,
    )


@app.post('/api/videos/{video_id}/verify')
def verify_video(
    video_id: int,
    data: dict,
    user: User = Depends(require_admin),
    db:   Session = Depends(get_db),
):
    v = db.get(Video, video_id)
    if not v:
        raise HTTPException(404, detail='Not found')
    new_status = data.get('status', 'approved')
    if new_status not in VERIFIED:
        raise HTTPException(400, detail=f'status must be one of {VERIFIED}')
    v.verified_status = new_status
    v.status = new_status
    fct = db.query(FactVideoUpload).filter_by(video_id=video_id).first()
    if fct:
        fct.verified_status = new_status
    db.commit()
    return {'message': f'Video {new_status}', 'video_id': video_id}


@app.post('/api/videos/{video_id}/replace', status_code=201)
async def replace_video(
    video_id: int,
    file: UploadFile = File(...),
    reason: str = Form(''),
    duration: float = Form(0.0),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    original = db.get(Video, video_id)
    if not original:
        raise HTTPException(404, detail='Video not found')

    try:
        converted_path, original_format, size_kb = await asyncio.to_thread(
            _store_upload_as_mp4,
            file,
        )

        new_video = Video(
            school_id=original.school_id,
            uploader_id=user.user_id,
            file_path=str(converted_path),
            converted=True,
            converted_video_url=str(converted_path),
            original_format=original_format,
            conversion_status='completed',
            gloss_label=original.gloss_label,
            language_variant=original.language_variant,
            sign_category=original.sign_category,
            sentence_type=original.sentence_type,
            region=original.region,
            district=original.district,
            uploader_latitude=original.uploader_latitude,
            uploader_longitude=original.uploader_longitude,
            geo_source=original.geo_source,
            duration=duration or original.duration or 0,
            file_size_kb=size_kb,
            verified_status='pending',
            status='pending',
            replaced_from=original.id,
        )
        db.add(new_video)
        db.flush()

        now = datetime.utcnow()
        original.verified_status = 'replaced'
        original.status = 'replaced'
        original.replaced_by = new_video.id
        original.replaced_reason = (reason or '').strip() or None
        original.replaced_at = now
        original.replacement_admin_id = user.user_id

        db.add(
            VideoReplacementAudit(
                original_video_id=original.id,
                replaced_video_id=new_video.id,
                admin_id=user.user_id,
                reason=(reason or '').strip() or None,
            )
        )
        db.commit()
        db.refresh(original)
        db.refresh(new_video)
        playback_url = _public_video_url(new_video)

        return {
            'message': 'Video successfully replaced',
            'original_video_id': original.id,
            'replaced_video_id': new_video.id,
            'original_video': _fmt_video(original, db),
            'replacement_video': _fmt_video(new_video, db),
            'video_url': playback_url,
            'playback_url': playback_url,
        }
    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        print(f"ERROR in replace_video: {type(e).__name__}: {str(e)}")
        raise HTTPException(status_code=500, detail=f'Replacement failed: {str(e)}')

#  SCHOOL ANALYTICS
@app.get('/api/schools/{school_id}/analytics')
def school_analytics(
    school_id: int,
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    if user.role != 'ADMIN' and user.school_id != school_id:
        raise HTTPException(403, detail='Forbidden')
    s = db.get(School, school_id)
    if not s:
        raise HTTPException(404, detail='School not found')

    total    = db.query(Video).filter_by(school_id=school_id).count()
    approved = db.query(Video).filter_by(school_id=school_id, verified_status='approved').count()
    pending  = db.query(Video).filter_by(school_id=school_id, verified_status='pending').count()
    rejected = db.query(Video).filter_by(school_id=school_id, verified_status='rejected').count()

    monthly = db.query(
        func.date_trunc('month', Video.upload_timestamp).label('m'),
        func.count().label('c'),
    ).filter(Video.school_id == school_id).group_by('m').order_by('m').all()

    by_cat = db.query(
        Video.sign_category, func.count().label('c')
    ).filter(Video.school_id == school_id).group_by(Video.sign_category).all()

    return {
        # Flat fields Flutter dashboard uses directly
        'school_name':   s.name,
        'school_region': s.region,
        'school_district': s.district,
        # KPI
        'total_uploads': total,
        'approved':      approved,
        'pending':       pending,
        'rejected':      rejected,
        'ratio': round(total / max(s.deaf_students or 1, 1), 3),
        # Charts – key names match Flutter
        'monthly_trend': [{'month': str(m.m)[:7], 'count': m.c} for m in monthly],
        'by_category':   [{'sign_category': c or 'Other', 'count': n} for c, n in by_cat],
        # Full school object for other uses
        'school': {
            'id': s.id, 'name': s.name, 'region': s.region,
            'district': s.district, 'school_type': s.school_type,
            'deaf_students': s.deaf_students,
            'address': s.address,
            'latitude': s.latitude, 'longitude': s.longitude,
        },
    }


@app.get('/api/schools/{school_id}/nearby-health')
@app.get('/api/schools/{school_id}/health-nearby')
def nearby_health(
    school_id: int,
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    s = db.get(School, school_id)
    if not s:
        raise HTTPException(404, detail='School not found')
    if s.latitude is None or s.longitude is None:
        return {'facilities': [], 'message': 'School has no GPS coordinates'}

    try:
        facilities = _fetch_overpass_health_facilities(s.latitude, s.longitude)
    except Exception:
        facilities = _fallback_health_facilities(db, s.latitude, s.longitude)

    return {
        'school': {
            'id': s.id,
            'name': s.name,
            'latitude': s.latitude,
            'longitude': s.longitude,
        },
        'facilities': facilities[:10],
    }


# ══════════════════════════════════════════════════════════════════════════════
#  ADMIN ANALYTICS
# ══════════════════════════════════════════════════════════════════════════════

@app.get('/api/admin/analytics/overview')
def admin_overview(
    region: str = Query(''),
    school_id: Optional[int] = Query(None),
    start_date: str = Query(''),
    end_date: str = Query(''),
    granularity: str = Query('month'),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    granularity = granularity if granularity in {'day', 'week', 'month'} else 'month'

    video_scope = _apply_video_scope(
        db.query(Video),
        region=region,
        school_id=school_id,
        start_date=start_date,
        end_date=end_date,
    )
    school_scope = db.query(School)
    if region:
        school_scope = school_scope.filter(School.region == region)
    if school_id:
        school_scope = school_scope.filter(School.id == school_id)

    total_schools = school_scope.count()
    total_regions = school_scope.with_entities(func.count(distinct(School.region))).scalar() or 0
    total_videos = video_scope.count()
    total_uploads = total_videos
    total_students = school_scope.with_entities(func.coalesce(func.sum(School.deaf_students), 0)).scalar() or 0

    schools_per_region_rows = school_scope.with_entities(
        School.region,
        func.count(School.id).label('count'),
    ).group_by(School.region).order_by(func.count(School.id).desc(), School.region.asc()).all()

    uploads_by_region_rows = video_scope.with_entities(
        Video.region,
        func.count(Video.id).label('uploads'),
    ).group_by(Video.region).order_by(func.count(Video.id).desc(), Video.region.asc()).all()

    sign_rows = video_scope.with_entities(
        Video.gloss_label,
        func.count(Video.id).label('uploads'),
        func.count(distinct(Video.region)).label('region_count'),
        func.count(distinct(Video.school_id)).label('school_count'),
    ).filter(Video.gloss_label.isnot(None)).group_by(Video.gloss_label).order_by(
        func.count(Video.id).desc(),
        Video.gloss_label.asc(),
    ).all()

    top_signs = [{
        'gloss_label': gloss or 'Unknown',
        'uploads': int(uploads or 0),
        'regions': int(region_count or 0),
        'schools': int(school_count or 0),
    } for gloss, uploads, region_count, school_count in sign_rows[:10]]

    most_active_region = None
    if uploads_by_region_rows:
        region_name, region_uploads = uploads_by_region_rows[0]
        most_active_region = {
            'region': region_name or 'Unknown',
            'uploads': int(region_uploads or 0),
        }

    most_active_school_row = video_scope.outerjoin(School, School.id == Video.school_id).with_entities(
        School.id,
        School.name,
        School.region,
        func.count(Video.id).label('uploads'),
    ).group_by(School.id, School.name, School.region).order_by(
        func.count(Video.id).desc(),
        School.name.asc(),
    ).first()

    most_active_school = None
    if most_active_school_row:
        school_id_value, school_name, school_region, uploads = most_active_school_row
        most_active_school = {
            'school_id': school_id_value,
            'school_name': school_name or 'Individual',
            'region': school_region or 'Unknown',
            'uploads': int(uploads or 0),
        }

    gloss_region_rows = video_scope.with_entities(
        Video.gloss_label,
        Video.region,
        func.count(Video.id).label('uploads'),
    ).filter(Video.gloss_label.isnot(None)).group_by(
        Video.gloss_label,
        Video.region,
    ).all()

    gloss_school_rows = video_scope.with_entities(
        Video.gloss_label,
        func.count(distinct(Video.school_id)).label('school_count'),
    ).filter(Video.gloss_label.isnot(None)).group_by(Video.gloss_label).all()

    school_count_by_gloss = {
        (gloss or 'Unknown'): int(count or 0)
        for gloss, count in gloss_school_rows
    }

    duplicate_map = {}
    duplicate_matrix = []
    for gloss, region_name, uploads in gloss_region_rows:
        gloss_name = gloss or 'Unknown'
        region_name = region_name or 'Unknown'
        duplicate_matrix.append({
            'gloss_label': gloss_name,
            'region': region_name,
            'uploads': int(uploads or 0),
        })
        entry = duplicate_map.setdefault(gloss_name, {
            'gloss_label': gloss_name,
            'total_uploads': 0,
            'regions': {},
            'school_count': school_count_by_gloss.get(gloss_name, 0),
        })
        entry['total_uploads'] += int(uploads or 0)
        entry['regions'][region_name] = int(uploads or 0)

    duplicate_signs = []
    for entry in duplicate_map.values():
        regions_involved = list(entry['regions'].keys())
        if len(regions_involved) < 2:
            continue
        duplicate_signs.append({
            'gloss_label': entry['gloss_label'],
            'total_uploads': entry['total_uploads'],
            'duplicate_uploads': max(entry['total_uploads'] - len(regions_involved), 0),
            'region_count': len(regions_involved),
            'regions_involved': regions_involved,
            'school_count': entry['school_count'],
        })
    duplicate_signs.sort(
        key=lambda row: (-row['duplicate_uploads'], -row['total_uploads'], row['gloss_label'])
    )

    trend_rows = video_scope.with_entities(
        func.date_trunc(granularity, Video.upload_timestamp).label('period'),
        func.count(Video.id).label('uploads'),
    ).group_by('period').order_by('period').all()

    upload_trend = []
    for period, uploads in trend_rows:
        if period is None:
            continue
        upload_trend.append({
            'period': _period_label(period, granularity),
            'uploads': int(uploads or 0),
        })

    return {
        'filters': {
            'region': region,
            'school_id': school_id,
            'start_date': start_date,
            'end_date': end_date,
            'granularity': granularity,
        },
        'total_schools': int(total_schools),
        'total_regions': int(total_regions),
        'total_videos': int(total_videos),
        'total_uploads': int(total_uploads),
        'total_students': int(total_students),
        'most_active_region': most_active_region,
        'most_active_school': most_active_school,
        'kpis': {
            'total_schools': int(total_schools),
            'total_regions': int(total_regions),
            'total_videos': int(total_videos),
            'total_uploads': int(total_uploads),
            'most_active_region': most_active_region,
            'most_active_school': most_active_school,
        },
        'schools_per_region': [
            {'region': region_name or 'Unknown', 'count': int(count or 0)}
            for region_name, count in schools_per_region_rows
        ],
        'uploads_by_region': [
            {'region': region_name or 'Unknown', 'uploads': int(uploads or 0)}
            for region_name, uploads in uploads_by_region_rows
        ],
        'duplicate_signs': duplicate_signs,
        'duplicate_matrix': duplicate_matrix,
        'top_signs': top_signs,
        'upload_trend': upload_trend,
    }


@app.get('/api/admin/analytics/schools')
def admin_schools_analytics(
    region: str = Query(''),
    school_id: Optional[int] = Query(None),
    start_date: str = Query(''),
    end_date: str = Query(''),
    granularity: str = Query('month'),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    granularity = granularity if granularity in {'day', 'week', 'month'} else 'month'
    video_scope = _apply_video_scope(
        db.query(Video),
        region=region,
        school_id=school_id,
        start_date=start_date,
        end_date=end_date,
    ).filter(Video.school_id.isnot(None))

    school_scope = db.query(School)
    if region:
        school_scope = school_scope.filter(School.region == region)
    if school_id:
        school_scope = school_scope.filter(School.id == school_id)

    school_options = school_scope.with_entities(
        School.id,
        School.name,
        School.region,
        School.district,
    ).order_by(School.region.asc(), School.name.asc()).all()

    school_rows = video_scope.outerjoin(School, School.id == Video.school_id).with_entities(
        School.id,
        School.name,
        School.region,
        func.count(Video.id).label('uploads'),
        func.min(Video.upload_timestamp).label('first_upload'),
        func.max(Video.upload_timestamp).label('last_upload'),
    ).group_by(School.id, School.name, School.region).order_by(
        func.count(Video.id).desc(),
        School.name.asc(),
    ).all()

    uploads_per_school = []
    average_frequency = []
    for school_id_value, school_name, school_region, uploads, first_upload, last_upload in school_rows:
        upload_count = int(uploads or 0)
        uploads_per_school.append({
            'school_id': school_id_value,
            'school_name': school_name or 'Individual',
            'region': school_region or 'Unknown',
            'uploads': upload_count,
        })

        if upload_count > 1 and first_upload and last_upload:
            span_days = max((last_upload - first_upload).total_seconds() / 86400.0, 0.0)
            avg_days = span_days / max(upload_count - 1, 1)
        else:
            avg_days = 0.0
        average_frequency.append({
            'school_id': school_id_value,
            'school_name': school_name or 'Individual',
            'region': school_region or 'Unknown',
            'uploads': upload_count,
            'average_days_between_uploads': round(avg_days, 2),
        })

    region_groups = {}
    region_rows = video_scope.outerjoin(School, School.id == Video.school_id).with_entities(
        School.region,
        School.name,
        func.count(Video.id).label('uploads'),
    ).group_by(School.region, School.name).order_by(
        School.region.asc(),
        func.count(Video.id).desc(),
        School.name.asc(),
    ).all()

    for region_name, school_name, uploads in region_rows:
        region_label = region_name or 'Unknown'
        region_entry = region_groups.setdefault(region_label, {
            'region': region_label,
            'total_uploads': 0,
            'schools': [],
        })
        upload_count = int(uploads or 0)
        region_entry['total_uploads'] += upload_count
        region_entry['schools'].append({
            'school_name': school_name or 'Individual',
            'uploads': upload_count,
        })

    timeline_school_ids = [school_id] if school_id else [row[0] for row in school_rows[:5] if row[0] is not None]
    timeline_rows = []
    if timeline_school_ids:
        timeline_rows = video_scope.outerjoin(School, School.id == Video.school_id).with_entities(
            School.id,
            School.name,
            func.date_trunc(granularity, Video.upload_timestamp).label('period'),
            func.count(Video.id).label('uploads'),
        ).filter(Video.school_id.in_(timeline_school_ids)).group_by(
            School.id,
            School.name,
            'period',
        ).order_by('period').all()

    timeline_map = {}
    for school_id_value, school_name, period, uploads in timeline_rows:
        if period is None:
            continue
        key = str(school_id_value or school_name or 'Unknown')
        series = timeline_map.setdefault(key, {
            'school_id': school_id_value,
            'school_name': school_name or 'Individual',
            'points': [],
        })
        series['points'].append({
            'period': _period_label(period, granularity),
            'uploads': int(uploads or 0),
        })

    top_performing_schools = uploads_per_school[:10]

    return {
        'filters': {
            'region': region,
            'school_id': school_id,
            'start_date': start_date,
            'end_date': end_date,
            'granularity': granularity,
        },
        'school_options': [
            {
                'school_id': school_id_value,
                'school_name': school_name,
                'region': school_region,
                'district': district,
            }
            for school_id_value, school_name, school_region, district in school_options
        ],
        'uploads_per_school': uploads_per_school,
        'school_contribution_by_region': list(region_groups.values()),
        'activity_timeline': list(timeline_map.values()),
        'top_performing_schools': top_performing_schools,
        'average_upload_frequency': average_frequency[:10],
    }


@app.get('/api/admin/analytics/regions')
def admin_regions(user: User = Depends(require_admin), db: Session = Depends(get_db)):
    result = []
    for region in REGIONS:
        sc = db.query(School).filter_by(region=region).count()
        vc = db.query(Video).filter_by(region=region).count()
        ap = db.query(Video).filter_by(region=region, verified_status='approved').count()
        st = db.query(func.sum(School.deaf_students)).filter(School.region == region).scalar() or 0
        result.append({
            'region':   region,
            'schools':  sc,
            'videos':   vc,
            'total':    vc,   # alias: Flutter bar chart uses 'total'
            'approved': ap,
            'students': int(st),
        })
    return {'regions': result}


@app.get('/api/admin/analytics/map-data')
def admin_map_data(user: User = Depends(require_admin), db: Session = Depends(get_db)):
    schools = db.query(School).all()
    h_srvs  = db.query(HealthService).all()
    videos = db.query(Video)\
        .filter(Video.uploader_latitude.isnot(None), Video.uploader_longitude.isnot(None))\
        .order_by(Video.upload_timestamp.desc())\
        .all()

    school_name_by_id = {s.id: s.name for s in schools}

    school_pins = [{
        'id':           s.id,
        'name':         s.name,
        'region':       s.region,
        'district':     s.district,
        'address':      s.address,
        'latitude':     s.latitude,
        'longitude':    s.longitude,
        'school_type':  s.school_type,
        'deaf_students': s.deaf_students,
        'total_uploads': db.query(Video).filter_by(school_id=s.id).count(),
        'verified':     s.verified,
    } for s in schools]

    health_pins = [{
        'id':           h.id,
        'name':         h.name,
        'facility_type': h.facility_type,
        'region':       h.region,
        'district':     h.district,
        'latitude':     h.latitude,
        'longitude':    h.longitude,
        'deaf_friendly': h.deaf_friendly,
    } for h in h_srvs if h.latitude and h.longitude]

    video_source_pins = [{
        'video_id':         v.id,
        'gloss_label':      v.gloss_label,
        'school_id':        v.school_id,
        'school_name':      school_name_by_id.get(v.school_id) or 'Individual',
        'region':           v.region,
        'district':         v.district,
        'latitude':         v.uploader_latitude,
        'longitude':        v.uploader_longitude,
        'geo_source':       v.geo_source or 'unknown',
        'verified_status':  v.verified_status,
        'upload_date':      str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
    } for v in videos]

    return {
        'schools': school_pins,
        'health':  health_pins,      # Flutter uses 'health' key
        'health_facilities': health_pins,  # keep legacy key too
        'video_sources': video_source_pins,
    }


@app.get('/api/admin/schools')
def admin_schools(user: User = Depends(require_admin), db: Session = Depends(get_db)):
    schools = db.query(School).order_by(School.region, School.name).all()
    return {'schools': [{
        'id':           s.id,
        'name':         s.name,
        'region':       s.region,
        'district':     s.district,
        'school_type':  s.school_type,
        'deaf_students': s.deaf_students,
        'uploads':      db.query(Video).filter_by(school_id=s.id).count(),
        'verified':     s.verified,
        'created_at':   str(s.created_at)[:10] if s.created_at else '',
        'latitude':     s.latitude,
        'longitude':    s.longitude,
    } for s in schools], 'total': len(schools)}


@app.get('/api/admin/videos')
def admin_videos(
    status:   str = Query(''),
    region:   str = Query(''),
    page:     int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    user: User = Depends(require_admin),
    db:   Session = Depends(get_db),
):
    q = db.query(Video)
    if status: q = q.filter(Video.verified_status == status)
    if region: q = q.filter(Video.region == region)
    total  = q.count()
    videos = q.order_by(Video.upload_timestamp.desc()) \
               .offset((page-1)*per_page).limit(per_page).all()

    def _row(v: Video):
        school = db.get(School, v.school_id) if v.school_id else None
        playback_url = _to_browser_playable_video_url(v.file_path)
        return {
            'video_id':       v.id,
            'gloss_label':    v.gloss_label,
            'sign_category':  v.sign_category,
            'language':       v.language_variant,
            'region':         v.region,
            'district':       v.district,
            'file_path':      v.file_path,
            'video_url':      playback_url,
            'playback_url':   playback_url,
            'file_size_kb':   v.file_size_kb,
            'verified_status': v.verified_status,
            'upload_date':    str(v.upload_timestamp)[:10] if v.upload_timestamp else '',
            'school_name':    school.name if school else 'Individual',
        }

    return {'videos': [_row(v) for v in videos], 'total': total}


# ══════════════════════════════════════════════════════════════════════════════
#  HEALTH SERVICES CRUD
# ══════════════════════════════════════════════════════════════════════════════

@app.get('/api/health-services')
def list_health_services(
    district: str = Query(''),
    region:   str = Query(''),
    user: User = Depends(get_current_user),
    db:   Session = Depends(get_db),
):
    q = db.query(HealthService)
    if district: q = q.filter(HealthService.district.ilike(f'%{district}%'))
    if region:   q = q.filter(HealthService.region.ilike(f'%{region}%'))
    return {'facilities': [{
        'id': h.id, 'name': h.name, 'facility_type': h.facility_type,
        'district': h.district, 'region': h.region,
        'latitude': h.latitude, 'longitude': h.longitude,
        'deaf_friendly': h.deaf_friendly, 'services': h.services_available,
    } for h in q.all()]}


@app.post('/api/health-services', status_code=201)
def add_health_service(
    data: dict,
    user: User = Depends(require_admin),
    db:   Session = Depends(get_db),
):
    h = HealthService(
        name=data.get('name', ''), facility_type=data.get('type', ''),
        district=data.get('district', ''), region=data.get('region', ''),
        latitude=data.get('latitude'), longitude=data.get('longitude'),
        services_available=data.get('services', ''),
        deaf_friendly=bool(data.get('deaf_friendly', False)),
    )
    db.add(h); db.commit()
    return {'message': 'Added', 'id': h.id}

@app.post('/api/admin/fix-video-urls')
def fix_video_urls(
    user: User = Depends(require_admin),
    db:   Session = Depends(get_db),
):
    """Fix Cloudinary video URLs by adding browser-playable transformations."""
    fixed_count = 0
    videos = db.query(Video).all()
    for video in videos:
        updated = False
        for field in ('file_path', 'converted_video_url'):
            current_url = getattr(video, field) or ''
            if current_url.startswith('http://') or current_url.startswith('https://'):
                transformed = _to_browser_playable_video_url(current_url)
                if transformed and transformed != current_url:
                    setattr(video, field, transformed)
                    updated = True
                    fixed_count += 1
        if updated:
            video.conversion_status = 'completed'
            video.converted = True
    db.commit()
    return {'message': f'Fixed {fixed_count} video URLs', 'fixed_count': fixed_count}


@app.post('/api/admin/relink-missing-videos-from-cloudinary')
def relink_missing_videos_from_cloudinary(
    dry_run: bool = Query(True),
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Relink missing local video paths to Cloudinary URLs using timestamp/size matching."""
    try:
        result = _relink_missing_videos_from_cloudinary(db, dry_run=dry_run)
        mode = 'previewed' if dry_run else 'updated'
        result['message'] = f"Cloudinary relink {mode}: {len(result.get('matches', []))} candidate(s)"
        return result
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f'Cloudinary relink failed: {exc}')


@app.post('/api/admin/videos/{video_id}/link-cloudinary')
def link_video_to_cloudinary(
    video_id: int,
    data: dict,
    user: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Manually link a video record to a Cloudinary asset using public_id or URL."""
    video = db.get(Video, video_id)
    if not video:
        raise HTTPException(status_code=404, detail='Video not found')

    cloudinary_url = (data.get('cloudinary_url') or '').strip()
    public_id = (data.get('public_id') or '').strip()

    if cloudinary_url:
        resolved = _to_browser_playable_video_url(cloudinary_url)
    elif public_id:
        try:
            cloudinary.api.resource(public_id, resource_type='video', type='upload')
        except Exception:
            raise HTTPException(status_code=400, detail='Cloudinary public_id not found')
        resolved = _cloudinary_delivery_mp4_url(public_id)
    else:
        raise HTTPException(status_code=400, detail='Provide cloudinary_url or public_id')

    if not resolved:
        raise HTTPException(status_code=400, detail='Could not build a playable Cloudinary URL')

    video.file_path = resolved
    video.converted_video_url = resolved
    video.converted = True
    video.conversion_status = 'completed'
    db.commit()

    return {
        'message': 'Video linked to Cloudinary successfully',
        'video_id': video.id,
        'playback_url': resolved,
    }


#  ENTRY POINT
if __name__ == '__main__':
    import uvicorn
    uvicorn.run('main:app', host='0.0.0.0', port=5000, reload=True)
