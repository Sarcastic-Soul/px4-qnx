#!/usr/bin/env bash
# Render every codelab (codelab/<id>/<id>.md) to HTML with QNX's claat fork
# and place it in docs/codelab-site/<id>/ for GitHub Pages (main, /docs).
# Site root: https://sarcastic-soul.github.io/px4-qnx/ (docs/index.html).
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
mkdir -p "$OUT"

for md in "$DIR"/*/*.md; do
    id="$(basename "$md" .md)"
    [ "$(basename "$(dirname "$md")")" = "$id" ] || continue
    rm -rf "${OUT:?}/$id"
    "$CLAAT" export -o "$OUT" "$md"
    sed -i "s#\"\.\./js/#\"$ASSETS/#g" "$OUT/$id/index.html"
    echo "codelab written to $OUT/$id/index.html"
done

# Old links to .../codelab-site/ go to the site's landing page.
cat > "$OUT/index.html" <<'EOF'
<!doctype html>
<meta charset="utf-8">
<title>PX4 on QNX codelabs</title>
<meta http-equiv="refresh" content="0; url=../#codelabs">
<a href="../#codelabs">Codelabs</a>
EOF
touch "$DIR/../docs/.nojekyll"
