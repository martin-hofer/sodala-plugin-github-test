#!/bin/bash
# Veröffentlicht ein Plugin für automatische Updates (F166, ADR-019).
#
#   scripts/release-plugin.sh <plugin-ordner> [--key <pem>] [--base-url <url>] [--notes <text>]
#                             [--publish] [--force-republish] [--dry-run]
#
# Baut das .sodalaplugin über scripts/package-plugin.sh, signiert die Erklärung
# (id, version, sha256) mit dem Schlüssel des Plugins und schreibt
# build/plugins/<id>/latest.json. Vor dem Schreiben des Feeds prüft das Skript die
# eigene Signatur gegen den öffentlichen Schlüssel.
#
# Schlüssel (P-256, angelegt mit scripts/create-plugin-key.sh), in dieser Reihenfolge:
#   --key <pem>                         Datei
#   SODALA_PLUGIN_SIGNING_KEY           Inhalt als PEM oder Base64 der PEM-Datei (CI-Variable)
#   ~/.config/sodala/plugin-keys/<id>.pem
# Sodala merkt sich den Schlüssel bei der Installation aus der Adresse und nimmt
# danach nur Updates mit demselben Schlüssel an.
#
# --base-url: Adresse, unter der das Paket liegt (Standard: unser Update-Server). Für
# Release-Anhänge auf GitHub zum Beispiel https://github.com/<org>/<repo>/releases/download/v1.2.0
#
# --publish lädt nach app.proudcommerce.dev/update/sodala/plugins/<id>/ hoch: erst
# das Paket, dann latest.json (der Feed schaltet die Version live). Eine Version,
# die dort schon liegt, wird nur mit --force-republish ersetzt.
#
# In Sodala: Einstellungen > Erweiterungen > Verwaltung > "Aus Adresse installieren…"
#   https://app.proudcommerce.dev/update/sodala/plugins/<id>/latest.json
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE_HOST="proudcommerce@pc4.proudcommerce.com"
REMOTE_BASE="www/app.proudcommerce.dev/update/sodala/plugins"
PUBLIC_BASE="https://app.proudcommerce.dev/update/sodala/plugins"
# SubjectPublicKeyInfo eines P-256-Schlüssels beginnt immer so (Base64).
P256_PREFIX="MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE"

SRC=""
KEY_FILE=""
BASE_URL=""
NOTES=""
PUBLISH=false
FORCE_REPUBLISH=false
DRY_RUN=false
while [ $# -gt 0 ]; do
    case "$1" in
        --key)              KEY_FILE="$2"; shift 2 ;;
        --base-url)         BASE_URL="${2%/}"; shift 2 ;;
        --notes)            NOTES="$2"; shift 2 ;;
        --publish)          PUBLISH=true; shift ;;
        --force-republish)  FORCE_REPUBLISH=true; shift ;;
        --dry-run)          DRY_RUN=true; shift ;;
        -*)                 echo "Unbekannte Option: $1" >&2; exit 1 ;;
        *)                  SRC="$1"; shift ;;
    esac
done
[ -n "$SRC" ] || { echo "Plugin-Ordner fehlt" >&2; exit 1; }
[ -f "$SRC/plugin.json" ] || { echo "Kein plugin.json in $SRC" >&2; exit 1; }
if [ -n "$BASE_URL" ] && [ "$PUBLISH" = true ]; then
    echo "Fehler: --publish lädt auf unseren Update-Server und passt nicht zu --base-url." >&2
    exit 1
fi

OPENSSL=openssl
[ -x /opt/homebrew/bin/openssl ] && OPENSSL=/opt/homebrew/bin/openssl
for tool in "$OPENSSL" python3 zip; do
    command -v "$tool" > /dev/null || { echo "Fehler: $tool fehlt." >&2; exit 1; }
done
# SHA-256 als Hex, ohne shasum (fehlt in schlanken Linux-Images).
sha256_of() {
    python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
}

read_manifest() {
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$SRC/plugin.json" "$1"
}
ID="$(read_manifest id)"
VERSION="$(read_manifest version)"
# Wie PluginManifest::isValidId. Die ID landet in Pfaden und im SSH-Befehl für --publish.
if ! [[ "$ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+(-[a-z0-9]+)*)*$ ]] || [ ${#ID} -lt 3 ] || [ ${#ID} -gt 64 ]; then
    echo "Fehler: id \"$ID\" in plugin.json ist keine gültige Plugin-ID." >&2
    exit 1
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Fehler: version \"$VERSION\" hat nicht die Form MAJOR.MINOR.PATCH." >&2
    exit 1
fi
[ -n "$BASE_URL" ] || BASE_URL="$PUBLIC_BASE/$ID"
if ! [[ "$BASE_URL" =~ ^https:// ]]; then
    echo "Fehler: --base-url muss mit https:// beginnen." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [ -z "$KEY_FILE" ] && [ -n "${SODALA_PLUGIN_SIGNING_KEY:-}" ]; then
    KEY_FILE="$WORK/key.pem"
    (
        umask 077
        if [[ "$SODALA_PLUGIN_SIGNING_KEY" == -----BEGIN* ]]; then
            printf '%s\n' "$SODALA_PLUGIN_SIGNING_KEY" > "$KEY_FILE"
        else
            printf '%s' "$SODALA_PLUGIN_SIGNING_KEY" | "$OPENSSL" base64 -d -A > "$KEY_FILE"
        fi
    )
    echo "Schlüssel: aus SODALA_PLUGIN_SIGNING_KEY"
fi
[ -n "$KEY_FILE" ] || KEY_FILE="$HOME/.config/sodala/plugin-keys/$ID.pem"
if [ ! -f "$KEY_FILE" ]; then
    echo "Fehler: Schlüssel $KEY_FILE fehlt. Anlegen mit: scripts/create-plugin-key.sh $ID" >&2
    exit 1
fi
[ "$KEY_FILE" = "$WORK/key.pem" ] || echo "Schlüssel: $KEY_FILE"

PUBLIC_DER="$WORK/public.der"
"$OPENSSL" pkey -in "$KEY_FILE" -pubout -outform DER -out "$PUBLIC_DER" 2>/dev/null \
    || { echo "Fehler: $KEY_FILE ist kein lesbarer privater Schlüssel." >&2; exit 1; }
PUBLIC_KEY="$("$OPENSSL" base64 -A -in "$PUBLIC_DER")"
if [[ "$PUBLIC_KEY" != "$P256_PREFIX"* ]]; then
    echo "Fehler: Der Schlüssel ist kein P-256-Schlüssel (prime256v1)." >&2
    exit 1
fi

OUT="$REPO/build/plugins/$ID"
mkdir -p "$OUT"
BUILT="$("$REPO/scripts/package-plugin.sh" "$SRC" "$OUT")"
PACKAGE_NAME="$ID-$VERSION.sodalaplugin"
PACKAGE="$OUT/$PACKAGE_NAME"
mv -f "$BUILT" "$PACKAGE"
SHA256=$(sha256_of "$PACKAGE")

# Die Erklärung ist das, was Sodala als verbindlich liest (PluginSignature).
STATEMENT="$OUT/statement.json"
python3 - "$STATEMENT" "$ID" "$VERSION" "$SHA256" <<'PY'
import json, sys
path, pid, version, sha = sys.argv[1:5]
with open(path, "w") as f:
    json.dump({"format": 1, "id": pid, "version": version, "sha256": sha}, f, separators=(",", ":"))
PY

SIGNATURE="$OUT/statement.sig"
"$OPENSSL" dgst -sha256 -sign "$KEY_FILE" -out "$SIGNATURE" "$STATEMENT"

# Selbstprüfung mit dem öffentlichen Schlüssel, wie Sodala sie macht.
"$OPENSSL" pkey -pubin -inform DER -in "$PUBLIC_DER" -out "$WORK/public.pem"
if ! "$OPENSSL" dgst -sha256 -verify "$WORK/public.pem" -signature "$SIGNATURE" "$STATEMENT" > /dev/null; then
    echo "Fehler: Die eigene Signatur lässt sich nicht prüfen." >&2
    exit 1
fi

FEED="$OUT/latest.json"
python3 - "$FEED" "$ID" "$VERSION" "$BASE_URL/$PACKAGE_NAME" "$SHA256" "$STATEMENT" "$SIGNATURE" \
    "$PUBLIC_KEY" "$NOTES" <<'PY'
import base64, json, sys
path, pid, version, url, sha, statement, sig, key, notes = sys.argv[1:10]
def b64(file):
    with open(file, "rb") as f:
        return base64.b64encode(f.read()).decode()
feed = {"id": pid, "version": version, "url": url, "sha256": sha,
        "statement": b64(statement), "signature": b64(sig), "publicKey": key}
if notes:
    feed["notes"] = notes
with open(path, "w") as f:
    json.dump(feed, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

FINGERPRINT=$(sha256_of "$PUBLIC_DER" | cut -c1-16)
echo "Paket:  $PACKAGE"
echo "Feed:   $FEED"
echo "SHA256: $SHA256"
echo "Schlüssel-Fingerabdruck: $FINGERPRINT"

[ "$PUBLISH" = true ] || exit 0

REMOTE_DIR="$REMOTE_BASE/$ID"
if ssh "$REMOTE_HOST" "test -f \"$REMOTE_DIR/$PACKAGE_NAME\"" 2>/dev/null; then
    if [ "$FORCE_REPUBLISH" != true ]; then
        echo "Fehler: $PACKAGE_NAME liegt schon auf dem Server. Version anheben oder --force-republish." >&2
        exit 1
    fi
    # rsync ersetzt das Paket atomar. Bis der Feed nachzieht, passt dessen Prüfsumme
    # nicht; Sodala installiert dann nichts und versucht es beim nächsten Anlass erneut.
    echo "Warnung: $PACKAGE_NAME wird ersetzt (--force-republish)."
fi

RSYNC_FLAGS=(-av)
if [ "$DRY_RUN" = true ]; then
    RSYNC_FLAGS+=(--dry-run)
    echo "DRY-RUN: kein Upload."
else
    ssh "$REMOTE_HOST" "mkdir -p \"$REMOTE_DIR\""
fi
rsync "${RSYNC_FLAGS[@]}" "$PACKAGE" "$REMOTE_HOST:$REMOTE_DIR/"
rsync "${RSYNC_FLAGS[@]}" "$FEED" "$REMOTE_HOST:$REMOTE_DIR/"
echo "Version $VERSION von $ID ist live: $PUBLIC_BASE/$ID/latest.json"
