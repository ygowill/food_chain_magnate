#!/usr/bin/env python3
"""Deterministic documentation governance checks for this repository.

The repository is being migrated incrementally. Frontmatter is mandatory for
the explicit formal paths declared below, including Vision, Requirements,
Backlog, Features, Decisions, governed Plans, Validation and current progress
entries. Any other document that opts into frontmatter is validated too.

All Markdown under ``docs/`` is always checked for broken relative links and
machine-specific ``/Users/...`` paths. This keeps the migration exception from
becoming an exception to portability or link integrity.

Only the Python standard library is used so the same command works locally and
in GitHub Actions without installing packages.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import re
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import unquote


MINIMUM_FIELDS = ("id", "doc_kind", "status", "created", "updated", "owners")

ALLOWED_STATUSES = {
	"vision": {"draft", "active", "superseded", "retired"},
	"feature": {
		"idea",
		"discovery",
		"planned",
		"in-progress",
		"validation",
		"done",
		"cancelled",
	},
	"decision": {"proposed", "accepted", "rejected", "superseded"},
	"validation": {"draft", "completed", "superseded"},
	"governance": {"draft", "active", "superseded", "retired"},
	"backlog": {"active", "archived"},
	"acceptance-queue": {"active", "archived"},
	"progress": {"current", "historical", "archived"},
	"architecture": {"draft", "active", "superseded", "archived"},
	"plan": {"draft", "active", "completed", "abandoned", "archived"},
	"research": {"draft", "active", "completed", "archived"},
	"reference": {"draft", "active", "superseded", "archived"},
	"review": {"draft", "completed", "archived"},
	"runbook": {"draft", "active", "superseded", "retired"},
	"incident": {"open", "mitigated", "resolved", "archived"},
	"lesson": {"draft", "validated", "institutionalized", "archived"},
	"requirement": {"draft", "accepted", "superseded", "retired"},
	"release": {"draft", "released", "withdrawn"},
}

LIST_FIELDS = {
	"owners",
	"feature_ids",
	"requirement_ids",
	"source_refs",
	"supersedes",
	"superseded_by",
	"tags",
	"decision_refs",
	"adr_refs",
	"validation_refs",
}

FORMAL_ROOTS = {
	"docs/features": "feature",
	"docs/decisions": "decision",
	"docs/validation": "validation",
	"docs/governance": "governance",
}

FORMAL_FILES = {
	"docs/VISION.md": "vision",
	"docs/REQUIREMENTS.md": "requirement",
	"docs/BACKLOG.md": "backlog",
	"docs/progress/current_development_progress_report.md": "progress",
	"docs/progress/issue_tracker.md": "progress",
	"docs/progress/acceptance_queue.md": "acceptance-queue",
}

GENERATED_INDEX_PATH = "docs/_generated/document-index.json"

REVIEW_REQUIRED_KINDS = {
	"vision",
	"requirement",
	"feature",
	"decision",
	"architecture",
	"plan",
	"governance",
	"backlog",
	"acceptance-queue",
	"progress",
}

# Template source files deliberately contain placeholder frontmatter and links.
# They are checked for machine-specific paths, but are not treated as instantiated
# formal documents until copied outside this directory and placeholders replaced.
TEMPLATE_SOURCE_PREFIXES = ("docs/templates/",)
TEMPLATE_REQUIRED_FIELDS = {
	"docs/templates/feature.md": {"id", "doc_kind", "status", "created", "updated", "owners", "requirement_ids", "decision_refs", "validation_refs", "review_after"},
	"docs/templates/decision.md": {"id", "doc_kind", "status", "created", "updated", "owners", "feature_ids", "requirement_ids", "supersedes", "superseded_by", "review_after"},
	"docs/templates/validation.md": {"id", "doc_kind", "status", "created", "updated", "owners", "feature_ids", "requirement_ids", "commit", "verdict"},
}

EXTERNAL_SCHEMES = {"http", "https", "mailto", "tel", "ftp", "data", "res", "app"}
LINK_RE = re.compile(r"!?\[[^\]\n]*\]\(\s*(?P<target><[^>\n]+>|[^)\s]+)")
TOP_LEVEL_FIELD_RE = re.compile(r"^([A-Za-z][A-Za-z0-9_-]*):(?:\s*(.*))?$")


@dataclass(frozen=True)
class Finding:
	path: str
	line: int
	code: str
	message: str


@dataclass(frozen=True)
class MarkdownLink:
	target: str
	line: int


@dataclass
class Frontmatter:
	values: dict[str, Any] = field(default_factory=dict)
	lines: dict[str, int] = field(default_factory=dict)
	end_line: int = 0


@dataclass
class Document:
	path: Path
	rel_path: str
	text: str
	frontmatter: Frontmatter | None
	links: list[MarkdownLink]


@dataclass
class CheckResult:
	findings: list[Finding]
	document_count: int
	governed_count: int
	non_governed_count: int
	link_count: int
	generated_index_text: str = ""


def _render_generated_index(documents: Iterable[Document]) -> str:
	entries: list[dict[str, Any]] = []
	optional_fields = (
		"review_after",
		"feature_ids",
		"requirement_ids",
		"decision_refs",
		"validation_refs",
		"supersedes",
		"superseded_by",
		"commit",
		"verdict",
	)
	for document in documents:
		formal, _ = _is_formal_path(document.rel_path)
		if not formal or document.frontmatter is None:
			continue
		values = document.frontmatter.values
		entry: dict[str, Any] = {
			"id": values.get("id"),
			"doc_kind": values.get("doc_kind"),
			"status": values.get("status"),
			"created": values.get("created"),
			"updated": values.get("updated"),
			"owners": values.get("owners"),
			"path": document.rel_path,
		}
		for field_name in optional_fields:
			if field_name in values:
				entry[field_name] = values[field_name]
		entries.append(entry)
	entries.sort(key=lambda item: (str(item.get("doc_kind", "")), str(item.get("id", ""))))
	canonical_entries = json.dumps(entries, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
	payload = {
		"schema_version": 1,
		"generated_by": "python3 tools/docs_governance.py --write-index",
		"source_frontmatter_sha256": hashlib.sha256(canonical_entries.encode("utf-8")).hexdigest(),
		"documents": entries,
	}
	return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def _strip_scalar(value: str) -> str:
	value = value.strip()
	if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
		return value[1:-1]
	if " #" in value:
		value = value.split(" #", 1)[0].rstrip()
	return value


def _parse_inline_list(value: str) -> list[str]:
	inside = value[1:-1].strip()
	if not inside:
		return []
	try:
		row = next(csv.reader([inside], skipinitialspace=True))
	except (csv.Error, StopIteration):
		return [_strip_scalar(part) for part in inside.split(",")]
	return [_strip_scalar(part) for part in row]


def parse_frontmatter(text: str, rel_path: str) -> tuple[Frontmatter | None, list[Finding]]:
	lines = text.lstrip("\ufeff").splitlines()
	if not lines or lines[0].strip() != "---":
		return None, []

	closing_index = next(
		(index for index, line in enumerate(lines[1:], start=1) if line.strip() == "---"),
		None,
	)
	if closing_index is None:
		return None, [Finding(rel_path, 1, "FRONTMATTER_UNCLOSED", "frontmatter has no closing '---'")]

	frontmatter = Frontmatter(end_line=closing_index + 1)
	findings: list[Finding] = []
	current_key: str | None = None
	for index, raw_line in enumerate(lines[1:closing_index], start=2):
		if not raw_line.strip() or raw_line.lstrip().startswith("#"):
			continue

		if raw_line[0].isspace():
			stripped = raw_line.strip()
			if current_key is not None and stripped.startswith("-"):
				item = _strip_scalar(stripped[1:].strip())
				current = frontmatter.values.get(current_key)
				if not isinstance(current, list):
					current = []
					frontmatter.values[current_key] = current
				current.append(item)
			# Nested mappings are allowed for extension fields such as source_refs.
			continue

		match = TOP_LEVEL_FIELD_RE.match(raw_line)
		if match is None:
			findings.append(
				Finding(rel_path, index, "FRONTMATTER_SYNTAX", "expected a top-level 'key: value' field")
			)
			current_key = None
			continue

		key, raw_value = match.group(1), (match.group(2) or "")
		if key in frontmatter.values:
			findings.append(Finding(rel_path, index, "FRONTMATTER_DUPLICATE_KEY", f"duplicate field '{key}'"))
			continue
		frontmatter.lines[key] = index
		current_key = key
		value = raw_value.strip()
		if value.startswith("[") and value.endswith("]"):
			frontmatter.values[key] = _parse_inline_list(value)
		elif not value and key in LIST_FIELDS:
			frontmatter.values[key] = []
		else:
			frontmatter.values[key] = _strip_scalar(value)

	return frontmatter, findings


def _mask_fenced_code(text: str) -> str:
	"""Mask fenced code while preserving newlines and character offsets."""

	masked_lines: list[str] = []
	in_fence = False
	fence_marker = ""
	for line in text.splitlines(keepends=True):
		stripped = line.lstrip()
		marker = "```" if stripped.startswith("```") else "~~~" if stripped.startswith("~~~") else ""
		if marker:
			if not in_fence:
				in_fence = True
				fence_marker = marker
			elif marker == fence_marker:
				in_fence = False
				fence_marker = ""
			masked_lines.append("".join("\n" if char == "\n" else "\r" if char == "\r" else " " for char in line))
			continue
		if in_fence:
			masked_lines.append("".join("\n" if char == "\n" else "\r" if char == "\r" else " " for char in line))
		else:
			masked_lines.append(line)
	return "".join(masked_lines)


def extract_markdown_links(text: str) -> list[MarkdownLink]:
	masked = _mask_fenced_code(text)
	links: list[MarkdownLink] = []
	for match in LINK_RE.finditer(masked):
		target = match.group("target").strip()
		if target.startswith("<") and target.endswith(">"):
			target = target[1:-1].strip()
		line = masked.count("\n", 0, match.start()) + 1
		links.append(MarkdownLink(target=target, line=line))
	return links


def _is_formal_path(rel_path: str) -> tuple[bool, str | None]:
	path = Path(rel_path)
	if path.name.casefold() == "readme.md":
		return False, None
	if rel_path in FORMAL_FILES:
		return True, FORMAL_FILES[rel_path]
	if rel_path.startswith("docs/plans/PLAN-"):
		return True, "plan"
	for root, expected_kind in FORMAL_ROOTS.items():
		try:
			path.relative_to(root)
		except ValueError:
			continue
		return True, expected_kind
	return False, None


def _is_template_source(rel_path: str) -> bool:
	return rel_path.startswith(TEMPLATE_SOURCE_PREFIXES)


def _as_nonempty_string(value: Any) -> str | None:
	if isinstance(value, str) and value.strip():
		return value.strip()
	return None


def _validate_date(
	document: Document,
	frontmatter: Frontmatter,
	field_name: str,
	findings: list[Finding],
) -> dt.date | None:
	value = _as_nonempty_string(frontmatter.values.get(field_name))
	line = frontmatter.lines.get(field_name, 1)
	if value is None:
		return None
	try:
		parsed = dt.date.fromisoformat(value)
	except ValueError:
		findings.append(
			Finding(document.rel_path, line, "INVALID_DATE", f"'{field_name}' must use YYYY-MM-DD")
		)
		return None
	if parsed.isoformat() != value:
		findings.append(
			Finding(document.rel_path, line, "INVALID_DATE", f"'{field_name}' must use zero-padded YYYY-MM-DD")
		)
		return None
	return parsed


def _validate_frontmatter(document: Document, expected_kind: str | None) -> list[Finding]:
	frontmatter = document.frontmatter
	if frontmatter is None:
		return []
	values = frontmatter.values
	findings: list[Finding] = []

	for field_name in MINIMUM_FIELDS:
		if field_name not in values:
			findings.append(
				Finding(document.rel_path, 1, "MISSING_FIELD", f"frontmatter requires '{field_name}'")
			)
		elif field_name != "owners" and _as_nonempty_string(values[field_name]) is None:
			findings.append(
				Finding(
					document.rel_path,
					frontmatter.lines.get(field_name, 1),
					"EMPTY_FIELD",
					f"frontmatter field '{field_name}' cannot be empty",
				)
			)

	doc_id = _as_nonempty_string(values.get("id"))
	if doc_id is not None and (any(char.isspace() for char in doc_id) or doc_id.startswith("-") or doc_id.endswith("-")):
		findings.append(
			Finding(document.rel_path, frontmatter.lines.get("id", 1), "INVALID_ID", "id must be a stable token without whitespace")
		)

	doc_kind = _as_nonempty_string(values.get("doc_kind"))
	if doc_kind is not None and doc_kind not in ALLOWED_STATUSES:
		allowed = ", ".join(sorted(ALLOWED_STATUSES))
		findings.append(
			Finding(document.rel_path, frontmatter.lines.get("doc_kind", 1), "INVALID_DOC_KIND", f"unknown doc_kind '{doc_kind}'; expected one of: {allowed}")
		)
	elif expected_kind is not None and doc_kind is not None and doc_kind != expected_kind:
		findings.append(
			Finding(document.rel_path, frontmatter.lines.get("doc_kind", 1), "DOC_KIND_PATH_MISMATCH", f"this directory requires doc_kind '{expected_kind}'")
		)

	status = _as_nonempty_string(values.get("status"))
	if doc_kind in ALLOWED_STATUSES and status is not None and status not in ALLOWED_STATUSES[doc_kind]:
		allowed = ", ".join(sorted(ALLOWED_STATUSES[doc_kind]))
		findings.append(
			Finding(document.rel_path, frontmatter.lines.get("status", 1), "INVALID_STATUS", f"status '{status}' is invalid for {doc_kind}; expected one of: {allowed}")
		)

	owners = values.get("owners")
	if "owners" in values and (not isinstance(owners, list) or not owners or not all(_as_nonempty_string(item) for item in owners)):
		findings.append(
			Finding(document.rel_path, frontmatter.lines.get("owners", 1), "INVALID_OWNERS", "owners must be a non-empty YAML list")
		)

	created = _validate_date(document, frontmatter, "created", findings)
	updated = _validate_date(document, frontmatter, "updated", findings)
	if created is not None and updated is not None and updated < created:
		findings.append(
			Finding(document.rel_path, frontmatter.lines.get("updated", 1), "INVALID_DATE_ORDER", "updated cannot be earlier than created")
		)
	if "review_after" in values:
		review_after = _validate_date(document, frontmatter, "review_after", findings)
		if review_after is not None and updated is not None and review_after < updated:
			findings.append(
				Finding(document.rel_path, frontmatter.lines.get("review_after", 1), "INVALID_REVIEW_DATE", "review_after cannot be earlier than updated")
			)
		if review_after is not None and review_after < dt.date.today():
			findings.append(
				Finding(document.rel_path, frontmatter.lines.get("review_after", 1), "REVIEW_OVERDUE", f"review_after elapsed on {review_after.isoformat()}; review or supersede this document")
			)
	elif doc_kind in REVIEW_REQUIRED_KINDS and status not in {"superseded", "retired", "archived", "historical", "abandoned"}:
		findings.append(
			Finding(document.rel_path, 1, "MISSING_FIELD", f"active {doc_kind} frontmatter requires 'review_after'")
		)

	if doc_id is not None:
		filename = document.path.name
		id_patterns = {
			"feature": r"F-\d{3}",
			"decision": r"ADR-\d{4}",
			"validation": r"VAL-\d{4}-\d{3}",
			"plan": r"PLAN-\d{4}-\d{3}",
		}
		if doc_kind in id_patterns and re.fullmatch(id_patterns[doc_kind], doc_id) is None:
			findings.append(Finding(document.rel_path, frontmatter.lines.get("id", 1), "INVALID_ID_FORMAT", f"{doc_kind} id must match {id_patterns[doc_kind]}"))
		if doc_kind == "feature" and not filename.startswith(f"{doc_id}-"):
			findings.append(Finding(document.rel_path, frontmatter.lines.get("id", 1), "ID_FILENAME_MISMATCH", f"feature filename must start with '{doc_id}-'"))
		elif doc_kind == "validation" and not filename.startswith(f"{doc_id}-"):
			findings.append(Finding(document.rel_path, frontmatter.lines.get("id", 1), "ID_FILENAME_MISMATCH", f"validation filename must start with '{doc_id}-'"))
		elif doc_kind == "decision" and doc_id.startswith("ADR-"):
			expected_prefix = doc_id.removeprefix("ADR-")
			if not filename.startswith(f"{expected_prefix}-"):
				findings.append(Finding(document.rel_path, frontmatter.lines.get("id", 1), "ID_FILENAME_MISMATCH", f"decision filename must start with '{expected_prefix}-'"))
		elif doc_kind == "plan" and not filename.startswith(f"{doc_id}-"):
			findings.append(Finding(document.rel_path, frontmatter.lines.get("id", 1), "ID_FILENAME_MISMATCH", f"plan filename must start with '{doc_id}-'"))

	if doc_kind == "feature":
		if "requirement_ids" not in values:
			findings.append(Finding(document.rel_path, 1, "MISSING_FIELD", "feature frontmatter requires 'requirement_ids' (it may be empty)"))
		elif not isinstance(values["requirement_ids"], list) or not values["requirement_ids"]:
			findings.append(Finding(document.rel_path, frontmatter.lines.get("requirement_ids", 1), "INVALID_LIST", "requirement_ids must be a non-empty YAML list"))
		for field_name in ("decision_refs", "validation_refs"):
			if field_name not in values:
				findings.append(Finding(document.rel_path, 1, "MISSING_FIELD", f"feature frontmatter requires '{field_name}' (it may be empty)"))
			elif not isinstance(values[field_name], list):
				findings.append(Finding(document.rel_path, frontmatter.lines.get(field_name, 1), "INVALID_LIST", f"{field_name} must be a YAML list"))
		if "feature_ids" in values:
			findings.append(Finding(document.rel_path, frontmatter.lines.get("feature_ids", 1), "SELF_FEATURE_IDS", "a feature document uses its own id; remove feature_ids"))
	elif doc_kind == "decision":
		for field_name in ("feature_ids", "requirement_ids", "supersedes", "superseded_by", "review_after"):
			if field_name not in values:
				findings.append(Finding(document.rel_path, 1, "MISSING_FIELD", f"decision frontmatter requires '{field_name}'"))
		for field_name in ("feature_ids", "requirement_ids", "supersedes", "superseded_by"):
			if field_name in values and not isinstance(values[field_name], list):
				findings.append(Finding(document.rel_path, frontmatter.lines.get(field_name, 1), "INVALID_LIST", f"{field_name} must be a YAML list"))
	elif doc_kind == "validation":
		for field_name in ("feature_ids", "requirement_ids", "commit", "verdict"):
			if field_name not in values:
				findings.append(Finding(document.rel_path, 1, "MISSING_FIELD", f"validation frontmatter requires '{field_name}'"))
		if "feature_ids" in values and (not isinstance(values["feature_ids"], list) or not values["feature_ids"]):
			findings.append(Finding(document.rel_path, frontmatter.lines.get("feature_ids", 1), "INVALID_FEATURE_IDS", "validation feature_ids must be a non-empty YAML list"))
		if "requirement_ids" in values and (not isinstance(values["requirement_ids"], list) or not values["requirement_ids"]):
			findings.append(Finding(document.rel_path, frontmatter.lines.get("requirement_ids", 1), "INVALID_REQUIREMENT_IDS", "validation requirement_ids must be a non-empty YAML list"))
		for field_name in ("commit", "verdict"):
			if field_name in values and _as_nonempty_string(values[field_name]) is None:
				findings.append(Finding(document.rel_path, frontmatter.lines.get(field_name, 1), "EMPTY_FIELD", f"validation field '{field_name}' cannot be empty"))
		verdict = _as_nonempty_string(values.get("verdict"))
		allowed_verdicts = {"pending", "pass", "fail", "inconclusive"} if status == "draft" else {"pass", "fail", "inconclusive"}
		if verdict is not None and verdict not in allowed_verdicts:
			findings.append(Finding(document.rel_path, frontmatter.lines.get("verdict", 1), "INVALID_VERDICT", f"verdict '{verdict}' is invalid for validation status '{status}'"))
		commit = _as_nonempty_string(values.get("commit"))
		if status in {"completed", "superseded"} and commit is not None and re.fullmatch(r"[0-9a-fA-F]{7,40}", commit) is None:
			findings.append(Finding(document.rel_path, frontmatter.lines.get("commit", 1), "INVALID_COMMIT", "completed validation commit must be a 7-40 character hexadecimal Git SHA"))
	elif doc_kind == "plan":
		for field_name in ("feature_ids", "requirement_ids"):
			if field_name not in values:
				findings.append(Finding(document.rel_path, 1, "MISSING_FIELD", f"plan frontmatter requires '{field_name}' (it may be empty)"))
			elif not isinstance(values[field_name], list):
				findings.append(Finding(document.rel_path, frontmatter.lines.get(field_name, 1), "INVALID_LIST", f"{field_name} must be a YAML list"))

	return findings


def _clean_link_target(target: str) -> str:
	target = target.replace("\\ ", " ").strip()
	target = target.split("#", 1)[0].split("?", 1)[0]
	return unquote(target)


def _resolve_relative_target(root: Path, document: Document, raw_target: str, *, metadata: bool = False) -> Path | None:
	target = _clean_link_target(raw_target)
	if not target or target.startswith("#"):
		return None
	if target.startswith("//") or target.startswith("/"):
		return None
	if re.match(r"^[A-Za-z][A-Za-z0-9+.-]*:", target):
		scheme = target.split(":", 1)[0].casefold()
		if scheme in EXTERNAL_SCHEMES:
			return None
	if any(token in target for token in ("{{", "}}", "${", "<...>")):
		return None
	if metadata and target.startswith("docs/"):
		return (root / target).resolve()
	return (document.path.parent / target).resolve()


def _path_is_within(path: Path, root: Path) -> bool:
	try:
		path.relative_to(root)
		return True
	except ValueError:
		return False


def _check_links(root: Path, document: Document) -> tuple[list[Finding], int]:
	findings: list[Finding] = []
	checked = 0
	for link in document.links:
		target = _resolve_relative_target(root, document, link.target)
		if target is None:
			continue
		checked += 1
		if not _path_is_within(target, root):
			findings.append(Finding(document.rel_path, link.line, "LINK_OUTSIDE_REPO", f"relative link escapes the repository: {link.target}"))
		elif not target.exists():
			findings.append(Finding(document.rel_path, link.line, "BROKEN_LINK", f"relative link target does not exist: {link.target}"))
	return findings, checked


def _frontmatter_refs(frontmatter: Frontmatter, names: Iterable[str]) -> list[tuple[str, int]]:
	refs: list[tuple[str, int]] = []
	for name in names:
		value = frontmatter.values.get(name)
		if value is None:
			continue
		if not isinstance(value, list):
			refs.append(("", frontmatter.lines.get(name, 1)))
			continue
		refs.extend((str(item).strip(), frontmatter.lines.get(name, 1)) for item in value)
	return refs


def _check_feature_references(
	root: Path,
	document: Document,
	documents_by_path: dict[Path, Document],
) -> list[Finding]:
	frontmatter = document.frontmatter
	if frontmatter is None or frontmatter.values.get("doc_kind") != "feature":
		return []
	findings: list[Finding] = []
	feature_id = _as_nonempty_string(frontmatter.values.get("id"))
	passing_validation_paths: set[Path] = set()

	for field_names, expected_dir, label in (
		(("decision_refs", "adr_refs"), root / "docs" / "decisions", "decision"),
		(("validation_refs",), root / "docs" / "validation", "validation"),
	):
		for raw_ref, line in _frontmatter_refs(frontmatter, field_names):
			if not raw_ref:
				findings.append(Finding(document.rel_path, line, "INVALID_FEATURE_REF", f"{label} references must be a YAML list of paths"))
				continue
			target = _resolve_relative_target(root, document, raw_ref, metadata=True)
			if target is None or not _path_is_within(target, root):
				findings.append(Finding(document.rel_path, line, "INVALID_FEATURE_REF", f"invalid {label} reference: {raw_ref}"))
				continue
			if not target.is_file():
				findings.append(Finding(document.rel_path, line, "FEATURE_REF_MISSING", f"{label} reference does not exist: {raw_ref}"))
				continue
			if not _path_is_within(target, expected_dir.resolve()):
				findings.append(Finding(document.rel_path, line, "FEATURE_REF_KIND", f"{label} reference must point into {expected_dir.relative_to(root)}: {raw_ref}"))
				continue

			target_document = documents_by_path.get(target.resolve())
			target_frontmatter = target_document.frontmatter if target_document is not None else None
			if target_frontmatter is None or target_frontmatter.values.get("doc_kind") != label:
				findings.append(Finding(document.rel_path, line, "FEATURE_REF_METADATA", f"{label} reference lacks matching governed frontmatter: {raw_ref}"))
				continue
			target_feature_ids = target_frontmatter.values.get("feature_ids")
			if feature_id is not None and (not isinstance(target_feature_ids, list) or feature_id not in target_feature_ids):
				findings.append(Finding(document.rel_path, line, "FEATURE_REF_NOT_RECIPROCAL", f"{label} reference does not link back to {feature_id}: {raw_ref}"))
				continue
			if label == "validation":
				validation_status = target_frontmatter.values.get("status")
				validation_verdict = target_frontmatter.values.get("verdict")
				requirement_ids = frontmatter.values.get("requirement_ids")
				validated_requirements = target_frontmatter.values.get("requirement_ids")
				requirements_covered = (
					isinstance(requirement_ids, list)
					and isinstance(validated_requirements, list)
					and set(requirement_ids).issubset(set(validated_requirements))
				)
				if validation_status == "completed" and validation_verdict == "pass" and requirements_covered:
					passing_validation_paths.add(target)

	if frontmatter.values.get("status") == "done" and not passing_validation_paths:
		findings.append(
			Finding(
				document.rel_path,
				frontmatter.lines.get("status", 1),
				"DONE_WITHOUT_PASSING_VALIDATION",
				"a done feature requires a referenced completed/pass validation that links back and covers all requirement_ids",
			)
		)
	return findings


def check_repository(root: Path, *, check_generated_index: bool = True) -> CheckResult:
	root = root.resolve()
	docs_root = root / "docs"
	findings: list[Finding] = []
	documents: list[Document] = []
	governed_count = 0
	non_governed_count = 0
	link_count = 0

	if not docs_root.is_dir():
		return CheckResult(
			findings=[Finding("docs", 1, "DOCS_DIR_MISSING", "docs directory does not exist")],
			document_count=0,
			governed_count=0,
			non_governed_count=0,
			link_count=0,
			generated_index_text="",
		)
	for template_path in TEMPLATE_REQUIRED_FIELDS:
		if not (root / template_path).is_file():
			findings.append(Finding(template_path, 1, "TEMPLATE_MISSING", "required governance template does not exist"))

	for path in sorted(docs_root.rglob("*.md")):
		rel_path = path.relative_to(root).as_posix()
		try:
			text = path.read_text(encoding="utf-8")
		except UnicodeDecodeError:
			findings.append(Finding(rel_path, 1, "NOT_UTF8", "Markdown files must be UTF-8"))
			continue

		template_source = _is_template_source(rel_path)
		if template_source:
			frontmatter, parse_findings = None, []
			for field_name in sorted(TEMPLATE_REQUIRED_FIELDS.get(rel_path, set())):
				if re.search(rf"(?m)^{re.escape(field_name)}\s*:", text) is None:
					findings.append(Finding(rel_path, 1, "TEMPLATE_FIELD_MISSING", f"template requires frontmatter field '{field_name}'"))
		else:
			frontmatter, parse_findings = parse_frontmatter(text, rel_path)
		findings.extend(parse_findings)
		formal, expected_kind = _is_formal_path(rel_path)
		if formal:
			governed_count += 1
			if frontmatter is None:
				findings.append(Finding(rel_path, 1, "MISSING_FRONTMATTER", "formal active document requires frontmatter"))
		else:
			non_governed_count += 1

		links = [] if template_source else extract_markdown_links(text)
		document = Document(path=path, rel_path=rel_path, text=text, frontmatter=frontmatter, links=links)
		documents.append(document)
		if frontmatter is not None:
			findings.extend(_validate_frontmatter(document, expected_kind))

		for line_number, line in enumerate(text.splitlines(), start=1):
			if "/Users/" in line:
				findings.append(Finding(rel_path, line_number, "ABSOLUTE_USER_PATH", "replace machine-specific /Users/... paths with repository-relative paths or portable placeholders"))

		link_findings, checked = _check_links(root, document)
		findings.extend(link_findings)
		link_count += checked

	id_locations: dict[str, list[Document]] = {}
	documents_by_path = {document.path.resolve(): document for document in documents}
	for document in documents:
		if document.frontmatter is None:
			continue
		doc_id = _as_nonempty_string(document.frontmatter.values.get("id"))
		if doc_id is not None:
			id_locations.setdefault(doc_id, []).append(document)
	for doc_id, matching_documents in id_locations.items():
		if len(matching_documents) < 2:
			continue
		paths = ", ".join(document.rel_path for document in matching_documents)
		for document in matching_documents:
			assert document.frontmatter is not None
			findings.append(Finding(document.rel_path, document.frontmatter.lines.get("id", 1), "DUPLICATE_ID", f"id '{doc_id}' is also used by: {paths}"))

	requirement_locations: dict[str, list[tuple[Document, int]]] = {}
	for document in documents:
		if document.rel_path != "docs/REQUIREMENTS.md":
			continue
		for line_number, line in enumerate(document.text.splitlines(), start=1):
			match = re.match(r"^#{2,6}\s+((?:REQ|NFR)-\d+)\b", line)
			if match is not None:
				requirement_locations.setdefault(match.group(1), []).append((document, line_number))
	for requirement_id, locations in requirement_locations.items():
		if len(locations) < 2:
			continue
		for document, line_number in locations:
			findings.append(Finding(document.rel_path, line_number, "DUPLICATE_REQUIREMENT_ID", f"requirement id '{requirement_id}' is defined more than once"))

	for document in documents:
		findings.extend(_check_feature_references(root, document, documents_by_path))
		frontmatter = document.frontmatter
		if frontmatter is None:
			continue

		requirement_ids = frontmatter.values.get("requirement_ids")
		if isinstance(requirement_ids, list):
			seen_requirement_ids: set[str] = set()
			for requirement_id in requirement_ids:
				requirement_id_string = _as_nonempty_string(requirement_id)
				if requirement_id_string is None:
					findings.append(Finding(document.rel_path, frontmatter.lines.get("requirement_ids", 1), "INVALID_REQUIREMENT_ID_REF", "requirement_ids entries cannot be empty"))
					continue
				if requirement_id_string in seen_requirement_ids:
					findings.append(Finding(document.rel_path, frontmatter.lines.get("requirement_ids", 1), "DUPLICATE_REQUIREMENT_REF", f"requirement_ids repeats '{requirement_id_string}'"))
				seen_requirement_ids.add(requirement_id_string)
				if requirement_id_string not in requirement_locations:
					findings.append(Finding(document.rel_path, frontmatter.lines.get("requirement_ids", 1), "UNKNOWN_REQUIREMENT_ID", f"requirement id is not defined in docs/REQUIREMENTS.md: {requirement_id_string}"))
				elif frontmatter.values.get("doc_kind") in {"feature", "validation"} and document.text.count(requirement_id_string) < 2:
					findings.append(Finding(document.rel_path, frontmatter.lines.get("requirement_ids", 1), "REQUIREMENT_NOT_MAPPED", f"{requirement_id_string} is declared but has no body evidence/AC mapping"))

		feature_ids = frontmatter.values.get("feature_ids")
		if not isinstance(feature_ids, list):
			continue
		for feature_id in feature_ids:
			feature_id_string = _as_nonempty_string(feature_id)
			if feature_id_string is None:
				findings.append(Finding(document.rel_path, frontmatter.lines.get("feature_ids", 1), "INVALID_FEATURE_ID_REF", "feature_ids entries cannot be empty"))
				continue
			matches = id_locations.get(feature_id_string, [])
			if not any(match.frontmatter is not None and match.frontmatter.values.get("doc_kind") == "feature" for match in matches):
				findings.append(Finding(document.rel_path, frontmatter.lines.get("feature_ids", 1), "UNKNOWN_FEATURE_ID", f"feature id does not resolve to a feature document: {feature_id_string}"))

		for raw_ref, line in _frontmatter_refs(frontmatter, ("source_refs",)):
			if not raw_ref:
				findings.append(Finding(document.rel_path, line, "INVALID_SOURCE_REF", "source_refs must be a YAML list of repository paths"))
				continue
			target = _resolve_relative_target(root, document, raw_ref, metadata=True)
			if target is None or not _path_is_within(target, root) or not target.exists():
				findings.append(Finding(document.rel_path, line, "SOURCE_REF_MISSING", f"source reference does not exist: {raw_ref}"))

		if frontmatter.values.get("doc_kind") == "decision":
			doc_id = _as_nonempty_string(frontmatter.values.get("id"))
			status = frontmatter.values.get("status")
			superseded_by = frontmatter.values.get("superseded_by")
			if status == "superseded" and (not isinstance(superseded_by, list) or not superseded_by):
				findings.append(Finding(document.rel_path, frontmatter.lines.get("status", 1), "SUPERSEDED_WITHOUT_REPLACEMENT", "a superseded decision requires superseded_by"))
			if status != "superseded" and isinstance(superseded_by, list) and superseded_by:
				findings.append(Finding(document.rel_path, frontmatter.lines.get("superseded_by", 1), "ACTIVE_WITH_REPLACEMENT", "a decision with superseded_by must have status superseded"))
			for field_name, reciprocal_field in (("supersedes", "superseded_by"), ("superseded_by", "supersedes")):
				refs = frontmatter.values.get(field_name)
				if not isinstance(refs, list):
					continue
				for ref in refs:
					ref_id = _as_nonempty_string(ref)
					if ref_id is None:
						continue
					if ref_id == doc_id:
						findings.append(Finding(document.rel_path, frontmatter.lines.get(field_name, 1), "DECISION_SELF_REFERENCE", f"{field_name} cannot reference the same decision"))
						continue
					targets = [item for item in id_locations.get(ref_id, []) if item.frontmatter is not None and item.frontmatter.values.get("doc_kind") == "decision"]
					if len(targets) != 1:
						findings.append(Finding(document.rel_path, frontmatter.lines.get(field_name, 1), "UNKNOWN_DECISION_ID", f"{field_name} does not resolve to exactly one decision: {ref_id}"))
						continue
					target_values = targets[0].frontmatter.values
					reciprocal = target_values.get(reciprocal_field)
					if not isinstance(reciprocal, list) or doc_id not in reciprocal:
						findings.append(Finding(document.rel_path, frontmatter.lines.get(field_name, 1), "SUPERSESSION_NOT_RECIPROCAL", f"{ref_id} must list {doc_id} in {reciprocal_field}"))

	generated_index_text = _render_generated_index(documents)
	if check_generated_index:
		generated_index_path = root / GENERATED_INDEX_PATH
		if not generated_index_path.is_file():
			findings.append(Finding(GENERATED_INDEX_PATH, 1, "GENERATED_INDEX_MISSING", "run 'python3 tools/docs_governance.py --write-index' and commit the result"))
		else:
			try:
				actual_index_text = generated_index_path.read_text(encoding="utf-8")
			except UnicodeDecodeError:
				actual_index_text = ""
			if actual_index_text != generated_index_text:
				findings.append(Finding(GENERATED_INDEX_PATH, 1, "GENERATED_INDEX_STALE", "generated document index does not match formal frontmatter; rerun --write-index"))

	findings.sort(key=lambda item: (item.path, item.line, item.code, item.message))
	return CheckResult(
		findings=findings,
		document_count=len(documents),
		governed_count=governed_count,
		non_governed_count=non_governed_count,
		link_count=link_count,
		generated_index_text=generated_index_text,
	)


def _write_test_file(root: Path, relative_path: str, content: str) -> None:
	path = root / relative_path
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(content.strip() + "\n", encoding="utf-8")


def run_self_test() -> int:
	with tempfile.TemporaryDirectory(prefix="docs-governance-") as temporary_directory:
		root = Path(temporary_directory)
		for template_path, fields in TEMPLATE_REQUIRED_FIELDS.items():
			template_body = "---\n" + "\n".join(f"{field_name}: placeholder" for field_name in sorted(fields)) + "\n---\n# Template"
			_write_test_file(root, template_path, template_body)
		_write_test_file(
			root,
			"docs/REQUIREMENTS.md",
			"""
---
id: REQUIREMENTS-001
doc_kind: requirement
status: accepted
created: 2026-07-11
updated: 2026-07-11
owners: [product-owner]
review_after: 2099-01-01
---
# Requirements

## Example

### REQ-001 Example requirement
""",
		)
		_write_test_file(
			root,
			"docs/features/F-001-example.md",
			"""
---
id: F-001
doc_kind: feature
status: done
created: 2026-07-11
updated: 2026-07-11
owners: [project-maintainers]
requirement_ids: [REQ-001]
decision_refs: [../decisions/0005-example.md]
validation_refs: [../validation/VAL-2026-001-example.md]
review_after: 2099-01-01
---
# Example

[Requirement](../REQUIREMENTS.md): REQ-001
[Decision](../decisions/0005-example.md)
[Validation](../validation/VAL-2026-001-example.md)
""",
		)
		_write_test_file(
			root,
			"docs/decisions/0005-example.md",
			"""
---
id: ADR-0005
doc_kind: decision
status: accepted
created: 2026-07-11
updated: 2026-07-11
owners: [architecture-owner]
feature_ids: [F-001]
requirement_ids: [REQ-001]
supersedes: []
superseded_by: []
review_after: 2099-01-01
---
# Decision
""",
		)
		_write_test_file(
			root,
			"docs/validation/VAL-2026-001-example.md",
			"""
---
id: VAL-2026-001
doc_kind: validation
status: completed
created: 2026-07-11
updated: 2026-07-11
owners: [qa-owner]
feature_ids: [F-001]
requirement_ids: [REQ-001]
commit: deadbeef
verdict: pass
---
# Validation

REQ-001 pass.
""",
		)

		valid_result = check_repository(root, check_generated_index=False)
		if valid_result.findings:
			print("FAIL docs governance self-test: valid fixture produced findings")
			for finding in valid_result.findings:
				print(f"FAIL {finding.path}:{finding.line} [{finding.code}] {finding.message}")
			return 1

		_write_test_file(
			root,
			"docs/features/F-001-broken.md",
			"""
---
id: F-001
doc_kind: feature
status: done
created: 2026-07-11
updated: 2026-07-11
owners: [project-maintainers]
requirement_ids: [REQ-999]
decision_refs: []
validation_refs: [../validation/missing.md]
review_after: 2099-01-01
---
# Broken

[Broken](../validation/also-missing.md)
/Users/example/private/path
""",
		)
		_write_test_file(root, "docs/features/missing-frontmatter.md", "# Missing frontmatter")
		_write_test_file(
			root,
			"docs/validation/VAL-2026-002-invalid-verdict.md",
			"""
---
id: VAL-2026-002
doc_kind: validation
status: completed
created: 2026-07-11
updated: 2026-07-11
owners: [qa-owner]
feature_ids: [F-001]
requirement_ids: [REQ-001]
commit: deadbeef
verdict: passed
---
# Invalid verdict

REQ-001 was checked.
""",
		)
		invalid_result = check_repository(root, check_generated_index=False)
		codes = {finding.code for finding in invalid_result.findings}
		expected_codes = {
			"ABSOLUTE_USER_PATH",
			"BROKEN_LINK",
			"DONE_WITHOUT_PASSING_VALIDATION",
			"DUPLICATE_ID",
			"FEATURE_REF_MISSING",
			"INVALID_VERDICT",
			"MISSING_FRONTMATTER",
			"UNKNOWN_REQUIREMENT_ID",
		}
		missing_codes = sorted(expected_codes - codes)
		if missing_codes:
			print(f"FAIL docs governance self-test: missing expected findings: {', '.join(missing_codes)}")
			return 1

	print("PASS docs governance self-test")
	return 0


def print_scope() -> None:
	print("Formal frontmatter scope:")
	for root, expected_kind in FORMAL_ROOTS.items():
		kind_description = expected_kind or "any legal doc_kind"
		print(f"- {root}/**/*.md (except README.md): {kind_description}")
	for path, expected_kind in FORMAL_FILES.items():
		print(f"- {path}: {expected_kind}")
	print("- docs/plans/PLAN-*.md: plan")
	print("- any legacy Markdown with frontmatter opts into schema validation")
	print("- docs/templates/** is placeholder source: portability checked, schema/link checks begin after instantiation")
	print(f"- {GENERATED_INDEX_PATH}: deterministic compiled index; normal checks fail when stale")
	print("Global checks: relative Markdown link targets, requirement/Feature/ADR relations, review dates, and /Users/... path portability")


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description="Validate documentation metadata, links, references, and evidence gates.")
	parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1], help="repository root (defaults to the script's parent repository)")
	parser.add_argument("--self-test", action="store_true", help="run deterministic built-in positive and negative fixtures")
	parser.add_argument("--explain", action="store_true", help="print the migration scope and exit")
	parser.add_argument("--write-index", action="store_true", help=f"regenerate {GENERATED_INDEX_PATH} after all other checks pass")
	args = parser.parse_args(argv)

	if args.self_test:
		return run_self_test()
	if args.explain:
		print_scope()
		return 0

	result = check_repository(args.root, check_generated_index=not args.write_index)
	for finding in result.findings:
		print(f"FAIL {finding.path}:{finding.line} [{finding.code}] {finding.message}")
	if result.findings:
		print(
			"FAIL docs governance "
			f"(errors={len(result.findings)}, documents={result.document_count}, "
			f"governed={result.governed_count}, non_governed={result.non_governed_count}, links={result.link_count})"
		)
		return 1
	if args.write_index:
		index_path = args.root.resolve() / GENERATED_INDEX_PATH
		index_path.parent.mkdir(parents=True, exist_ok=True)
		index_path.write_text(result.generated_index_text, encoding="utf-8")
		print(f"WROTE {GENERATED_INDEX_PATH} ({len(json.loads(result.generated_index_text)['documents'])} documents)")
		return 0

	print(
		"PASS docs governance "
		f"(documents={result.document_count}, governed={result.governed_count}, "
		f"non_governed={result.non_governed_count}, links={result.link_count})"
	)
	return 0


if __name__ == "__main__":
	sys.exit(main())
