#!/usr/bin/env bash
set -euo pipefail

usage() {
	cat <<'EOF'
Usage:
  tools/build_portal.sh [--skip-godot] [--out build/web]

Assembles the complete web deployment:
  1. Builds Vue Portal (npm run build)
  2. Exports Godot Web build (unless --skip-godot)
  3. Copies Godot export into Vue dist/game/

Options:
  --skip-godot    Skip Godot export (use existing build/client/web/)
  --out <dir>     Output directory (default: build/web)
  --install-templates  Pass through to export_web.sh
EOF
}

SKIP_GODOT=0
OUT_DIR="build/web"
INSTALL_TEMPLATES=""

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			usage
			exit 0
			;;
		--skip-godot)
			SKIP_GODOT=1
			shift
			;;
		--out)
			OUT_DIR="${2:-}"
			shift 2
			;;
		--install-templates)
			INSTALL_TEMPLATES="--install-templates"
			shift
			;;
		*)
			echo "Unknown arg: $1" >&2
			usage >&2
			exit 2
			;;
	esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORTAL_DIR="$PROJECT_ROOT/web/portal"
GODOT_WEB_DIR="$PROJECT_ROOT/build/client/web"

echo "[build_portal] === Step 1: Build Vue Portal ==="

if [[ ! -d "$PORTAL_DIR/node_modules" ]]; then
	echo "[build_portal] Installing dependencies..."
	(cd "$PORTAL_DIR" && npm ci --ignore-scripts)
fi

(cd "$PORTAL_DIR" && npm run build)
echo "[build_portal] Vue build complete."

echo ""
echo "[build_portal] === Step 2: Godot Web Export ==="

if [[ "${SKIP_GODOT}" -eq 0 ]]; then
	"$SCRIPT_DIR/export_web.sh" $INSTALL_TEMPLATES
	echo "[build_portal] Godot export complete."
else
	if [[ ! -d "$GODOT_WEB_DIR" ]]; then
		echo "[build_portal] WARN: --skip-godot but $GODOT_WEB_DIR not found."
		echo "[build_portal] The game/ directory will use the placeholder."
	else
		echo "[build_portal] Skipping Godot export (using existing build)."
	fi
fi

echo ""
echo "[build_portal] === Step 3: Assemble ==="

mkdir -p "$PROJECT_ROOT/$OUT_DIR"
# Copy Vue dist
cp -r "$PORTAL_DIR/dist/"* "$PROJECT_ROOT/$OUT_DIR/"

# Overlay Godot export into game/
if [[ -d "$GODOT_WEB_DIR" ]]; then
	mkdir -p "$PROJECT_ROOT/$OUT_DIR/game"
	cp -r "$GODOT_WEB_DIR/"* "$PROJECT_ROOT/$OUT_DIR/game/"
	echo "[build_portal] Godot files copied to $OUT_DIR/game/"
fi

echo "[build_portal] DONE -> $OUT_DIR/"
