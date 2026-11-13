#!/bin/bash
# Renders the App Store header and search-results images from the iPhone screenshots:
#   ./render.sh   (writes ../header-3840x1646.png and ../search-3840x2560.png)
# Needs Google Chrome and network access for the Instrument Sans / Serif Italic web fonts.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
shots="$(cd "$here/../../iPhone 6.3in" && pwd)"
out="$(cd "$here/.." && pwd)"
for t in header search; do
  sed -e "s|TODAY|$shots/01-today.png|; s|JOURNAL|$shots/02-journal.png|; s|ENTRY|$shots/03-entry.png|; s|WRITE|$shots/04-write.png|; s|PHOTOS|$shots/05-photos.png|; s|STATS|$shots/06-stats.png|" "$here/$t.html" > "$here/.$t.filled.html"
done
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
render() { "$chrome" --headless=new --hide-scrollbars --force-device-scale-factor=1 --virtual-time-budget=8000 \
  --allow-file-access-from-files --window-size="$1" --screenshot="$2" "file://$3" 2>/dev/null; }
render 3840,1646 "$out/header-3840x1646.png" "$here/.header.filled.html"
render 3840,2560 "$out/search-3840x2560.png" "$here/.search.filled.html"
rm -f "$here/.header.filled.html" "$here/.search.filled.html"
