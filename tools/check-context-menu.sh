#!/usr/bin/env bash
# Compare context menu ids referenced by Zen-context-menu/chrome.css against
# the current Zen source (and the Firefox release Zen is built on).
# Prints ids the mod references that no longer exist, and ids in the browser's
# context menus that the mod does not reference yet.
#
# Usage: tools/check-context-menu.sh [zen-git-ref]   (default: dev)
set -euo pipefail
REF="${1:-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CSS="$ROOT/Zen-context-menu/chrome.css"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

git clone -q --depth 1 --branch "$REF" https://github.com/zen-browser/desktop.git "$WORK/zen"
FF_VER="$(grep -o '"version": *"[0-9.]*"' "$WORK/zen/surfer.json" | head -1 | grep -o '[0-9.]*')"
FF_TAG="FIREFOX_${FF_VER//./_}_RELEASE"
ZEN_VER="$(grep -o '"displayVersion": *"[^"]*"' "$WORK/zen/surfer.json" | head -1 | cut -d'"' -f4)"
echo "Zen $ZEN_VER (ref $REF) on Firefox $FF_VER ($FF_TAG)"

FF_RAW="https://raw.githubusercontent.com/mozilla-firefox/firefox/$FF_TAG/browser"
curl -sf "$FF_RAW/base/content/main-popupset.inc.xhtml" > "$WORK/popupset.xhtml"
curl -sf "$FF_RAW/base/content/browser-context.inc.xhtml" > "$WORK/context.xhtml"

# tabContextMenu, toolbar-context-menu, contentAreaContextMenu (browser-context.inc.xhtml)
{
  awk '/id="tabContextMenu"/,/^  <\/menupopup>/' "$WORK/popupset.xhtml"
  awk '/id="toolbar-context-menu"/,/^  <\/menupopup>/' "$WORK/popupset.xhtml"
  cat "$WORK/context.xhtml"
} | grep -oE '(^|[ <])id="[^"]*"' | cut -d'"' -f2 > "$WORK/browser-ids.txt"
# Zen inserts its own items from JS / .inc files
grep -rhoE '(^|[ <])id="(context[_-][^"]+|zen-context-menu[^"]*)"' "$WORK/zen/src/zen" "$WORK/zen/src/browser/base/content" \
  --include='*.mjs' --include='*.js' --include='*.inc' --include='*.xhtml' | cut -d'"' -f2 >> "$WORK/browser-ids.txt"
grep -rhoE 'setAttribute\("id", *"(context[_-][^"]+)"' "$WORK/zen/src/zen" --include='*.mjs' | cut -d'"' -f4 >> "$WORK/browser-ids.txt"
sort -u "$WORK/browser-ids.txt" > "$WORK/browser.txt"

grep -oE '#(context[_-][A-Za-z0-9_-]+|toolbar-context-[A-Za-z0-9_-]+|zen-context-menu[A-Za-z0-9_-]*|frame(-sep)?|inspect-separator|spell-[A-Za-z0-9_-]+|fill-login[A-Za-z0-9_-]*|manage-saved-logins|use-relay-mask|passwordmgr-items-separator|toolbarNavigatorItemsMenuSeparator)\b' "$CSS" \
  | sed 's/^#//' | sort -u > "$WORK/mod.txt"

echo; echo "== Referenced by mod but missing from Zen $ZEN_VER =="
comm -23 "$WORK/mod.txt" "$WORK/browser.txt"
echo; echo "== In Zen $ZEN_VER context menus but not referenced by mod =="
comm -13 "$WORK/mod.txt" "$WORK/browser.txt" | grep -vE 'Popup|popup|-sep|separator|Separator|playbackrate-|pdfjs|viewsource-|media-|^context_zen(Folder|Change|Share|Unload|Reorder|Open|Clear|SpaceRouting|LiveFolder|Edit|Delete|Workspaces)' || true
