from __future__ import annotations

import argparse
import asyncio
import os
import sys
from pathlib import Path

from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from app.config import settings
from app.guest_identity_cleanup import cleanup_upgraded_guest_identities


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="清理已升级邮箱账号仍残留的 guest identity。默认 dry-run，不会写库。",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="实际执行删除；默认仅输出候选项。",
    )
    parser.add_argument(
        "--database-url",
        default="",
        help="可选覆盖数据库连接串；默认使用 settings.database_url。",
    )
    parser.add_argument(
        "--preview-limit",
        type=int,
        default=20,
        help="最多打印多少条候选项预览，默认 20。",
    )
    return parser


async def _run(args: argparse.Namespace) -> int:
    database_url = str(args.database_url).strip() or str(settings.database_url).strip()
    if database_url == "":
        print("database_url is required", file=sys.stderr)
        return 2

    engine = create_async_engine(database_url)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with session_factory() as db:
            report = await cleanup_upgraded_guest_identities(db, dry_run=not bool(args.apply))
    finally:
        await engine.dispose()

    mode = "APPLY" if args.apply else "DRY-RUN"
    print("[guest_identity_cleanup] mode=%s affected_users=%d candidate_identities=%d removed_identities=%d" % (
        mode,
        report.affected_users,
        len(report.candidates),
        report.removed_identities,
    ))

    preview_limit = max(0, int(args.preview_limit))
    if preview_limit > 0:
        for candidate in report.candidates[:preview_limit]:
            print("user_id=%s device_id=%s identity_id=%s" % (
                candidate.user_id,
                candidate.device_id,
                candidate.identity_id,
            ))
        remaining = len(report.candidates) - min(preview_limit, len(report.candidates))
        if remaining > 0:
            print("... %d more candidate identities omitted" % remaining)

    if not args.apply:
        print("dry-run only; rerun with --apply to delete these guest identities")
    return 0


def main() -> int:
    parser = _build_parser()
    args = parser.parse_args()
    return asyncio.run(_run(args))


if __name__ == "__main__":
    raise SystemExit(main())
