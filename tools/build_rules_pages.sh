#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "$(uname -s)" != "Darwin" ]]; then
	echo "[build_rules_pages] FAIL this tool requires macOS (PDFKit)." >&2
	exit 2
fi

WIDTH="1600"
FORCE_FLAG=""
for a in "$@"; do
	if [[ "$a" == "--force" ]]; then
		FORCE_FLAG="--force"
	fi
done
if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
	WIDTH="$1"
fi

HOME_DIR="$PROJECT_PATH/.tmp_home"
mkdir -p "$HOME_DIR"

SWIFT_SCRIPT="$SCRIPT_DIR/render_pdf_pages.swift"
if [[ ! -f "$SWIFT_SCRIPT" ]]; then
	echo "[build_rules_pages] FAIL missing $SWIFT_SCRIPT" >&2
	exit 1
fi

BASE_PDF="$PROJECT_PATH/docs/FCM_Rules_EN_v3.pdf"
KETCHUP_PDF="$PROJECT_PATH/docs/FCM_ketchup_Regels_English_web_2.pdf"

OUT_BASE="$PROJECT_PATH/assets/rules/pages/base"
OUT_KETCHUP="$PROJECT_PATH/assets/rules/pages/ketchup"

mkdir -p "$OUT_BASE" "$OUT_KETCHUP"

echo "[build_rules_pages] START width=$WIDTH"

HOME="$HOME_DIR" swift "$SWIFT_SCRIPT" "$BASE_PDF" "$OUT_BASE" --width "$WIDTH" --prefix page_ --pad 3 --format png $FORCE_FLAG --quiet
HOME="$HOME_DIR" swift "$SWIFT_SCRIPT" "$KETCHUP_PDF" "$OUT_KETCHUP" --width "$WIDTH" --prefix page_ --pad 3 --format png $FORCE_FLAG --quiet

echo "[build_rules_pages] DONE out_base=$OUT_BASE out_ketchup=$OUT_KETCHUP"
