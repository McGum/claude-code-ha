#!/usr/bin/env bash
# =============================================================================
# Claude Code for Home Assistant — one-shot setup (core_ssh add-on)
# =============================================================================
# Installs the CLI tools + Claude Code into a PERSISTENT cache and wires an
# auto-restore hook, so everything survives HA / add-on updates. Run it once
# on a fresh Terminal & SSH add-on:
#
#     git clone https://github.com/danbuhler/claude-code-ha.git /config/claude-code-ha
#     bash /config/claude-code-ha/setup.sh
#
# Idempotent — safe to re-run. After it finishes, put your HA long-lived token
# into <config>/.env and open a new terminal. Done.
# =============================================================================
set -euo pipefail

REPO_URL="https://github.com/McGum/claude-code-ha.git"

# --- locate the persistent HA config mount ---------------------------------
if [ -d /homeassistant ]; then HA_CONFIG=/homeassistant
elif [ -d /config ];      then HA_CONFIG=/config
else echo "!! No /homeassistant or /config found — is this the SSH add-on?"; exit 1; fi
DIR="$HA_CONFIG/claude-code-ha"

echo "=== Claude Code HA — setup (config: $HA_CONFIG) ==="

# --- 1) system dependencies -------------------------------------------------
if command -v apk >/dev/null 2>&1; then
    echo "-> installing system packages (apk)…"
    apk add --quiet git jq curl python3 py3-pip py3-websockets 2>/dev/null || true
    command -v npm >/dev/null 2>&1 || apk add --quiet nodejs npm 2>/dev/null || true
fi
if ! command -v npm >/dev/null 2>&1; then
    echo "!! npm not found and could not be installed. Aborting."; exit 1
fi

# --- 2) fetch the repo (CLI tools + CLAUDE.md) if not already present -------
if [ ! -d "$DIR/bin" ]; then
    echo "-> cloning $REPO_URL -> $DIR"
    git clone --depth 1 "$REPO_URL" "$DIR"
fi
chmod +x "$DIR"/bin/* 2>/dev/null || true

# --- 3) ensure bootstrap.sh exists (the persistence brain) ------------------
# Written only if missing, so a customized bootstrap.sh in the repo is kept.
if [ ! -f "$DIR/bootstrap.sh" ]; then
    echo "-> writing bootstrap.sh"
    cat > "$DIR/bootstrap.sh" <<'BOOT'
#!/usr/bin/env bash
# Claude Code for Home Assistant — persistent bootstrap (sourced on login).
CLAUDE_HA_DIR="/homeassistant/claude-code-ha"
CLAUDE_PREFIX="$CLAUDE_HA_DIR/.local"
BIN_DIR="/usr/local/bin"
case ":$PATH:" in
    *":$CLAUDE_PREFIX/bin:"*) : ;;
    *) export PATH="$CLAUDE_PREFIX/bin:$CLAUDE_HA_DIR/bin:$PATH" ;;
esac
for _s in ha-api ha-ws lovelace-sync; do
    if [ -f "$CLAUDE_HA_DIR/bin/$_s" ] && [ ! -e "$BIN_DIR/$_s" ]; then
        ln -sf "$CLAUDE_HA_DIR/bin/$_s" "$BIN_DIR/$_s" 2>/dev/null
    fi
done
command -v jq >/dev/null 2>&1 || { echo "[claude-ha] installing jq..."; apk add --quiet jq 2>/dev/null; }
python3 -c "import websockets" 2>/dev/null || {
    echo "[claude-ha] installing python websockets..."
    pip3 install websockets --break-system-packages --quiet 2>/dev/null || pip3 install websockets --quiet
}
if ! command -v claude >/dev/null 2>&1; then
    echo "[claude-ha] Claude Code not found — installing into $CLAUDE_PREFIX (one-time)…"
    npm install -g --prefix "$CLAUDE_PREFIX" @anthropic-ai/claude-code
fi
BOOT
fi
chmod +x "$DIR/bootstrap.sh"

# --- 4) python websockets (fallback if not covered by apk) -----------------
python3 -c "import websockets" 2>/dev/null || \
    pip3 install websockets --break-system-packages --quiet 2>/dev/null || \
    pip3 install websockets --quiet || true

# --- 5) Claude Code into the persistent /config-backed cache ---------------
echo "-> installing Claude Code into $DIR/.local (persistent cache)…"
npm install -g --prefix "$DIR/.local" @anthropic-ai/claude-code

# --- 6) wire the persistent auto-restore hook (/data survives rebuilds) ----
PROFILE=/data/.bash_profile
[ -d /data ] || mkdir -p /data
[ -e "$PROFILE" ] || touch "$PROFILE"
if ! grep -q "claude-code-ha/bootstrap.sh" "$PROFILE" 2>/dev/null; then
    echo "-> wiring auto-restore hook into $PROFILE"
    cat >> "$PROFILE" <<'HOOK'

# Claude Code for Home Assistant — persistent auto-setup (survives rebuilds)
if [ -f /homeassistant/claude-code-ha/bootstrap.sh ]; then
    source /homeassistant/claude-code-ha/bootstrap.sh
fi
HOOK
fi

# --- 7) CLAUDE.md + .env (never overwrite existing customizations) ---------
[ -f "$HA_CONFIG/CLAUDE.md" ] || cp "$DIR/CLAUDE.md" "$HA_CONFIG/CLAUDE.md"
if [ ! -f "$HA_CONFIG/.env" ] && [ -f "$DIR/.env.example" ]; then
    cp "$DIR/.env.example" "$HA_CONFIG/.env"
    echo "-> created $HA_CONFIG/.env (add your HA token!)"
fi

# --- 8) persist jq + py3-websockets in the add-on config (best effort) -----
# Uses the Supervisor API from inside the add-on; harmless if it fails.
if [ -n "${SUPERVISOR_TOKEN:-}" ]; then
    python3 - <<'PYEOF' 2>/dev/null && echo "-> add-on apks updated (jq, py3-websockets)" || echo "-> (skipped add-on apks update; bootstrap.sh self-heals these anyway)"
import json,urllib.request,os
tok=os.environ["SUPERVISOR_TOKEN"]
def api(p,d=None):
    r=urllib.request.Request("http://supervisor"+p,
        headers={"Authorization":f"Bearer {tok}","Content-Type":"application/json"},
        data=json.dumps(d).encode() if d is not None else None,
        method="POST" if d is not None else "GET")
    return json.load(urllib.request.urlopen(r,timeout=30))
o=dict(api("/addons/self/info")["data"]["options"])
a=list(o.get("apks",[]));
for p in ("py3-websockets","jq"):
    if p not in a: a.append(p)
o["apks"]=a; api("/addons/self/options",{"options":o})
PYEOF
fi

echo
echo "=== Setup complete ==="
echo "  1. Edit $HA_CONFIG/.env  ->  set HA_URL and HA_TOKEN (long-lived token)"
echo "  2. Open a NEW terminal (or run: source /data/.bash_profile)"
echo "  3. Run:  claude"
