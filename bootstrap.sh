#!/usr/bin/env bash
# Claude Code for Home Assistant — persistent bootstrap
# ---------------------------------------------------------------------------
# Sourced from /data/.bash_profile (a symlink into the add-on's persistent
# /data volume) on every login shell.
#
# HA add-on containers are rebuilt on every add-on / OS update, which wipes
# /usr/local, pip packages, apk-installed tools and PATH. But /data and
# /homeassistant (where this repo lives) survive. This script transparently
# restores everything, so `claude` and the ha-* CLIs just work after an
# update — no more manual re-running of install.sh.
#
# It is idempotent and near-silent once everything is already in place.
# ---------------------------------------------------------------------------

CLAUDE_HA_DIR="/homeassistant/claude-code-ha"
CLAUDE_PREFIX="$CLAUDE_HA_DIR/.local"   # persistent npm prefix (survives rebuilds)
BIN_DIR="/usr/local/bin"                # ephemeral, recreated each boot

# --- PATH: persistent npm bin + repo bin (idempotent) ----------------------
case ":$PATH:" in
    *":$CLAUDE_PREFIX/bin:"*) : ;;
    *) export PATH="$CLAUDE_PREFIX/bin:$CLAUDE_HA_DIR/bin:$PATH" ;;
esac

# --- CLI tool symlinks (ha-api / ha-ws / lovelace-sync) --------------------
for _s in ha-api ha-ws lovelace-sync; do
    if [ -f "$CLAUDE_HA_DIR/bin/$_s" ] && [ ! -e "$BIN_DIR/$_s" ]; then
        ln -sf "$CLAUDE_HA_DIR/bin/$_s" "$BIN_DIR/$_s" 2>/dev/null
    fi
done

# --- system deps living in the ephemeral rootfs (reinstalled if missing) ---
# jq        -> used by ha-api
# websockets-> used by ha-ws
# (node/npm come from the add-on base image; see README for the apks option)
command -v jq >/dev/null 2>&1 || { echo "[claude-ha] installing jq..."; apk add --quiet jq 2>/dev/null; }
python3 -c "import websockets" 2>/dev/null || {
    echo "[claude-ha] installing python websockets..."
    pip3 install websockets --break-system-packages --quiet 2>/dev/null || pip3 install websockets --quiet
}

# --- Claude Code: install into the persistent /config-backed prefix --------
# After a rebuild the PATH above already points at the cached copy, so this is
# a no-op. Only the very first run (or a wiped cache) triggers a download.
if ! command -v claude >/dev/null 2>&1; then
    echo "[claude-ha] Claude Code not found — installing into $CLAUDE_PREFIX (one-time)…"
    npm install -g --prefix "$CLAUDE_PREFIX" @anthropic-ai/claude-code
fi
