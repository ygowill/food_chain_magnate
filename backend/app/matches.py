import json
from collections.abc import Callable

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, RedirectResponse
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user
from app.db import get_db
from app.models import Match, MatchParticipant, MatchReplay
from app.replay_storage import get_local_replay_path, parse_local_replay_filename

router = APIRouter(prefix="/v1/matches", tags=["matches"])


class PlayerStats(BaseModel):
    marketing_actions: int = 0
    billboard_placements: int = 0
    hired_employees: int = 0
    trained_employees: int = 0
    marketing_by_type: dict[str, int] = {}
    metrics: dict[str, int] = {}
    produced: dict[str, int] = {}
    sold: dict[str, int] = {}


class PlayerScore(BaseModel):
    cash: int = 0
    forfeited: bool = False
    restaurants: int = 0
    employees: list[str] = []
    milestones: list[str] = []
    inventory: dict[str, int] = {}
    marketing_campaigns: int = 0
    stats: PlayerStats = Field(default_factory=PlayerStats)


class GameSummary(BaseModel):
    modules: list[str] = []
    round_number: int = 0
    bank_total: int = 0
    bank_broke_count: int = 0
    bank_reserve_added: int = 0
    marketing_count: int = 0


class ParticipantInfo(BaseModel):
    user_id: str
    role: str
    seat_index: int | None
    result: str | None
    display_name: str | None = None
    restaurant_logo_id: int | None = None
    restaurant_logo_key: str | None = None
    score: PlayerScore | None


class MatchSummary(BaseModel):
    match_id: str
    room_code: str | None
    status: str
    player_count: int
    started_at: str | None
    ended_at: str | None
    duration_sec: int | None
    participants: list[ParticipantInfo]


class MatchDetail(MatchSummary):
    seed: str | None
    schema_version: str | None
    game_version: str | None
    final_hash: str | None
    summary: GameSummary | None
    has_replay: bool


class ReplayInfo(BaseModel):
    match_id: str
    storage_uri: str
    checksum: str | None
    size_bytes: int | None


RESTAURANT_LOGO_KEYS = [
    "restaurant_logo_fried_geese_donkey",
    "restaurant_logo_gluttony_inc_burgers",
    "restaurant_logo_golden_duck_diner",
    "restaurant_logo_santa_maria_pizza",
    "restaurant_logo_xango_blues_bar",
    "restaurant_logo_sixth_chain",
]

PRODUCT_KEY_ALIASES = {
    "coke": "soda",
    "cola": "soda",
}


def _safe_int(value: object) -> int:
    try:
        n = int(value)
    except (TypeError, ValueError):
        return 0
    return max(0, n)


def _canonicalize_product_key(value: str) -> str:
    normalized = value.strip().lower()
    return PRODUCT_KEY_ALIASES.get(normalized, normalized)


def _parse_count_map(value: object, normalize_key: Callable[[str], str] | None = None) -> dict[str, int]:
    if not isinstance(value, dict):
        return {}
    out: dict[str, int] = {}
    for k, v in value.items():
        c = _safe_int(v)
        if c <= 0:
            continue
        key = str(k)
        if normalize_key is not None:
            key = normalize_key(key)
        if not key:
            continue
        out[key] = out.get(key, 0) + c
    return out


def _logo_key_from_id(logo_id: int | None) -> str | None:
    if logo_id is None:
        return None
    if logo_id < 0 or logo_id >= len(RESTAURANT_LOGO_KEYS):
        return None
    return RESTAURANT_LOGO_KEYS[logo_id]


def _parse_participant_profile(raw: str | None) -> tuple[str | None, int | None, str | None]:
    if not raw:
        return None, None, None
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None, None, None
    if not isinstance(data, dict):
        return None, None, None

    sources: list[dict] = [data]
    for key in ("player_profile", "profile", "public_profile"):
        nested = data.get(key)
        if isinstance(nested, dict):
            sources.append(nested)

    display_name: str | None = None
    for src in sources:
        for key in ("display_name", "player_name", "nickname", "name"):
            value = src.get(key)
            if not isinstance(value, str):
                continue
            text = value.strip()
            if text:
                display_name = text
                break
        if display_name:
            break

    logo_id: int | None = None
    for src in sources:
        for key in ("restaurant_logo_id", "restaurantLogoId", "logo_id"):
            if key not in src:
                continue
            parsed = _safe_int(src.get(key))
            if parsed >= 0:
                logo_id = parsed
                break
        if logo_id is not None:
            break

    logo_key: str | None = None
    for src in sources:
        for key in ("restaurant_logo_key", "restaurant_logo_piece_id", "restaurantLogoKey", "logo_key"):
            value = src.get(key)
            if not isinstance(value, str):
                continue
            text = value.strip()
            if text:
                logo_key = text
                break
        if logo_key:
            break

    if not logo_key:
        logo_key = _logo_key_from_id(logo_id)

    return display_name, logo_id, logo_key


def _to_public_replay_uri(match_id: str, storage_uri: str) -> str:
    if parse_local_replay_filename(storage_uri) is not None:
        return f"/v1/matches/{match_id}/replay/download"
    return storage_uri


def _pick_int(sources: list[dict], keys: tuple[str, ...]) -> int:
    for src in sources:
        for key in keys:
            if key not in src:
                continue
            return _safe_int(src.get(key))
    return 0


def _pick_count_map(
    sources: list[dict],
    keys: tuple[str, ...],
    normalize_key: Callable[[str], str] | None = None,
) -> dict[str, int]:
    for src in sources:
        for key in keys:
            if key not in src:
                continue
            return _parse_count_map(src.get(key), normalize_key)
    return {}


def _collect_extra_metrics(stats_sources: list[dict], reserved_keys: set[str]) -> dict[str, int]:
    out: dict[str, int] = {}
    for src in stats_sources:
        for key, value in src.items():
            if key in reserved_keys:
                continue
            if isinstance(value, (int, float, str)):
                n = _safe_int(value)
                if n > 0 and key not in out:
                    out[str(key)] = n
                continue
            if not isinstance(value, dict):
                continue
            for sub_key, sub_value in value.items():
                n2 = _safe_int(sub_value)
                if n2 <= 0:
                    continue
                flat_key = f"{key}:{sub_key}"
                if flat_key not in out:
                    out[flat_key] = n2
    return out


def _parse_player_stats(data: dict, marketing_campaigns: int) -> PlayerStats:
    stats_sources: list[dict] = []
    stats_raw = data.get("stats")
    if isinstance(stats_raw, dict):
        stats_sources.append(stats_raw)
    statistics_raw = data.get("statistics")
    if isinstance(statistics_raw, dict):
        stats_sources.append(statistics_raw)
    sources: list[dict] = stats_sources + [data]

    marketing_actions = _pick_int(sources, (
        "marketing_actions", "marketingActions", "marketing_count", "marketingCount",
    ))
    billboard_placements = _pick_int(sources, (
        "billboard_placements", "billboardPlacements", "billboard_count", "billboardCount",
    ))
    hired_employees = _pick_int(sources, (
        "hired_employees", "hiredEmployees", "recruit_count", "recruitCount",
    ))
    trained_employees = _pick_int(sources, (
        "trained_employees", "trainedEmployees", "train_count", "trainCount",
    ))
    house_built = _pick_int(sources, (
        "house_built", "houses_built", "house_build_count", "build_house_count",
        "place_house_count", "house_placement_count",
    ))
    garden_built = _pick_int(sources, (
        "garden_built", "gardens_built", "build_garden_count", "place_garden_count",
    ))
    restaurant_built = _pick_int(sources, (
        "restaurant_built", "restaurants_built", "place_restaurant_count",
        "new_restaurant_count",
    ))
    restaurant_moved = _pick_int(sources, (
        "restaurant_moved", "restaurants_moved", "move_restaurant_count",
    ))
    procurement_actions = _pick_int(sources, (
        "procurement_actions", "procurement_count", "procure_count",
    ))
    lobbyists_actions = _pick_int(sources, (
        "lobbyists_actions", "lobbyists_count", "lobbyist_actions",
    ))

    produced = _pick_count_map(sources, (
        "produced", "produced_products", "producedProducts", "production_counts", "productionCounts",
    ), _canonicalize_product_key)
    sold = _pick_count_map(sources, (
        "sold", "sold_products", "soldProducts", "sales_counts", "salesCounts",
    ), _canonicalize_product_key)
    marketing_by_type = _pick_count_map(sources, (
        "marketing_by_type", "marketingByType", "marketing_type_counts", "marketingTypeCounts",
    ))

    if billboard_placements == 0:
        billboard_placements = _safe_int(marketing_by_type.get("billboard", 0))

    if marketing_actions == 0:
        marketing_actions = marketing_campaigns

    metrics: dict[str, int] = {}
    if house_built > 0:
        metrics["house_built"] = house_built
    if garden_built > 0:
        metrics["garden_built"] = garden_built
    if restaurant_built > 0:
        metrics["restaurant_built"] = restaurant_built
    if restaurant_moved > 0:
        metrics["restaurant_moved"] = restaurant_moved
    if procurement_actions > 0:
        metrics["procurement_actions"] = procurement_actions
    if lobbyists_actions > 0:
        metrics["lobbyists_actions"] = lobbyists_actions

    reserved_keys = {
        "marketing_actions", "marketingActions", "marketing_count", "marketingCount",
        "billboard_placements", "billboardPlacements", "billboard_count", "billboardCount",
        "hired_employees", "hiredEmployees", "recruit_count", "recruitCount",
        "trained_employees", "trainedEmployees", "train_count", "trainCount",
        "house_built", "houses_built", "house_build_count", "build_house_count",
        "place_house_count", "house_placement_count",
        "garden_built", "gardens_built", "build_garden_count", "place_garden_count",
        "restaurant_built", "restaurants_built", "place_restaurant_count", "new_restaurant_count",
        "restaurant_moved", "restaurants_moved", "move_restaurant_count",
        "procurement_actions", "procurement_count", "procure_count",
        "lobbyists_actions", "lobbyists_count", "lobbyist_actions",
        "produced", "produced_products", "producedProducts", "production_counts", "productionCounts",
        "sold", "sold_products", "soldProducts", "sales_counts", "salesCounts",
        "marketing_by_type", "marketingByType", "marketing_type_counts", "marketingTypeCounts",
    }
    extra_metrics = _collect_extra_metrics(stats_sources, reserved_keys)
    for key, value in extra_metrics.items():
        if key not in metrics:
            metrics[key] = value

    return PlayerStats(
        marketing_actions=marketing_actions,
        billboard_placements=billboard_placements,
        hired_employees=hired_employees,
        trained_employees=trained_employees,
        marketing_by_type=marketing_by_type,
        metrics=metrics,
        produced=produced,
        sold=sold,
    )


def _parse_score(raw: str | None) -> PlayerScore | None:
    if not raw:
        return None
    try:
        d = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None

    # employees: 合并 employees + reserve_employees + busy_marketers
    emp_list: list[str] = []
    for key in ("employees", "reserve_employees", "busy_marketers"):
        val = d.get(key, [])
        if isinstance(val, list):
            emp_list.extend(str(e) for e in val)

    # milestones: 保留完整 ID 列表
    ms_raw = d.get("milestones", [])
    ms_list = [str(m) for m in ms_raw] if isinstance(ms_raw, list) else []

    # restaurants
    rest_raw = d.get("restaurants", [])
    rest_count = len(rest_raw) if isinstance(rest_raw, list) else int(rest_raw or 0)

    # inventory
    inv_raw = d.get("inventory", {})
    inventory = {str(k): int(v) for k, v in inv_raw.items()} if isinstance(inv_raw, dict) else {}

    # busy marketers count
    busy_raw = d.get("busy_marketers", [])
    marketing = len(busy_raw) if isinstance(busy_raw, list) else 0
    stats = _parse_player_stats(d, marketing)

    return PlayerScore(
        cash=_safe_int(d.get("cash", 0)),
        forfeited=bool(d.get("forfeited", False)),
        restaurants=rest_count,
        employees=emp_list,
        milestones=ms_list,
        inventory=inventory,
        marketing_campaigns=marketing,
        stats=stats,
    )


def _parse_summary(raw: str | None) -> GameSummary | None:
    if not raw:
        return None
    try:
        d = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None
    bank = d.get("bank", {}) if isinstance(d.get("bank"), dict) else {}
    modules = d.get("modules", [])
    if not isinstance(modules, list):
        modules = []
    mk_raw = d.get("marketing_instances", [])
    mk_count = len(mk_raw) if isinstance(mk_raw, list) else 0
    return GameSummary(
        modules=[str(m) for m in modules],
        round_number=int(d.get("round_number", 0)),
        bank_total=int(bank.get("total", 0)),
        bank_broke_count=int(bank.get("broke_count", 0)),
        bank_reserve_added=int(bank.get("reserve_added_total", 0)),
        marketing_count=mk_count,
    )


def _build_participant(p: MatchParticipant) -> ParticipantInfo:
    display_name, restaurant_logo_id, restaurant_logo_key = _parse_participant_profile(p.score_json)
    return ParticipantInfo(
        user_id=p.user_id, role=p.role,
        seat_index=p.seat_index, result=p.result,
        display_name=display_name,
        restaurant_logo_id=restaurant_logo_id,
        restaurant_logo_key=restaurant_logo_key,
        score=_parse_score(p.score_json),
    )


@router.get("", response_model=list[MatchSummary])
async def list_matches(
    session_id: str = Query(...),
    db: AsyncSession = Depends(get_db),
):
    sess = await get_current_user(db=db, session_id=session_id)
    stmt = (
        select(Match)
        .join(MatchParticipant, MatchParticipant.match_id == Match.match_id)
        .where(MatchParticipant.user_id == sess.user_id)
        .order_by(Match.created_at.desc())
    )
    rows = (await db.execute(stmt)).scalars().all()
    match_ids = [m.match_id for m in rows]
    parts_stmt = select(MatchParticipant).where(MatchParticipant.match_id.in_(match_ids))
    parts = (await db.execute(parts_stmt)).scalars().all()
    parts_by_match: dict[str, list[ParticipantInfo]] = {}
    for p in parts:
        parts_by_match.setdefault(p.match_id, []).append(_build_participant(p))
    return [
        MatchSummary(
            match_id=m.match_id, room_code=m.room_code, status=m.status,
            player_count=m.player_count,
            started_at=m.started_at.isoformat() if m.started_at else None,
            ended_at=m.ended_at.isoformat() if m.ended_at else None,
            duration_sec=m.duration_sec,
            participants=parts_by_match.get(m.match_id, []),
        ) for m in rows
    ]


@router.get("/{match_id}", response_model=MatchDetail)
async def get_match(match_id: str, session_id: str = Query(...), db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=session_id)
    # Check participant
    part = (await db.execute(
        select(MatchParticipant).where(MatchParticipant.match_id == match_id, MatchParticipant.user_id == sess.user_id)
    )).scalar_one_or_none()
    if not part:
        raise HTTPException(403, "not a participant")
    match = (await db.execute(select(Match).where(Match.match_id == match_id))).scalar_one_or_none()
    if not match:
        raise HTTPException(404, "match not found")
    parts = (await db.execute(
        select(MatchParticipant).where(MatchParticipant.match_id == match_id)
    )).scalars().all()
    participants = [_build_participant(p) for p in parts]
    replay = (await db.execute(
        select(MatchReplay.id).where(MatchReplay.match_id == match_id)
    )).scalar_one_or_none()
    return MatchDetail(
        match_id=match.match_id, room_code=match.room_code, status=match.status,
        player_count=match.player_count,
        started_at=match.started_at.isoformat() if match.started_at else None,
        ended_at=match.ended_at.isoformat() if match.ended_at else None,
        duration_sec=match.duration_sec, seed=match.seed,
        schema_version=match.schema_version, game_version=match.game_version,
        final_hash=match.final_hash, summary=_parse_summary(match.summary_json),
        participants=participants, has_replay=replay is not None,
    )


@router.get("/{match_id}/replay", response_model=ReplayInfo)
async def get_replay(match_id: str, session_id: str = Query(...), db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=session_id)
    part = (await db.execute(
        select(MatchParticipant).where(MatchParticipant.match_id == match_id, MatchParticipant.user_id == sess.user_id)
    )).scalar_one_or_none()
    if not part:
        raise HTTPException(403, "not a participant")
    replay = (await db.execute(
        select(MatchReplay).where(MatchReplay.match_id == match_id)
    )).scalar_one_or_none()
    if not replay:
        raise HTTPException(404, "replay not found")
    return ReplayInfo(
        match_id=replay.match_id, storage_uri=_to_public_replay_uri(match_id, replay.storage_uri),
        checksum=replay.checksum, size_bytes=replay.size_bytes,
    )


@router.get("/{match_id}/replay/download")
async def download_replay(match_id: str, session_id: str = Query(...), db: AsyncSession = Depends(get_db)):
    sess = await get_current_user(db=db, session_id=session_id)
    part = (await db.execute(
        select(MatchParticipant).where(MatchParticipant.match_id == match_id, MatchParticipant.user_id == sess.user_id)
    )).scalar_one_or_none()
    if not part:
        raise HTTPException(403, "not a participant")

    replay = (await db.execute(
        select(MatchReplay).where(MatchReplay.match_id == match_id)
    )).scalar_one_or_none()
    if not replay:
        raise HTTPException(404, "replay not found")

    filename = parse_local_replay_filename(replay.storage_uri)
    if filename is not None:
        path = get_local_replay_path(filename)
        if not path.exists() or not path.is_file():
            raise HTTPException(404, "replay file missing")
        return FileResponse(path, media_type="application/json", filename=filename)

    storage_uri = str(replay.storage_uri or "").strip()
    if storage_uri == "":
        raise HTTPException(404, "replay uri missing")
    return RedirectResponse(storage_uri, status_code=307)
