#!/usr/bin/env bash
# Render the codelab Markdown to HTML with QNX's claat fork and place it in
# docs/codelab-site/ for GitHub Pages (Settings > Pages > main /docs, URL
# .../px4-qnx/codelab-site/).
#
# Needs claat from https://github.com/qnx/tools (cd tools/claat && go install).
# The page's JS/CSS are loaded from the QNX Codelabs site rather than copied,
# because that repo carries no license file.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$DIR/../docs/codelab-site"
CLAAT="${CLAAT:-$(command -v claat || echo "$HOME/go/bin/claat")}"
ASSETS="${CODELAB_ASSETS:-https://qnx.github.io/codelabs/js}"

[ -x "$CLAAT" ] || { echo "claat not found; see header" >&2; exit 1; }
cp "$DIR/../docs/img/timing.png" "$DIR/px4-sih-on-qnx/timing.png"

rm -rf "$OUT/px4-sih-on-qnx"
mkdir -p "$OUT"
"$CLAAT" export -o "$OUT" "$DIR/px4-sih-on-qnx/px4-sih-on-qnx.md"
sed -i "s#\"\.\./js/#\"$ASSETS/#g" "$OUT/px4-sih-on-qnx/index.html"

cat > "$OUT/index.html" <<'EOF'
<!doctype html>
<meta charset="utf-8">
<title>PX4 on QNX codelab</title>
<meta http-equiv="refresh" content="0; url=px4-sih-on-qnx/index.html">
<a href="px4-sih-on-qnx/index.html">Fly PX4 Autopilot on QNX 8.0 in QEMU</a>
EOF
touch "$OUT/.nojekyll"
echo "codelab written to $OUT/px4-sih-on-qnx/index.html"
