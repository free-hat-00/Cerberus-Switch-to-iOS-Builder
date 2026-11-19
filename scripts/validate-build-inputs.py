#!/usr/bin/env python3
"""Validate and extract a staged game tar, with a conservative disk-space budget.

No Nintendo keys or game data are needed to test this validation component.
"""
import argparse
import os
import shutil
import tarfile
from pathlib import Path, PurePosixPath

EXTENSIONS = {".nsp", ".xci", ".nsz", ".xcz"}

def validate_and_extract(archive: Path, output: Path, free_bytes: int | None = None, reserve_bytes: int = 10 * 1024**3) -> list[Path]:
    if not archive.is_file() or archive.stat().st_size == 0:
        raise ValueError("Missing or empty input archive")
    free = shutil.disk_usage(output.parent).free if free_bytes is None else free_bytes
    if free < 2 * archive.stat().st_size + reserve_bytes:
        raise ValueError("Insufficient disk: require at least twice archive size plus reserve")
    # Validate all headers before any extraction, including zero-length names and
    # links, which tarfile's default handling could otherwise accept.
    with tarfile.open(archive, "r:*") as tf:
        seen = set()
        total_size = 0
        headers = tf.getmembers()
        for member in headers:
            p = PurePosixPath(member.name)
            if (not member.name or "\\" in member.name or p.is_absolute()
                or ".." in p.parts or not (member.isfile() or member.isdir())
                or member.name.startswith("-")):
                raise ValueError("Unsafe tar entry")
            normalized = str(p)
            if normalized in seen and normalized not in (".",):
                raise ValueError("Duplicate tar entry")
            seen.add(normalized)
            if member.isfile():
                total_size += member.size
                if total_size > free - reserve_bytes:
                    raise ValueError("Extracted content would exceed disk budget")
        packages = [m for m in headers if m.isfile() and Path(m.name).suffix.lower() in EXTENSIONS]
        if not packages:
            raise ValueError("No supported game packages in archive")
        output.mkdir(parents=True, exist_ok=True)
        tf.extractall(output, filter="data")
    extracted = [output / m.name for m in packages]
    if not all(p.is_file() for p in extracted):
        raise ValueError("Package extraction failed")
    return extracted

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("archive", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--free-bytes", type=int, help="For controlled CI tests only")
    ap.add_argument("--reserve-bytes", type=int, default=10 * 1024**3)
    args = ap.parse_args()
    if args.reserve_bytes < 0 or (args.free_bytes is not None and args.free_bytes < 0):
        ap.error("Byte budgets must be nonnegative")
    try:
        packages = validate_and_extract(args.archive, args.output, args.free_bytes, args.reserve_bytes)
    except (ValueError, tarfile.TarError, OSError) as e:
        ap.exit(1, f"INVALID: {e}\n")
    print(f"PASS: validated and extracted {len(packages)} supported package(s)")

if __name__ == "__main__":
    main()
