#!/usr/bin/env bash
set -euo pipefail

# Convert external SVG assets into project PNGs.
#
# Usage:
#   tools/convert_assets.sh
#
# Optional env vars:
#   SRC_DIR        Path to the Mk III Assets root folder
#   INKSCAPE_BIN   Path to inkscape executable
#
# Notes:
# - Designed for macOS where Inkscape is installed as /Applications/Inkscape.app.
# - This script overwrites existing PNGs in modules/*/assets.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SRC_DIR_DEFAULT="/Users/qinkai/Downloads/Organiser and Accessories - Food Chain Magnate - Mk III/Assets"
SRC_DIR="${SRC_DIR:-$SRC_DIR_DEFAULT}"

INKSCAPE="${INKSCAPE_BIN:-}"
if [[ -z "$INKSCAPE" ]]; then
	if command -v inkscape >/dev/null 2>&1; then
		INKSCAPE="$(command -v inkscape)"
	elif [[ -x "/Applications/Inkscape.app/Contents/MacOS/inkscape" ]]; then
		INKSCAPE="/Applications/Inkscape.app/Contents/MacOS/inkscape"
	fi
fi

die() {
	echo "ERROR: $*" >&2
	exit 1
}

[[ -x "$INKSCAPE" ]] || die "inkscape not found (set INKSCAPE_BIN or install Inkscape)"
[[ -d "$SRC_DIR" ]] || die "SRC_DIR does not exist: $SRC_DIR"

export_png() {
	local src_svg="$1"
	local dst_png="$2"
	local width="$3"

	[[ -f "$src_svg" ]] || die "missing source svg: $src_svg"
	mkdir -p "$(dirname "$dst_png")"

	"$INKSCAPE" "$src_svg" \
		--export-type=png \
		--export-filename="$dst_png" \
		--export-area-drawing \
		--export-background-opacity=0 \
		--export-width="$width" \
		--export-dpi=96 \
		--export-overwrite
}

echo "[convert_assets] START"
echo "[convert_assets] inkscape=$INKSCAPE"
echo "[convert_assets] SRC_DIR=$SRC_DIR"

# === Pieces (base_pieces) ===
# House.svg is wide; we keep alpha and preserve aspect ratio (UI side should draw with aspect-fit).
export_png \
	"$SRC_DIR/Houses/House.svg" \
	"$PROJECT_DIR/modules/base_pieces/assets/map/pieces/house.png" \
	512

# Gate and Fence.svg -> garden_large.png (used later as garden overlay texture).
export_png \
	"$SRC_DIR/Houses/Gate and Fence.svg" \
	"$PROJECT_DIR/modules/base_pieces/assets/map/pieces/garden_large.png" \
	512

# === Product icons (base_products) ===
export_png \
	"$SRC_DIR/Food & Drinks/Burger - Icon.svg" \
	"$PROJECT_DIR/modules/base_products/assets/map/icons/burger.png" \
	256
export_png \
	"$SRC_DIR/Food & Drinks/Pizza - Icon.svg" \
	"$PROJECT_DIR/modules/base_products/assets/map/icons/pizza.png" \
	256
export_png \
	"$SRC_DIR/Food & Drinks/Beer - Icon.svg" \
	"$PROJECT_DIR/modules/base_products/assets/map/icons/beer.png" \
	256
export_png \
	"$SRC_DIR/Food & Drinks/Lemonade - Icon.svg" \
	"$PROJECT_DIR/modules/base_products/assets/map/icons/lemonade.png" \
	256
export_png \
	"$SRC_DIR/Food & Drinks/Softdrink - Icon.svg" \
	"$PROJECT_DIR/modules/base_products/assets/map/icons/soda.png" \
	256

# === Marketing icons (base_marketing) ===
export_png \
	"$SRC_DIR/Marketing/Billboard.svg" \
	"$PROJECT_DIR/modules/base_marketing/assets/map/icons/billboard.png" \
	256
export_png \
	"$SRC_DIR/Marketing/Mail Box.svg" \
	"$PROJECT_DIR/modules/base_marketing/assets/map/icons/mailbox.png" \
	256
export_png \
	"$SRC_DIR/Marketing/Radio - Icon.svg" \
	"$PROJECT_DIR/modules/base_marketing/assets/map/icons/radio.png" \
	256
export_png \
	"$SRC_DIR/Marketing/Aeroplane.svg" \
	"$PROJECT_DIR/modules/base_marketing/assets/map/icons/airplane.png" \
	256

# === Restaurant logos (base_pieces for now) ===
LOGO_DIR="$PROJECT_DIR/modules/base_pieces/assets/map/logos"
export_png \
	"$SRC_DIR/Restaurant Logos/Gluttony Inc Burgers.svg" \
	"$LOGO_DIR/gluttony_inc_burgers.png" \
	512
export_png \
	"$SRC_DIR/Restaurant Logos/Santa Maria Pizza.svg" \
	"$LOGO_DIR/santa_maria_pizza.png" \
	512
export_png \
	"$SRC_DIR/Restaurant Logos/Xango Blues Bar.svg" \
	"$LOGO_DIR/xango_blues_bar.png" \
	512
export_png \
	"$SRC_DIR/Restaurant Logos/Goldem Duck Diner.svg" \
	"$LOGO_DIR/golden_duck_diner.png" \
	512
export_png \
	"$SRC_DIR/Restaurant Logos/Fried Geese & Donkey.svg" \
	"$LOGO_DIR/fried_geese_donkey.png" \
	512

echo "[convert_assets] DONE"
