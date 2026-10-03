#!/bin/bash
# Packt einen Plugin-Ordner als .sodalaplugin (ZIP mit plugin.json in der Wurzel).
#
#   scripts/package-plugin.sh <plugin-ordner> [ausgabe-ordner]
#
# Ausgabe: <ausgabe-ordner>/<id>.sodalaplugin, Standard build/plugins/. Installiert wird
# über Einstellungen > Erweiterungen > Erweiterung installieren…. Symlinks, versteckte
# Dateien und Pfade mit ".." lehnt PluginPackage ab; sie kommen gar nicht erst ins Paket.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:?Plugin-Ordner fehlt}"
OUT="${2:-$REPO/build/plugins}"

[ -f "$SRC/plugin.json" ] || { echo "Kein plugin.json in $SRC" >&2; exit 1; }
if find "$SRC" -type l | grep -q .; then
    echo "Symlinks im Plugin-Ordner sind nicht erlaubt" >&2
    exit 1
fi

ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$SRC/plugin.json")"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
TARGET="$OUT/$ID.sodalaplugin"
rm -f "$TARGET"

# -X ohne Zusatzattribute, -D ohne Verzeichniseinträge: gleicher Inhalt ergibt dasselbe Paket.
(cd "$SRC" && find . -type f ! -name '.*' ! -path '*/.*' | sed 's#^\./##' | LC_ALL=C sort \
    | zip -X -D -q "$TARGET" -@)

echo "$TARGET"
