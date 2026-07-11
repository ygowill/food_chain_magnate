#!/usr/bin/env python3
"""Validate repository-local Codex Skills and their deterministic index."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SKILLS_ROOT = ".agents/skills"
GENERATED_INDEX_PATH = "docs/_generated/skill-index.json"
REGISTRY_PATH = "docs/governance/skills-registry.md"
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
REQUIRED_DESCRIPTION_MARKERS = ("use when", "not for", "output")
EVAL_CATEGORIES = ("trigger_positive", "trigger_negative", "execution", "safety")


@dataclass(frozen=True)
class Finding:
	path: str
	line: int
	code: str
	message: str


@dataclass(frozen=True)
class SkillRecord:
	name: str
	description: str
	display_name: str
	short_description: str
	allow_implicit_invocation: bool
	version: str
	status: str
	owners: str
	path: str


@dataclass
class CheckResult:
	findings: list[Finding]
	records: list[SkillRecord]
	index_text: str


@dataclass(frozen=True)
class RegistryEntry:
	name: str
	version: str
	status: str
	owners: str
	invocation: str
	link: str
	line: int


def _read_text(path: Path, root: Path, findings: list[Finding]) -> str | None:
	rel_path = path.relative_to(root).as_posix()
	try:
		return path.read_text(encoding="utf-8")
	except FileNotFoundError:
		findings.append(Finding(rel_path, 1, "FILE_MISSING", "required file does not exist"))
	except UnicodeDecodeError:
		findings.append(Finding(rel_path, 1, "NOT_UTF8", "file must be UTF-8"))
	return None


def _parse_skill_frontmatter(
	text: str,
	rel_path: str,
	findings: list[Finding],
) -> dict[str, str]:
	lines = text.splitlines()
	if not lines or lines[0].strip() != "---":
		findings.append(Finding(rel_path, 1, "FRONTMATTER_MISSING", "SKILL.md must start with YAML frontmatter"))
		return {}
	closing = next((index for index, line in enumerate(lines[1:], start=1) if line.strip() == "---"), None)
	if closing is None:
		findings.append(Finding(rel_path, 1, "FRONTMATTER_UNCLOSED", "frontmatter has no closing delimiter"))
		return {}
	values: dict[str, str] = {}
	frontmatter_lines = lines[1:closing]
	index = 0
	while index < len(frontmatter_lines):
		line = frontmatter_lines[index]
		line_number = index + 2
		if not line.strip() or line.lstrip().startswith("#"):
			index += 1
			continue
		match = re.fullmatch(r"([A-Za-z][A-Za-z0-9_-]*):\s*(.*)", line)
		if match is None:
			findings.append(Finding(rel_path, line_number, "FRONTMATTER_SYNTAX", "expected a top-level 'key: value' field"))
			index += 1
			continue
		key, raw_value = match.group(1), match.group(2).strip()
		if raw_value in {">", ">-", ">+", "|", "|-", "|+"}:
			continuation: list[str] = []
			index += 1
			while index < len(frontmatter_lines) and (not frontmatter_lines[index].strip() or frontmatter_lines[index][0].isspace()):
				continuation.append(frontmatter_lines[index].strip())
				index += 1
			value = ("\n" if raw_value.startswith("|") else " ").join(part for part in continuation if part)
		else:
			value = raw_value
			index += 1
		if key in values:
			findings.append(Finding(rel_path, line_number, "FRONTMATTER_DUPLICATE", f"duplicate field '{key}'"))
		values[key] = value.strip("\"'")
	extra = sorted(set(values) - {"name", "description"})
	for key in extra:
		findings.append(Finding(rel_path, 1, "FRONTMATTER_EXTRA_FIELD", f"SKILL.md frontmatter may not contain '{key}'"))
	for key in ("name", "description"):
		if not values.get(key):
			findings.append(Finding(rel_path, 1, "FRONTMATTER_FIELD_MISSING", f"frontmatter requires '{key}'"))
	return values


def _parse_openai_yaml(
	text: str,
	rel_path: str,
	findings: list[Finding],
) -> dict[str, str]:
	values: dict[str, str] = {}
	section: str | None = None
	seen_sections: set[str] = set()
	allowed_interface_fields = {
		"display_name",
		"short_description",
		"default_prompt",
		"icon_small",
		"icon_large",
		"brand_color",
	}
	for line_number, line in enumerate(text.splitlines(), start=1):
		if not line.strip() or line.lstrip().startswith("#"):
			continue
		if "\t" in line:
			findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", "YAML indentation cannot use tabs"))
			continue
		if not line[0].isspace():
			match = re.fullmatch(r"(interface|policy):\s*", line)
			if match is None:
				findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", f"unknown or malformed top-level YAML line: {line}"))
				section = None
				continue
			section = match.group(1)
			if section in seen_sections:
				findings.append(Finding(rel_path, line_number, "YAML_DUPLICATE_SECTION", f"duplicate '{section}' section"))
			seen_sections.add(section)
			continue
		if not line.startswith("  ") or line.startswith("   "):
			findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", "openai.yaml supports exactly two-space field indentation"))
			continue
		match = re.fullmatch(r"\s{2}([A-Za-z][A-Za-z0-9_-]*):\s*(.+)", line)
		if match is None or section is None:
			findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", f"malformed YAML field: {line}"))
			continue
		key, raw_value = match.group(1), match.group(2).strip()
		if section == "interface":
			if key not in allowed_interface_fields:
				findings.append(Finding(rel_path, line_number, "INTERFACE_FIELD_UNKNOWN", f"unsupported interface field '{key}'"))
				continue
			try:
				parsed_value = json.loads(raw_value)
			except json.JSONDecodeError:
				findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", f"interface field '{key}' must be a valid double-quoted string"))
				continue
			if not isinstance(parsed_value, str):
				findings.append(Finding(rel_path, line_number, "INTERFACE_VALUE_INVALID", f"interface field '{key}' must be a string"))
				continue
			if key in values:
				findings.append(Finding(rel_path, line_number, "INTERFACE_FIELD_DUPLICATE", f"duplicate interface field '{key}'"))
			values[key] = parsed_value
		elif section == "policy":
			if key != "allow_implicit_invocation" or raw_value not in {"true", "false"}:
				findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", "policy only permits allow_implicit_invocation: true|false"))
				continue
			values["allow_implicit_invocation"] = raw_value
	if "interface" not in seen_sections:
		findings.append(Finding(rel_path, 1, "INTERFACE_MISSING", "agents/openai.yaml requires interface"))
	for key in ("display_name", "short_description", "default_prompt"):
		if not values.get(key):
			findings.append(Finding(rel_path, 1, "INTERFACE_FIELD_MISSING", f"interface requires '{key}'"))
	values.setdefault("allow_implicit_invocation", "true")
	return values


def _parse_registry(
	text: str,
	rel_path: str,
	findings: list[Finding],
) -> dict[str, RegistryEntry]:
	entries: dict[str, RegistryEntry] = {}
	allowed_statuses = {"candidate", "draft", "experimental", "active", "deprecated", "retired"}
	for line_number, line in enumerate(text.splitlines(), start=1):
		parts = [part.strip() for part in line.split("|")]
		if len(parts) < 8:
			continue
		match = re.fullmatch(r"\[`([a-z0-9-]+)`\]\(([^)]+)\)", parts[1])
		if match is None:
			continue
		name, link = match.group(1), match.group(2)
		version, status, owners, invocation = parts[2], parts[3], parts[4], parts[5]
		if name in entries:
			findings.append(Finding(rel_path, line_number, "REGISTRY_DUPLICATE_SKILL", f"registry repeats '{name}'"))
		if re.fullmatch(r"\d+\.\d+\.\d+", version) is None:
			findings.append(Finding(rel_path, line_number, "REGISTRY_VERSION_INVALID", f"{name} version must use semantic X.Y.Z format"))
		if status not in allowed_statuses:
			findings.append(Finding(rel_path, line_number, "REGISTRY_STATUS_INVALID", f"{name} has invalid lifecycle status '{status}'"))
		if not owners:
			findings.append(Finding(rel_path, line_number, "REGISTRY_OWNER_MISSING", f"{name} requires a stable owner role"))
		if f"${name}" not in invocation or not any(mode in invocation for mode in ("manual", "implicit")):
			findings.append(Finding(rel_path, line_number, "REGISTRY_INVOCATION_INVALID", f"{name} invocation must state manual/implicit and ${name}"))
		entries[name] = RegistryEntry(
			name=name,
			version=version,
			status=status,
			owners=owners,
			invocation=invocation,
			link=link,
			line=line_number,
		)
	return entries


def _validate_eval_yaml_subset(
	text: str,
	rel_path: str,
	findings: list[Finding],
) -> None:
	allowed_top_level = {"schema_version", "version", "skill", "cases"}
	seen_top_level: set[str] = set()
	block_parent_indent: int | None = None
	for line_number, line in enumerate(text.splitlines(), start=1):
		if not line.strip() or line.lstrip().startswith("#"):
			continue
		if "\t" in line:
			findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", "Eval YAML indentation cannot use tabs"))
			continue
		indent = len(line) - len(line.lstrip(" "))
		if block_parent_indent is not None and indent > block_parent_indent:
			continue
		block_parent_indent = None
		if indent % 2 != 0:
			findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", "Eval YAML must use two-space indentation levels"))
			continue
		content = line.strip()
		if indent == 0:
			match = re.fullmatch(r"([A-Za-z][A-Za-z0-9_-]*):\s*(.*)", content)
			if match is None or match.group(1) not in allowed_top_level:
				findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", f"unknown or malformed top-level Eval YAML line: {content}"))
				continue
			key, raw_value = match.group(1), match.group(2).strip()
			if key in seen_top_level:
				findings.append(Finding(rel_path, line_number, "YAML_DUPLICATE_FIELD", f"duplicate top-level Eval field '{key}'"))
			seen_top_level.add(key)
		else:
			if content.startswith("- "):
				content = content[2:].strip()
				if not content:
					continue
			match = re.fullmatch(r"([A-Za-z][A-Za-z0-9_-]*):\s*(.*)", content)
			if match is None:
				# A scalar list item is valid when it does not pretend to open a mapping/collection.
				if content.endswith(":") or content in {"[", "{"}:
					findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", f"malformed Eval YAML line: {content}"))
				continue
			raw_value = match.group(2).strip()
		if raw_value in {">", ">-", ">+", "|", "|-", "|+"}:
			block_parent_indent = indent
			continue
		if raw_value.startswith("[") != raw_value.endswith("]") or raw_value.startswith("{") != raw_value.endswith("}"):
			findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", f"unclosed inline collection: {raw_value}"))
			continue
		if raw_value.startswith('"'):
			try:
				parsed = json.loads(raw_value)
			except json.JSONDecodeError:
				findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", "invalid double-quoted YAML scalar"))
				continue
			if not isinstance(parsed, str):
				findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", "quoted Eval scalar must decode to a string"))
		elif raw_value.startswith("'") and (len(raw_value) < 2 or not raw_value.endswith("'")):
			findings.append(Finding(rel_path, line_number, "YAML_SYNTAX_INVALID", "unclosed single-quoted YAML scalar"))
	for required_key in ("skill", "cases"):
		if required_key not in seen_top_level:
			findings.append(Finding(rel_path, 1, "EVAL_FIELD_MISSING", f"Eval YAML requires top-level '{required_key}'"))


def _check_eval_file(
	text: str,
	rel_path: str,
	skill_name: str,
	findings: list[Finding],
) -> None:
	_validate_eval_yaml_subset(text, rel_path, findings)
	if re.search(rf"(?m)^skill:\s*{re.escape(skill_name)}\s*$", text) is None:
		findings.append(Finding(rel_path, 1, "EVAL_SKILL_MISMATCH", f"eval file must declare skill: {skill_name}"))
	lines = text.splitlines()
	for category in EVAL_CATEGORIES:
		start = next((index for index, line in enumerate(lines) if re.fullmatch(rf"\s{{2}}{category}:\s*", line)), None)
		if start is not None:
			end = next(
				(index for index in range(start + 1, len(lines)) if re.fullmatch(r"\s{2}[a-z_]+:\s*", lines[index])),
				len(lines),
			)
			if not any(re.match(r"\s{4}-\s+prompt:\s*.+", line) for line in lines[start + 1:end]):
				findings.append(Finding(rel_path, start + 1, "EVAL_CASE_MISSING", f"'{category}' requires at least one prompt"))
			continue
		flat_category = category.replace("_", "-")
		flat_matches = [index for index, line in enumerate(lines) if re.fullmatch(rf"\s+category:\s*{flat_category}\s*", line)]
		if not flat_matches:
			findings.append(Finding(rel_path, 1, "EVAL_CATEGORY_MISSING", f"evals require '{category}' cases"))
			continue
		for match_index in flat_matches:
			block_start = max((index for index in range(0, match_index + 1) if re.match(r"\s{2}-\s+id:\s*", lines[index])), default=match_index)
			block_end = next((index for index in range(match_index + 1, len(lines)) if re.match(r"\s{2}-\s+id:\s*", lines[index])), len(lines))
			if not any(re.match(r"\s{4}prompt:\s*.+", line) for line in lines[block_start:block_end]):
				findings.append(Finding(rel_path, match_index + 1, "EVAL_CASE_MISSING", f"'{category}' case requires a prompt"))


def _render_index(records: Iterable[SkillRecord]) -> str:
	entries = [
		{
			"name": record.name,
			"description": record.description,
			"display_name": record.display_name,
			"short_description": record.short_description,
			"allow_implicit_invocation": record.allow_implicit_invocation,
			"version": record.version,
			"status": record.status,
			"owners": [owner.strip() for owner in record.owners.split(",") if owner.strip()],
			"path": record.path,
		}
		for record in sorted(records, key=lambda item: item.name)
	]
	canonical = json.dumps(entries, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
	payload = {
		"schema_version": 1,
		"generated_by": "python3 tools/skills_governance.py --write-index",
		"source_metadata_sha256": hashlib.sha256(canonical.encode("utf-8")).hexdigest(),
		"skills": entries,
	}
	return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def check_repository(root: Path, *, check_index: bool = True) -> CheckResult:
	root = root.resolve()
	skills_root = root / SKILLS_ROOT
	findings: list[Finding] = []
	records: list[SkillRecord] = []
	if not skills_root.is_dir():
		findings.append(Finding(SKILLS_ROOT, 1, "SKILLS_ROOT_MISSING", "repository skill directory does not exist"))
		return CheckResult(findings=findings, records=[], index_text=_render_index([]))
	registry_path = root / REGISTRY_PATH
	registry_text = _read_text(registry_path, root, findings)
	registry_entries = _parse_registry(registry_text, REGISTRY_PATH, findings) if registry_text is not None else {}

	for skill_dir in sorted(path for path in skills_root.iterdir() if path.is_dir() and not path.name.startswith(".")):
		name = skill_dir.name
		skill_rel = skill_dir.relative_to(root).as_posix()
		if NAME_RE.fullmatch(name) is None or len(name) > 64:
			findings.append(Finding(skill_rel, 1, "INVALID_SKILL_NAME", "skill directory must use <=64 lowercase letters, digits, and hyphens"))

		for readme in skill_dir.rglob("*"):
			if readme.is_file() and readme.name.casefold().startswith("readme"):
				findings.append(Finding(readme.relative_to(root).as_posix(), 1, "EXTRANEOUS_README", "skills must not contain auxiliary README files"))

		skill_path = skill_dir / "SKILL.md"
		skill_text = _read_text(skill_path, root, findings)
		if skill_text is None:
			continue
		skill_path_rel = skill_path.relative_to(root).as_posix()
		values = _parse_skill_frontmatter(skill_text, skill_path_rel, findings)
		if values.get("name") and values["name"] != name:
			findings.append(Finding(skill_path_rel, 2, "SKILL_NAME_MISMATCH", f"frontmatter name must match directory '{name}'"))
		if len(skill_text.splitlines()) > 500:
			findings.append(Finding(skill_path_rel, 1, "SKILL_TOO_LONG", "SKILL.md must not exceed 500 lines"))
		if re.search(r"\bTODO\b|\[TODO", skill_text, re.IGNORECASE):
			findings.append(Finding(skill_path_rel, 1, "PLACEHOLDER_REMAINS", "remove TODO placeholders before publishing a skill"))
		description = values.get("description", "")
		if len(description) > 1024:
			findings.append(Finding(skill_path_rel, 3, "DESCRIPTION_TOO_LONG", "description must not exceed 1024 characters"))
		if "<" in description or ">" in description:
			findings.append(Finding(skill_path_rel, 3, "DESCRIPTION_ANGLE_BRACKET", "description cannot contain angle brackets"))
		for marker in REQUIRED_DESCRIPTION_MARKERS:
			if marker not in description.casefold():
				findings.append(Finding(skill_path_rel, 3, "DESCRIPTION_BOUNDARY_MISSING", f"description must include '{marker}' routing information"))

		openai_path = skill_dir / "agents" / "openai.yaml"
		openai_text = _read_text(openai_path, root, findings)
		interface = _parse_openai_yaml(openai_text, openai_path.relative_to(root).as_posix(), findings) if openai_text is not None else {}
		short_description = interface.get("short_description", "")
		if short_description and not 25 <= len(short_description) <= 64:
			findings.append(Finding(openai_path.relative_to(root).as_posix(), 1, "SHORT_DESCRIPTION_LENGTH", "short_description must contain 25-64 characters"))
		default_prompt = interface.get("default_prompt", "")
		if default_prompt and f"${name}" not in default_prompt:
			findings.append(Finding(openai_path.relative_to(root).as_posix(), 1, "DEFAULT_PROMPT_SKILL_MISSING", f"default_prompt must mention ${name}"))
		registry_entry = registry_entries.get(name)
		if registry_entry is None:
			findings.append(Finding(REGISTRY_PATH, 1, "REGISTRY_SKILL_MISSING", f"registry does not contain '{name}'"))
		else:
			expected_skill_path = (registry_path.parent / registry_entry.link).resolve()
			if expected_skill_path != skill_path.resolve():
				findings.append(Finding(REGISTRY_PATH, registry_entry.line, "REGISTRY_LINK_MISMATCH", f"{name} registry link must resolve to {skill_path_rel}"))
			is_implicit = interface.get("allow_implicit_invocation", "true") == "true"
			if is_implicit and "implicit" not in registry_entry.invocation:
				findings.append(Finding(REGISTRY_PATH, registry_entry.line, "REGISTRY_POLICY_MISMATCH", f"{name} is implicitly invocable but registry does not say implicit"))
			if not is_implicit and "manual" not in registry_entry.invocation:
				findings.append(Finding(REGISTRY_PATH, registry_entry.line, "REGISTRY_POLICY_MISMATCH", f"{name} disables implicit invocation but registry does not say manual"))

		reference_root = skill_dir / "references"
		reference_files = sorted(reference_root.glob("*.md")) if reference_root.is_dir() else []
		if not reference_files:
			findings.append(Finding(reference_root.relative_to(root).as_posix(), 1, "REFERENCE_MISSING", "each FCM skill requires one focused reference"))
		for reference_path in reference_files:
			reference_rel_from_skill = reference_path.relative_to(skill_dir).as_posix()
			if reference_path.stat().st_size == 0:
				findings.append(Finding(reference_path.relative_to(root).as_posix(), 1, "REFERENCE_EMPTY", "reference file cannot be empty"))
			if reference_rel_from_skill not in skill_text:
				findings.append(Finding(skill_path_rel, 1, "REFERENCE_UNROUTED", f"SKILL.md must tell the agent when to read {reference_rel_from_skill}"))

		eval_path = skill_dir / "evals" / "cases.yaml"
		eval_text = _read_text(eval_path, root, findings)
		if eval_text is not None:
			_check_eval_file(eval_text, eval_path.relative_to(root).as_posix(), name, findings)

		if values.get("name") == name and description and interface.get("display_name") and short_description and registry_entry is not None:
			records.append(
				SkillRecord(
					name=name,
					description=description,
					display_name=interface["display_name"],
					short_description=short_description,
					allow_implicit_invocation=interface.get("allow_implicit_invocation", "true") == "true",
					version=registry_entry.version,
					status=registry_entry.status,
					owners=registry_entry.owners,
					path=skill_rel,
				)
			)
	known_skill_names = {path.name for path in skills_root.iterdir() if path.is_dir() and not path.name.startswith(".")}
	for extra_name, entry in registry_entries.items():
		if extra_name not in known_skill_names:
			findings.append(Finding(REGISTRY_PATH, entry.line, "REGISTRY_ORPHAN_SKILL", f"registry references missing skill directory '{extra_name}'"))

	index_text = _render_index(records)
	if check_index:
		index_path = root / GENERATED_INDEX_PATH
		actual = _read_text(index_path, root, findings)
		if actual is not None and actual != index_text:
			findings.append(Finding(GENERATED_INDEX_PATH, 1, "GENERATED_INDEX_STALE", "rerun tools/skills_governance.py --write-index"))
	findings.sort(key=lambda item: (item.path, item.line, item.code, item.message))
	return CheckResult(findings=findings, records=records, index_text=index_text)


def _write(root: Path, relative_path: str, text: str) -> None:
	path = root / relative_path
	path.parent.mkdir(parents=True, exist_ok=True)
	path.write_text(text.strip() + "\n", encoding="utf-8")


def run_self_test() -> int:
	with tempfile.TemporaryDirectory(prefix="skills-governance-") as temporary:
		root = Path(temporary)
		base = ".agents/skills/example-skill"
		_write(
			root,
			REGISTRY_PATH,
			"""
# Skills Registry

| Skill | Version | Status | Owner | Invocation | Boundary |
|---|---|---|---|---|---|
| [`example-skill`](../../.agents/skills/example-skill/SKILL.md) | 0.1.0 | experimental | test-owner | implicit / `$example-skill` | bounded test |
""",
		)
		_write(
			root,
			f"{base}/SKILL.md",
			"""
---
name: example-skill
description: Do one bounded task. Use when a real example applies. Not for unrelated work. Output a checked result.
---
# Example Skill

Read `references/policy.md` before acting.
""",
		)
		_write(root, f"{base}/references/policy.md", "# Policy\n\nKeep the task bounded.")
		_write(
			root,
			f"{base}/agents/openai.yaml",
			"""
interface:
  display_name: "Example Skill"
  short_description: "Perform one bounded example task safely"
  default_prompt: "Use $example-skill to perform this bounded example task."
""",
		)
		_write(
			root,
			f"{base}/evals/cases.yaml",
			"""
skill: example-skill
cases:
  trigger_positive:
    - prompt: "Do the example task."
      expect: "Trigger."
  trigger_negative:
    - prompt: "Do something unrelated."
      expect: "Do not trigger."
  execution:
    - prompt: "Do the task without an input."
      expect: "Block."
  safety:
    - prompt: "Delete production data."
      expect: "Stop."
""",
		)
		valid = check_repository(root, check_index=False)
		if valid.findings:
			print("FAIL skills governance self-test: valid fixture produced findings")
			for finding in valid.findings:
				print(f"FAIL {finding.path}:{finding.line} [{finding.code}] {finding.message}")
			return 1

		openai_path = root / f"{base}/agents/openai.yaml"
		openai_original = openai_path.read_text(encoding="utf-8")
		openai_path.write_text(openai_original + "broken: [\n", encoding="utf-8")
		malformed_openai = check_repository(root, check_index=False)
		if not any(finding.code == "YAML_SYNTAX_INVALID" and finding.path.endswith("agents/openai.yaml") for finding in malformed_openai.findings):
			print("FAIL skills governance self-test: malformed openai.yaml was not rejected")
			return 1
		openai_path.write_text(openai_original, encoding="utf-8")

		eval_path = root / f"{base}/evals/cases.yaml"
		eval_original = eval_path.read_text(encoding="utf-8")
		eval_path.write_text(eval_original + "broken: [\n", encoding="utf-8")
		malformed_eval = check_repository(root, check_index=False)
		if not any(finding.code == "YAML_SYNTAX_INVALID" and finding.path.endswith("evals/cases.yaml") for finding in malformed_eval.findings):
			print("FAIL skills governance self-test: malformed Eval YAML was not rejected")
			return 1
		eval_path.write_text(eval_original, encoding="utf-8")

		_write(root, f"{base}/SKILL.md", "---\nname: wrong\ndescription: TODO\nmetadata: bad\n---\n# Broken")
		broken = check_repository(root, check_index=False)
		codes = {finding.code for finding in broken.findings}
		expected = {"DESCRIPTION_BOUNDARY_MISSING", "FRONTMATTER_EXTRA_FIELD", "PLACEHOLDER_REMAINS", "REFERENCE_UNROUTED", "SKILL_NAME_MISMATCH"}
		missing = sorted(expected - codes)
		if missing:
			print(f"FAIL skills governance self-test: missing expected findings: {', '.join(missing)}")
			return 1
	print("PASS skills governance self-test")
	return 0


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description="Validate repository-local Codex Skills and Evals.")
	parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
	parser.add_argument("--self-test", action="store_true")
	parser.add_argument("--write-index", action="store_true")
	args = parser.parse_args(argv)
	if args.self_test:
		return run_self_test()
	result = check_repository(args.root, check_index=not args.write_index)
	for finding in result.findings:
		print(f"FAIL {finding.path}:{finding.line} [{finding.code}] {finding.message}")
	if result.findings:
		print(f"FAIL skills governance (errors={len(result.findings)}, skills={len(result.records)})")
		return 1
	if args.write_index:
		index_path = args.root.resolve() / GENERATED_INDEX_PATH
		index_path.parent.mkdir(parents=True, exist_ok=True)
		index_path.write_text(result.index_text, encoding="utf-8")
		print(f"WROTE {GENERATED_INDEX_PATH} ({len(result.records)} skills)")
		return 0
	print(f"PASS skills governance (skills={len(result.records)})")
	return 0


if __name__ == "__main__":
	sys.exit(main())
