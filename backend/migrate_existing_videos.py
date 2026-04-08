"""One-time backfill migration for legacy videos.

Usage:
    python migrate_existing_videos.py --workers 4
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import logging
import os
import shutil
import tempfile
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Iterable, Optional
from urllib.request import urlopen

import main
from sqlalchemy.orm import Session

LOG = logging.getLogger("video_backfill")


def configure_logging(verbose: bool = False) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(level=level, format="%(asctime)s %(levelname)s %(message)s")


def normalize_status(value: Optional[str]) -> str:
    status_value = (value or "").strip().lower()
    if status_value == "converted":
        return "completed"
    if status_value in {"pending", "processing", "completed", "failed"}:
        return status_value
    return "pending"


def probe_video(path: Path) -> dict:
    ffprobe = main._resolve_ffmpeg_binary("ffprobe")
    result = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-print_format",
            "json",
            "-show_streams",
            "-show_format",
            str(path),
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError((result.stderr or result.stdout or "ffprobe failed").strip())

    return json.loads(result.stdout or "{}")


def is_browser_ready(path: Path) -> bool:
    try:
        payload = probe_video(path)
    except Exception:
        return False

    streams = payload.get("streams") or []
    has_video = False
    has_h264 = False
    has_aac = False
    for stream in streams:
        codec_type = (stream or {}).get("codec_type")
        codec_name = (stream or {}).get("codec_name")
        if codec_type == "video":
            has_video = True
            has_h264 = codec_name == "h264"
        if codec_type == "audio":
            has_aac = codec_name == "aac"
    return has_video and has_h264 and has_aac


def source_to_temp(source: str, target_dir: Path) -> Path:
    target_dir.mkdir(parents=True, exist_ok=True)
    suffix = Path(source).suffix or ".video"
    with tempfile.NamedTemporaryFile(mode="wb", suffix=suffix, dir=target_dir, delete=False) as temp_file:
        if source.startswith(("http://", "https://")):
            with urlopen(source) as response:
                shutil.copyfileobj(response, temp_file)
        else:
            source_path = Path(source)
            if not source_path.exists():
                raise FileNotFoundError(source)
            with source_path.open("rb") as input_file:
                shutil.copyfileobj(input_file, temp_file)
        return Path(temp_file.name)


def backup_original(video_id: int, source: str, source_name: str) -> Path:
    backup_dir = main.VIDEO_ORIGINAL_DIR
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_name = f"{video_id}_{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}_{Path(source_name).name}"
    backup_path = backup_dir / backup_name
    if source.startswith(("http://", "https://")):
        with urlopen(source) as response, backup_path.open("wb") as target_file:
            shutil.copyfileobj(response, target_file)
    else:
        source_path = Path(source)
        if not source_path.exists():
            raise FileNotFoundError(source)
        shutil.copy2(source_path, backup_path)
    return backup_path


def needs_conversion(video: main.Video) -> bool:
    status = normalize_status(video.conversion_status)
    if video.converted and status == "completed" and video.converted_video_url:
        converted_path = Path(video.converted_video_url)
        if converted_path.exists() and is_browser_ready(converted_path):
            return False

    source = (video.file_path or "").strip()
    if not source:
        return True
    if source.startswith(("http://", "https://")):
        return True

    source_path = Path(source)
    if not source_path.exists():
        return True
    if source_path.suffix.lower() != ".mp4":
        return True
    return not is_browser_ready(source_path)


def convert_single(video_id: int) -> tuple[int, bool, str]:
    db: Session = main.SessionLocal()
    try:
        video = db.get(main.Video, video_id)
        if not video:
            return video_id, False, "not found"

        if not needs_conversion(video):
            video.converted = True
            video.conversion_status = "completed"
            if not video.converted_video_url:
                video.converted_video_url = video.file_path
            db.commit()
            return video_id, True, "already playable"

        video.conversion_status = "processing"
        db.commit()

        source = (video.file_path or "").strip()
        if not source:
            raise RuntimeError("missing file_path")

        original_name = Path(source).name or f"video_{video.id}"
        backup_original(video.id, source, original_name)

        temp_input = source_to_temp(source, main.VIDEO_RAW_DIR)
        converted_name = f"{datetime.utcnow().strftime('%Y%m%d%H%M%S%f')}_{video.id}.mp4"
        converted_path = main.VIDEO_CONVERTED_DIR / converted_name

        main._convert_to_browser_mp4(temp_input, converted_path)
        if temp_input.exists():
            temp_input.unlink(missing_ok=True)

        original_format = video.original_format or Path(original_name).suffix.lower().lstrip(".") or "unknown"
        video.file_path = str(converted_path)
        video.converted_video_url = str(converted_path)
        video.converted = True
        video.original_format = original_format
        video.conversion_status = "completed"
        video.file_size_kb = round(converted_path.stat().st_size / 1024, 1)
        db.commit()
        return video_id, True, "converted"
    except Exception as exc:
        db.rollback()
        video = db.get(main.Video, video_id)
        if video:
            video.conversion_status = "failed"
            db.commit()
        return video_id, False, f"failed: {exc}"
    finally:
        db.close()


def batch(videos: Iterable[main.Video], workers: int) -> None:
    video_ids = [video.id for video in videos]
    if not video_ids:
        LOG.info("No videos need conversion.")
        return

    LOG.info("Starting backfill for %s videos with %s workers", len(video_ids), workers)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        for video_id, ok, message in executor.map(convert_single, video_ids):
            if ok:
                LOG.info("Video %s: %s", video_id, message)
            else:
                LOG.error("Video %s: %s", video_id, message)


def main_entry() -> int:
    parser = argparse.ArgumentParser(description="Backfill legacy videos to browser-playable MP4.")
    parser.add_argument("--workers", type=int, default=2, help="Concurrent conversion workers.")
    parser.add_argument("--limit", type=int, default=0, help="Optional limit for testing.")
    parser.add_argument("--verbose", action="store_true", help="Enable debug logging.")
    args = parser.parse_args()

    configure_logging(args.verbose)

    db: Session = main.SessionLocal()
    try:
        query = db.query(main.Video).order_by(main.Video.upload_timestamp.asc())
        if args.limit and args.limit > 0:
            query = query.limit(args.limit)
        videos = query.all()
        target_videos = [video for video in videos if needs_conversion(video)]
        LOG.info("Found %s videos requiring conversion.", len(target_videos))
    finally:
        db.close()

    batch(target_videos, max(1, args.workers))
    return 0


if __name__ == "__main__":
    raise SystemExit(main_entry())
