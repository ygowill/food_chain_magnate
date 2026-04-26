from __future__ import annotations

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.backfill_match_artifacts import BackfillOptions, ExportJob, backfill_matches
from app.config import settings
from app.models import Match, MatchArtifact, MatchReplay


PNG_BYTES = b"\x89PNG\r\n\x1a\nbackfill-test"


@pytest.mark.asyncio
async def test_backfill_matches_exports_local_replay_artifacts(db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        match = Match(room_code="bf01", status="completed", player_count=2)
        db_session.add(match)
        await db_session.flush()
        replay_filename = f"{match.match_id}.json"
        (tmp_path / replay_filename).write_text('{"schema_version":3,"commands":[]}', encoding="utf-8")
        db_session.add(MatchReplay(
            match_id=match.match_id,
            storage_uri=f"local_file://{replay_filename}",
            checksum="replay-checksum",
            size_bytes=34,
        ))
        await db_session.commit()

        def fake_exporter(job: ExportJob, _options: BackfillOptions):
            job.output_dir.mkdir(parents=True, exist_ok=True)
            snapshot_dir = job.output_dir / "map_snapshots"
            snapshot_dir.mkdir(parents=True, exist_ok=True)
            (job.output_dir / "latest_autosave.json").write_text('{"round":1}', encoding="utf-8")
            (snapshot_dir / "round_0001_round_end.png").write_bytes(PNG_BYTES)
            return {
                "ok": True,
                "latest_save": {
                    "filename": "latest_autosave.json",
                    "snapshot_kind": "round_end",
                    "round_number": 1,
                    "state_hash": "state-1",
                },
                "map_snapshots": [
                    {
                        "filename": "round_0001_round_end.png",
                        "snapshot_kind": "round_end",
                        "round_number": 1,
                        "state_hash": "state-1",
                    }
                ],
            }

        summary = await backfill_matches(db_session, BackfillOptions(), exporter=fake_exporter)

        assert summary.scanned == 1
        assert summary.backfilled == 1
        assert summary.artifacts == 2
        rows = (await db_session.execute(
            select(MatchArtifact).where(MatchArtifact.match_id == match.match_id)
        )).scalars().all()
        assert {row.artifact_type for row in rows} == {"autosave_latest", "map_snapshot"}
        latest = next(row for row in rows if row.artifact_type == "autosave_latest")
        snapshot = next(row for row in rows if row.artifact_type == "map_snapshot")
        assert latest.room_code == "BF01"
        assert latest.storage_uri == "local_artifact://rooms/BF01/latest_autosave.json"
        assert snapshot.storage_uri == "local_artifact://rooms/BF01/map_snapshots/round_0001_round_end.png"
        assert snapshot.mime_type == "image/png"
        assert snapshot.size_bytes == len(PNG_BYTES)
    finally:
        settings.replay_storage_dir = old_replay_storage_dir


@pytest.mark.asyncio
async def test_backfill_matches_skips_existing_artifacts_without_force(db_session: AsyncSession, tmp_path):
    old_replay_storage_dir = settings.replay_storage_dir
    settings.replay_storage_dir = str(tmp_path)
    try:
        match = Match(room_code="EXISTS1", status="completed", player_count=2)
        db_session.add(match)
        await db_session.flush()
        replay_filename = f"{match.match_id}.json"
        (tmp_path / replay_filename).write_text('{"schema_version":3,"commands":[]}', encoding="utf-8")
        db_session.add(MatchReplay(
            match_id=match.match_id,
            storage_uri=f"local_file://{replay_filename}",
            checksum="replay-checksum",
            size_bytes=34,
        ))
        db_session.add(MatchArtifact(
            match_id=match.match_id,
            room_code="EXISTS1",
            artifact_type="autosave_latest",
            snapshot_kind="round_end",
            round_number=1,
            storage_uri="local_artifact://rooms/EXISTS1/latest_autosave.json",
            mime_type="application/json",
            checksum="old",
            size_bytes=2,
        ))
        await db_session.commit()

        def should_not_export(_job: ExportJob, _options: BackfillOptions):
            raise AssertionError("exporter should not run when artifacts already exist")

        summary = await backfill_matches(db_session, BackfillOptions(), exporter=should_not_export)

        assert summary.scanned == 1
        assert summary.backfilled == 0
        assert summary.skipped_existing == 1
    finally:
        settings.replay_storage_dir = old_replay_storage_dir
