#!/bin/bash
# Setzt die Version in plugin/plugin.json und in der Anzeige von plugin/index.html.
#
#   scripts/set-version.sh 1.0.1
set -euo pipefail

VERSION="${1:?Version fehlt (z. B. 1.0.1)}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Fehler: \"$VERSION\" hat nicht die Form MAJOR.MINOR.PATCH." >&2
    exit 1
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT/plugin/plugin.json" "$ROOT/plugin/index.html" "$VERSION" <<'PY'
import json, re, sys
manifest_path, html_path, version = sys.argv[1:4]
with open(manifest_path) as f:
    manifest = json.load(f)
manifest["version"] = version
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write("\n")
with open(html_path) as f:
    html = f.read()
html, count = re.subn(r'(<div class="version">)[^<]*(</div>)', r"\g<1>" + version + r"\g<2>", html)
if count != 1:
    sys.exit("Versionsanzeige in index.html nicht gefunden")
with open(html_path, "w") as f:
    f.write(html)
PY
echo "Version $VERSION gesetzt. Veröffentlichen: git commit -am \"v$VERSION\" && git tag v$VERSION && git push --follow-tags"
