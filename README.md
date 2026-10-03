# Sodala-Plugin: GitHub-Test

Test-Plugin für automatische Plugin-Updates aus GitHub-Releases (Sodala F166, ADR-019). Es zeigt in der Seitenleiste nur seine Version; daran sieht man, welches Paket gerade läuft.

## Aufbau

```
plugin/                     Plugin (plugin.json, index.html, icon.svg)
scripts/release-plugin.sh   baut, signiert, schreibt latest.json (Kopie aus dem Sodala-Repo)
scripts/package-plugin.sh   packt das .sodalaplugin (Kopie aus dem Sodala-Repo)
scripts/create-plugin-key.sh legt den Signaturschlüssel an (Kopie aus dem Sodala-Repo)
scripts/set-version.sh      setzt die Version in plugin.json und index.html
.github/workflows/release.yml  veröffentlicht bei einem Tag vX.Y.Z
```

## Einmalig einrichten

1. Schlüssel anlegen: `scripts/create-plugin-key.sh com.proudcommerce.github-test`
   Der Schlüssel liegt danach unter `~/.config/sodala/plugin-keys/` und gehört in den Passwort-Manager des Teams.
2. Secret im Repo anlegen (Settings > Secrets and variables > Actions > New repository secret):
   Name `SODALA_PLUGIN_SIGNING_KEY`, Wert aus
   `openssl base64 -A -in ~/.config/sodala/plugin-keys/com.proudcommerce.github-test.pem`.
   Oder mit der GitHub-CLI:
   `openssl base64 -A -in ~/.config/sodala/plugin-keys/com.proudcommerce.github-test.pem | gh secret set SODALA_PLUGIN_SIGNING_KEY`
3. Das Repo muss öffentlich sein: Sodala lädt Feed und Paket ohne Anmeldung.

## Neue Version veröffentlichen

```bash
scripts/set-version.sh 1.0.1
git commit -am "v1.0.1"
git tag -a v1.0.1 -m "v1.0.1"
git push --follow-tags
```

Der Workflow prüft, dass Tag und `plugin.json` übereinstimmen, signiert, legt das Release an und markiert es als "latest".

## In Sodala installieren

Einstellungen > Erweiterungen > Verwaltung > "Aus Adresse installieren…":

```
https://github.com/<owner>/sodala-plugin-github-test/releases/latest/download/latest.json
```

Sodala merkt sich dabei den Schlüssel und nimmt danach nur Updates an, die mit demselben Schlüssel signiert sind.
