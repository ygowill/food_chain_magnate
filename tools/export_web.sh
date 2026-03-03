#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  tools/export_web.sh [--preset Web] [--out build/client/web/index.html] [--install-templates] [--version <ver>]

Notes:
  - Uses a project-local HOME (`.tmp_home/`) to avoid writing to your real user directory.
  - Requires Godot export templates installed for your Godot version.
  - `--install-templates` downloads official export templates (requires network access).
  - Version override:
      - Pass `--version <ver>`, or set env `FCM_BUILD_VERSION=<ver>`.
      - The script temporarily patches `project.godot` (`application/config/version`) for this export,
        then restores it afterwards.
EOF
}

PRESET="Web"
OUT="build/client/web/index.html"
INSTALL_TEMPLATES=0
VERSION_OVERRIDE="${FCM_BUILD_VERSION:-}"

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--preset)
			PRESET="${2:-}"
			shift 2
			;;
		--out)
			OUT="${2:-}"
			shift 2
			;;
		--install-templates)
			INSTALL_TEMPLATES=1
			shift
			;;
		--version)
			VERSION_OVERRIDE="${2:-}"
			shift 2
			;;
		*)
			echo "Unknown arg: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$PROJECT_PATH/.tmp_home" "$PROJECT_PATH/.godot"
mkdir -p "$(dirname "$PROJECT_PATH/$OUT")"

LOG_FILE="$PROJECT_PATH/.godot/ExportWeb.log"
: > "$LOG_FILE"

HOME_DIR="$PROJECT_PATH/.tmp_home"

PROJECT_GODOT="$PROJECT_PATH/project.godot"
if [[ -n "${VERSION_OVERRIDE}" ]]; then
	if [[ "${VERSION_OVERRIDE}" == *$'\n'* || "${VERSION_OVERRIDE}" == *$'\r'* || "${VERSION_OVERRIDE}" == *'"'* ]]; then
		echo "[ExportWeb] FAIL invalid version (contains newline/CR/quote): ${VERSION_OVERRIDE}" >&2
		exit 2
	fi
	if [[ ! -f "${PROJECT_GODOT}" ]]; then
		echo "[ExportWeb] FAIL missing project.godot at: ${PROJECT_GODOT}" >&2
		exit 2
	fi

	backup="$PROJECT_PATH/.godot/_project.godot.before_export_web"
	tmp="$PROJECT_PATH/.godot/_project.godot.tmp"
	cp "$PROJECT_GODOT" "$backup"
	cleanup_version_override() {
		if [[ -f "$backup" ]]; then
			mv "$backup" "$PROJECT_GODOT"
		fi
		rm -f "$tmp"
	}
	trap cleanup_version_override EXIT

	awk -v ver="${VERSION_OVERRIDE}" '
		BEGIN { in_app = 0; replaced = 0 }
		/^\[application\]$/ { in_app = 1; print; next }
		/^\[/ { in_app = 0 }
		{
			if (in_app && $0 ~ /^config\/version=/) {
				print "config/version=\"" ver "\""
				replaced = 1
				next
			}
			print
		}
		END { if (!replaced) exit 3 }
	' "$PROJECT_GODOT" > "$tmp"
	mv "$tmp" "$PROJECT_GODOT"
	echo "[ExportWeb] INFO override application/config/version -> ${VERSION_OVERRIDE}"
fi

godot_version_raw="$(godot --version 2>/dev/null | head -n 1 || true)"
godot_version=""
if [[ "$godot_version_raw" =~ ([0-9]+\.[0-9]+\.[0-9]+) ]]; then
	godot_version="${BASH_REMATCH[1]}"
fi
if [[ -z "${godot_version}" ]]; then
	echo "[ExportWeb] FAIL unable to parse Godot version from: ${godot_version_raw}" >&2
	exit 2
fi

template_dir=""
if [[ "$(uname -s)" == "Darwin" ]]; then
	template_dir="$HOME_DIR/Library/Application Support/Godot/export_templates/${godot_version}.stable"
else
	template_dir="$HOME_DIR/.local/share/godot/export_templates/${godot_version}.stable"
fi

debug_tpl="${template_dir}/web_nothreads_debug.zip"
release_tpl="${template_dir}/web_nothreads_release.zip"

if [[ "${INSTALL_TEMPLATES}" -eq 1 ]]; then
	if ! command -v curl >/dev/null 2>&1; then
		echo "[ExportWeb] FAIL curl not found; cannot install templates" >&2
		exit 2
	fi
	if ! command -v unzip >/dev/null 2>&1; then
		echo "[ExportWeb] FAIL unzip not found; cannot install templates" >&2
		exit 2
	fi

	mkdir -p "${template_dir}"
	tmp_tpz="${PROJECT_PATH}/.godot/_export_templates.tpz"
	tag="${godot_version}-stable"
	url="https://github.com/godotengine/godot/releases/download/${tag}/Godot_v${tag}_export_templates.tpz"
	echo "[ExportWeb] INFO downloading export templates: ${url}"
	curl -fL --retry 3 -o "${tmp_tpz}" "${url}"

	rm -rf "${PROJECT_PATH}/.godot/_export_templates_unpack"
	mkdir -p "${PROJECT_PATH}/.godot/_export_templates_unpack"
	unzip -q "${tmp_tpz}" -d "${PROJECT_PATH}/.godot/_export_templates_unpack"
	mv "${PROJECT_PATH}/.godot/_export_templates_unpack/templates/"* "${template_dir}/"
	rm -rf "${PROJECT_PATH}/.godot/_export_templates_unpack" "${tmp_tpz}"
fi

if [[ ! -f "${debug_tpl}" || ! -f "${release_tpl}" ]]; then
	echo "[ExportWeb] FAIL missing export templates for Web (nothreads)." >&2
	echo "[ExportWeb] Expected:" >&2
	echo "[ExportWeb] - ${debug_tpl}" >&2
	echo "[ExportWeb] - ${release_tpl}" >&2
	echo "[ExportWeb] Fix:" >&2
	echo "[ExportWeb] - Install export templates in Godot editor, or rerun with --install-templates" >&2
	exit 2
fi

echo "[ExportWeb] START preset=${PRESET} out=${OUT}"
echo "[ExportWeb] LOG=${LOG_FILE}"

HOME="$HOME_DIR" godot --headless \
	--log-file "$LOG_FILE" \
	--path "$PROJECT_PATH" \
	--export-release "$PRESET" "$OUT"

echo "[ExportWeb] PASS"
