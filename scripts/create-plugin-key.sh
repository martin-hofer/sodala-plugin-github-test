#!/bin/bash
# Legt den Signaturschlüssel eines Plugins an (F166, ADR-019).
#
#   scripts/create-plugin-key.sh <plugin-id>
#
# Schreibt ~/.config/sodala/plugin-keys/<id>.pem (P-256, nur für dich lesbar) und
# überschreibt nie einen vorhandenen Schlüssel: Sodala nimmt Updates nur mit dem
# Schlüssel an, mit dem das Plugin installiert wurde. Geht er verloren, müssen alle
# Nutzer das Plugin einmal neu aus der Adresse installieren.
set -euo pipefail

ID="${1:?Plugin-ID fehlt}"
# Wie PluginManifest::isValidId.
if ! [[ "$ID" =~ ^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+(-[a-z0-9]+)*)*$ ]] || [ ${#ID} -lt 3 ] || [ ${#ID} -gt 64 ]; then
    echo "Fehler: \"$ID\" ist keine Plugin-ID (z. B. com.firma.plugin)." >&2
    exit 1
fi

OPENSSL=openssl
[ -x /opt/homebrew/bin/openssl ] && OPENSSL=/opt/homebrew/bin/openssl
for tool in "$OPENSSL" python3; do
    command -v "$tool" > /dev/null || { echo "Fehler: $tool fehlt." >&2; exit 1; }
done

DIR="$HOME/.config/sodala/plugin-keys"
KEY="$DIR/$ID.pem"
if [ -e "$KEY" ]; then
    echo "Fehler: $KEY gibt es schon. Ein neuer Schlüssel würde Updates für alle Nutzer abschneiden." >&2
    exit 1
fi

umask 077
mkdir -p "$DIR"
"$OPENSSL" ecparam -name prime256v1 -genkey -noout -out "$KEY"
FINGERPRINT=$("$OPENSSL" pkey -in "$KEY" -pubout -outform DER \
    | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest()[:16])')

cat <<EOF
Schlüssel angelegt: $KEY
Fingerabdruck:      $FINGERPRINT

1. Sichern: Lege eine Kopie der Datei in den Passwort-Manager des Teams.

2. Für eine CI-Pipeline (GitLab: Settings > CI/CD > Variables, "Protected" und
   "Masked"; GitHub: Settings > Secrets) die Variable SODALA_PLUGIN_SIGNING_KEY
   anlegen. Ihren Wert (eine Zeile) legt dieser Befehl in die Zwischenablage:

     $OPENSSL base64 -A -in "$KEY" | pbcopy

3. Veröffentlichen: scripts/release-plugin.sh <plugin-ordner> [--publish]
EOF
