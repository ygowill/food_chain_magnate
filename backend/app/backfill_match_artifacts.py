from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import async_session, init_db
from app.models import Match, MatchArtifact, MatchReplay
from app.replay_storage import (
    build_local_artifact_uri,
    get_local_artifact_path,
    get_local_replay_path,
    parse_local_artifact_relative_path,
    parse_local_replay_filename,
)

ARTIFACT_TYPE_LATEST_AUTOSAVE = "autosave_latest"
ARTIFACT_TYPE_MAP_SNAPSHOT = "map_snapshot"
SNAPSHOT_KIND_ROUND_END = "round_end"
SNAPSHOT_KIND_GAME_OVER = "game_over"


@dataclass(frozen=True)
class BackfillOptions:
    match_ids: tuple[str, ...] = ()
    limit: int | None = None
    dry_run: bool = False
    force: bool = False
    godot_bin: str = "godot"
    project_root: Path = field(default_factory=lambda: Path(__file__).resolve().parents[2])
    json_output: bool = False


@dataclass(frozen=True)
class ExportJob:
    match_id: str
    room_code: str
    replay_path: Path
    output_dir: Path


@dataclass
class BackfillReport:
    match_id: str
    room_code: str
    status: str
    detail: str = ""
    artifacts: int = 0

    def to_dict(self) -> dict[str, Any]:
        return {
            "match_id": self.match_id,
            "room_code": self.room_code,
            "status": self.status,
            "detail": self.detail,
            "artifacts": self.artifacts,
        }


@dataclass
class BackfillSummary:
    scanned: int = 0
    backfilled: int = 0
    dry_run_ready: int = 0
    artifacts: int = 0
    skipped_existing: int = 0
    skipped_missing_replay: int = 0
    skipped_nonlocal_replay: int = 0
    failed: int = 0
    reports: list[BackfillReport] = field(default_factory=list)

    def add(self, report: BackfillReport) -> None:
        self.reports.append(report)
        if report.status == "backfilled":
            self.backfilled += 1
            self.artifacts += report.artifacts
        elif report.status == "dry_run_ready":
            self.dry_run_ready += 1
        elif report.status == "skipped_existing":
            self.skipped_existing += 1
        elif report.status == "skipped_missing_replay":
            self.skipped_missing_replay += 1
        elif report.status == "skipped_nonlocal_replay":
            self.skipped_nonlocal_replay += 1
        elif report.status == "failed":
            self.failed += 1

    def to_dict(self) -> dict[str, Any]:
        return {
            "scanned": self.scanned,
            "backfilled": self.backfilled,
            "dry_run_ready": self.dry_run_ready,
            "artifacts": self.artifacts,
            "skipped_existing": self.skipped_existing,
            "skipped_missing_replay": self.skipped_missing_replay,
            "skipped_nonlocal_replay": self.skipped_nonlocal_replay,
            "failed": self.failed,
            "reports": [item.to_dict() for item in self.reports],
        }


Exporter = Callable[[ExportJob, BackfillOptions], dict[str, Any]]


def normalize_room_code_for_backfill(match: Match) -> str:
    raw = str(match.room_code or match.match_id or "").strip().upper()
    safe = "".join(ch for ch in raw if ch.isalnum() or ch in ("_", "-"))
    if safe:
        return safe
    return str(match.match_id).strip()


async def backfill_matches(
    db: AsyncSession,
    options: BackfillOptions,
    exporter: Exporter | None = None,
) -> BackfillSummary:
    exporter = exporter or run_godot_export
    rows = await _load_match_replay_rows(db, options)
    summary = BackfillSummary(scanned=len(rows))

    for match, replay in rows:
        room_code = normalize_room_code_for_backfill(match)
        existing = await _load_existing_artifacts(db, str(match.match_id), room_code)
        if existing and not options.force:
            summary.add(BackfillReport(
                match_id=str(match.match_id),
                room_code=room_code,
                status="skipped_existing",
                detail=f"{len(existing)} artifact(s) already exist",
            ))
            continue

        filename = parse_local_replay_filename(str(replay.storage_uri))
        if filename is None:
            summary.add(BackfillReport(
                match_id=str(match.match_id),
                room_code=room_code,
                status="skipped_nonlocal_replay",
                detail=str(replay.storage_uri),
            ))
            continue

        replay_path = get_local_replay_path(filename)
        if not replay_path.exists() or not replay_path.is_file():
            summary.add(BackfillReport(
                match_id=str(match.match_id),
                room_code=room_code,
                status="skipped_missing_replay",
                detail=str(replay_path),
            ))
            continue

        output_dir = get_local_artifact_path(f"rooms/{room_code}")
        job = ExportJob(
            match_id=str(match.match_id),
            room_code=room_code,
            replay_path=replay_path,
            output_dir=output_dir,
        )
        if options.dry_run:
            summary.add(BackfillReport(
                match_id=job.match_id,
                room_code=room_code,
                status="dry_run_ready",
                detail=f"would export to {output_dir}",
            ))
            continue

        try:
            manifest = exporter(job, options)
            artifact_count = await persist_manifest_artifacts(db, match, room_code, manifest, force=options.force)
            await db.commit()
            summary.add(BackfillReport(
                match_id=job.match_id,
                room_code=room_code,
                status="backfilled",
                detail=f"{artifact_count} artifact(s)",
                artifacts=artifact_count,
            ))
        except Exception as exc:
            await db.rollback()
            summary.add(BackfillReport(
                match_id=job.match_id,
                room_code=room_code,
                status="failed",
                detail=str(exc),
            ))

    return summary


async def persist_manifest_artifacts(
    db: AsyncSession,
    match: Match,
    room_code: str,
    manifest: dict[str, Any],
    *,
    force: bool = False,
) -> int:
    if bool(manifest.get("ok")) is not True:
        raise ValueError("manifest is not ok")

    existing = await _load_existing_artifacts(db, str(match.match_id), room_code)
    if existing:
        if not force:
            raise ValueError("artifacts already exist; pass force to replace")
        await _delete_artifacts(db, existing, unlink_files=False)

    rows: list[MatchArtifact] = []
    latest = manifest.get("latest_save")
    if not isinstance(latest, dict):
        raise ValueError("manifest latest_save missing")
    latest_filename = _require_safe_filename(latest.get("filename"), "latest_save.filename")
    latest_path = get_local_artifact_path(f"rooms/{room_code}/{latest_filename}")
    latest_info = _inspect_artifact_file(latest_path, expected_prefix=None)
    rows.append(MatchArtifact(
        match_id=str(match.match_id),
        room_code=room_code,
        artifact_type=ARTIFACT_TYPE_LATEST_AUTOSAVE,
        snapshot_kind=_normalize_snapshot_kind(latest.get("snapshot_kind")),
        round_number=max(0, _safe_int(latest.get("round_number"))),
        state_hash=_optional_str(latest.get("state_hash")),
        storage_uri=build_local_artifact_uri(f"rooms/{room_code}/{latest_filename}"),
        mime_type="application/json",
        checksum=latest_info["checksum"],
        size_bytes=latest_info["size_bytes"],
    ))

    snapshots = manifest.get("map_snapshots", [])
    if not isinstance(snapshots, list):
        raise ValueError("manifest map_snapshots must be a list")
    for index, item in enumerate(snapshots):
        if not isinstance(item, dict):
            raise ValueError(f"manifest map_snapshots[{index}] must be an object")
        filename = _require_safe_filename(item.get("filename"), f"map_snapshots[{index}].filename")
        path = get_local_artifact_path(f"rooms/{room_code}/map_snapshots/{filename}")
        info = _inspect_artifact_file(path, expected_prefix=b"\x89PNG\r\n\x1a\n")
        rows.append(MatchArtifact(
            match_id=str(match.match_id),
            room_code=room_code,
            artifact_type=ARTIFACT_TYPE_MAP_SNAPSHOT,
            snapshot_kind=_normalize_snapshot_kind(item.get("snapshot_kind")),
            round_number=max(0, _safe_int(item.get("round_number"))),
            state_hash=_optional_str(item.get("state_hash")),
            storage_uri=build_local_artifact_uri(f"rooms/{room_code}/map_snapshots/{filename}"),
            mime_type="image/png",
            checksum=info["checksum"],
            size_bytes=info["size_bytes"],
        ))

    db.add_all(rows)
    await db.flush()
    return len(rows)


def run_godot_export(job: ExportJob, options: BackfillOptions) -> dict[str, Any]:
    output_dir = job.output_dir.expanduser()
    output_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = output_dir / "manifest.json"
    try:
        manifest_path.unlink(missing_ok=True)
    except OSError:
        pass
    cmd = [
        options.godot_bin,
        "--headless",
        "--path",
        str(options.project_root),
        "--script",
        "res://tools/export_match_artifacts_from_replay.gd",
        "--",
        f"--replay-file={job.replay_path}",
        f"--output-dir={output_dir}",
        f"--match-id={job.match_id}",
        f"--room-code={job.room_code}",
    ]
    result = subprocess.run(
        cmd,
        cwd=options.project_root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(_format_command_failure(cmd, result))
    try:
        return json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"failed to read manifest {manifest_path}: {exc}") from exc


async def _load_match_replay_rows(db: AsyncSession, options: BackfillOptions) -> list[tuple[Match, MatchReplay]]:
    stmt = (
        select(Match, MatchReplay)
        .join(MatchReplay, MatchReplay.match_id == Match.match_id)
        .order_by(Match.created_at.asc())
    )
    if options.match_ids:
        stmt = stmt.where(Match.match_id.in_(options.match_ids))
    if options.limit is not None and options.limit > 0:
        stmt = stmt.limit(options.limit)
    result = await db.execute(stmt)
    return [(row[0], row[1]) for row in result.all()]


async def _load_existing_artifacts(db: AsyncSession, match_id: str, room_code: str | None = None) -> list[MatchArtifact]:
    owner_filter = MatchArtifact.match_id == match_id
    if room_code:
        owner_filter = or_(owner_filter, MatchArtifact.room_code == room_code)
    result = await db.execute(
        select(MatchArtifact).where(
            owner_filter,
            MatchArtifact.artifact_type.in_((ARTIFACT_TYPE_LATEST_AUTOSAVE, ARTIFACT_TYPE_MAP_SNAPSHOT)),
        )
    )
    return list(result.scalars().all())


async def _delete_artifacts(db: AsyncSession, artifacts: list[MatchArtifact], *, unlink_files: bool) -> None:
    for artifact in artifacts:
        if unlink_files:
            rel_path = parse_local_artifact_relative_path(str(artifact.storage_uri))
            if rel_path is not None:
                try:
                    get_local_artifact_path(rel_path).unlink(missing_ok=True)
                except OSError:
                    pass
        await db.delete(artifact)
    await db.flush()


def _inspect_artifact_file(path: Path, expected_prefix: bytes | None) -> dict[str, Any]:
    if not path.exists() or not path.is_file():
        raise ValueError(f"artifact file missing: {path}")
    digest = hashlib.sha256()
    size = 0
    first = b""
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            if not first:
                first = chunk[:16]
            size += len(chunk)
            digest.update(chunk)
    if expected_prefix is not None and not first.startswith(expected_prefix):
        raise ValueError(f"artifact file has unexpected format: {path}")
    return {"checksum": digest.hexdigest(), "size_bytes": size}


def _require_safe_filename(value: Any, field_name: str) -> str:
    filename = str(value or "").strip()
    if not filename:
        raise ValueError(f"{field_name} missing")
    if Path(filename).name != filename:
        raise ValueError(f"{field_name} must be a filename")
    if filename in (".", ".."):
        raise ValueError(f"{field_name} invalid")
    return filename


def _normalize_snapshot_kind(value: Any) -> str:
    kind = str(value or "").strip()
    if kind == SNAPSHOT_KIND_GAME_OVER:
        return SNAPSHOT_KIND_GAME_OVER
    return SNAPSHOT_KIND_ROUND_END


def _optional_str(value: Any) -> str | None:
    text = str(value or "").strip()
    return text or None


def _safe_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _format_command_failure(cmd: list[str], result: subprocess.CompletedProcess[str]) -> str:
    out = (result.stdout or "").strip()
    err = (result.stderr or "").strip()
    tail = "\n".join(part for part in (_tail(out), _tail(err)) if part)
    return "Godot export failed exit=%d cmd=%s%s" % (
        result.returncode,
        " ".join(cmd),
        f"\n{tail}" if tail else "",
    )


def _tail(text: str, lines: int = 40) -> str:
    if not text:
        return ""
    parts = text.splitlines()
    return "\n".join(parts[-lines:])


def parse_args(argv: list[str] | None = None) -> BackfillOptions:
    parser = argparse.ArgumentParser(description="Backfill server-side match autosaves and map snapshots from local replay archives.")
    parser.add_argument("--match-id", action="append", default=[], help="Only backfill a specific match id. Can be repeated.")
    parser.add_argument("--limit", type=int, default=None, help="Maximum number of replay rows to scan.")
    parser.add_argument("--dry-run", action="store_true", help="Report what would be backfilled without running Godot or writing DB rows.")
    parser.add_argument("--force", action="store_true", help="Replace existing match_artifacts rows for selected matches.")
    parser.add_argument("--godot-bin", default=os.environ.get("GODOT_BIN", "godot"), help="Godot executable to run.")
    parser.add_argument(
        "--project-root",
        default=str(Path(__file__).resolve().parents[2]),
        help="Godot project root. Defaults to the repository root.",
    )
    parser.add_argument("--json", action="store_true", dest="json_output", help="Print machine-readable JSON summary.")
    args = parser.parse_args(argv)
    options = BackfillOptions(
        match_ids=tuple(str(item).strip() for item in args.match_id if str(item).strip()),
        limit=args.limit,
        dry_run=bool(args.dry_run),
        force=bool(args.force),
        godot_bin=str(args.godot_bin),
        project_root=Path(str(args.project_root)).expanduser().resolve(),
        json_output=bool(args.json_output),
    )
    return options


def print_summary(summary: BackfillSummary) -> None:
    print(
        "Backfill scanned={scanned} backfilled={backfilled} dry_run_ready={dry_run_ready} "
        "artifacts={artifacts} skipped_existing={skipped_existing} skipped_missing_replay={skipped_missing_replay} "
        "skipped_nonlocal_replay={skipped_nonlocal_replay} failed={failed}".format(**summary.to_dict())
    )
    for report in summary.reports:
        suffix = f" - {report.detail}" if report.detail else ""
        print(f"{report.status} match={report.match_id} room={report.room_code} artifacts={report.artifacts}{suffix}")


async def main_async(argv: list[str] | None = None) -> int:
    options = parse_args(argv)
    await init_db()
    async with async_session() as db:
        summary = await backfill_matches(db, options)
    if options.json_output:
        print(json.dumps(summary.to_dict(), ensure_ascii=False, indent=2))
    else:
        print_summary(summary)
    return 1 if summary.failed else 0


def main() -> None:
    raise SystemExit(asyncio.run(main_async(sys.argv[1:])))


if __name__ == "__main__":
    main()
