#!/usr/bin/env bash
# t3-sbx.sh — create a Docker Sandbox for the current folder, ready for T3 Code over SSH.
#
# Usage (run from your project folder) — pick ONE:
#   bash t3-sbx.sh              # sandbox name derived from the folder name
#   bash t3-sbx.sh my-sandbox   # custom sandbox name
#
# Or straight from GitHub, without downloading:
#   curl -fsSL https://raw.githubusercontent.com/lepreem/t3-sbx/main/t3-sbx.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/lepreem/t3-sbx/main/t3-sbx.sh | bash -s -- my-sandbox
#
# Optional env vars:
#   AGENT=claude   agent template to base the sandbox on (default: claude)
#   KIT=...        force a specific T3 kit instead of trying the known names

set -euo pipefail

AGENT="${AGENT:-claude}"
PROJECT_DIR="$(pwd)"

# Sandbox name: argument, or the folder name made SSH/hostname-safe.
if [[ $# -ge 1 ]]; then
  NAME="$1"
else
  NAME="$(basename "$PROJECT_DIR" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//')"
  NAME="${NAME:-t3sbx}"
fi
HOST="${NAME}.sbx"

# The kit has been published under several names; try them in order.
if [[ -n "${KIT:-}" ]]; then
  KITS=("$KIT")
else
  KITS=(
    "docker.io/sbx/t3code-kit:latest"
    "docker.io/sbx/t3code:latest"
    "docker.io/docker/sbx-kit-t3code:latest"
  )
fi

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!  %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. Prerequisites --------------------------------------------------------
say "Checking prerequisites"
command -v sbx >/dev/null 2>&1 || die "sbx not found. Install it first:
    macOS:   brew install docker/tap/sbx
    Windows: winget install Docker.sbx
  then run: sbx login"
command -v ssh >/dev/null 2>&1 || die "ssh client not found."
echo "sbx: $(sbx version 2>/dev/null | head -n1 || echo 'unknown version') (needs 0.37.0+)"
echo "Project folder: $PROJECT_DIR"
echo "Sandbox name:   $NAME  (SSH host: $HOST)"

# --- 2. Create the sandbox ---------------------------------------------------
if sbx ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$NAME"; then
  warn "A sandbox named '$NAME' already exists — reusing it."
else
  say "Creating sandbox '$NAME' with the T3 Code kit"
  CREATED=""
  for k in "${KITS[@]}"; do
    echo "Trying kit: $k"
    if sbx create --name "$NAME" --kit "$k" "$AGENT" "$PROJECT_DIR"; then
      CREATED="$k"; break
    fi
    warn "sbx create failed with that kit."
  done

  if [[ -z "$CREATED" ]]; then
    warn "Non-interactive create didn't work. Falling back to 'sbx run' (interactive)."
    warn "When the agent session opens, type /exit — the sandbox keeps running."
    # Read from the terminal directly so this also works when piped via curl | bash.
    read -r -p "Press Enter to continue..." _ </dev/tty
    sbx run --name "$NAME" --kit "${KITS[0]}" "$AGENT" "$PROJECT_DIR" </dev/tty || true
    sbx ls 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$NAME" \
      || die "Sandbox '$NAME' still doesn't exist. Check 'sbx ls' and the errors above."
    CREATED="${KITS[0]}"
  fi
  echo "Created with kit: $CREATED"
fi

# --- 3. SSH ------------------------------------------------------------------
say "Setting up SSH (safe to repeat)"
sbx setup ssh

say "Testing SSH to $HOST"
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)
ssh "${SSH_OPTS[@]}" "$HOST" 'echo "connected as $(whoami)"' \
  || die "Can't SSH into $HOST. Try 'ssh $HOST' manually to see the error."

# --- 4. Make sure T3 can start inside ---------------------------------------
say "Checking that T3 Code's server can run inside the sandbox"
if ssh "${SSH_OPTS[@]}" "$HOST" 'command -v t3 >/dev/null 2>&1'; then
  echo "t3 is pre-installed — first connection will be fast."
else
  warn "t3 isn't pre-installed. Installing the build toolchain so T3 Code can install it on first connect."
  sbx exec "$NAME" -- sudo apt-get update
  sbx exec "$NAME" -- sudo DEBIAN_FRONTEND=noninteractive apt-get install -y g++ make python3 libatomic1
  sbx exec "$NAME" -- sh -lc 'command -v g++ && command -v make && command -v python3' \
    || die "Toolchain install failed — check the sandbox's network policy."
  warn "Note: this manual install is lost if the sandbox is recreated."
fi

DISK="$(ssh "${SSH_OPTS[@]}" "$HOST" "df -h / | awk 'NR==2 {print \$4}'" 2>/dev/null || echo '?')"
echo "Free disk in sandbox: $DISK"

# --- 5. Where is the project inside? ----------------------------------------
# sbx mounts the project at the same absolute path it has on the host.
# (~/workspace exists too but is an empty folder — don't use it.)
# Require a non-empty directory so we never point T3 at an empty folder.
INNER_DIR="$(ssh "${SSH_OPTS[@]}" "$HOST" "
  for d in '$PROJECT_DIR' \"\$HOME/workspace/$(basename "$PROJECT_DIR")\"; do
    [ -d \"\$d\" ] && [ -n \"\$(ls -A \"\$d\" 2>/dev/null)\" ] && { echo \"\$d\"; exit 0; }
  done" 2>/dev/null || true)"
INNER_DIR="${INNER_DIR:-(not found — run: ssh $HOST, then look around with ls)}"

# --- Done: next steps in T3 Code ---------------------------------------------
B=$'\033[1m'; R=$'\033[0m'

say "Sandbox ready. In T3 Code:"
cat <<EOF

  ${B}1.${R} Settings → Connections → Add environment → SSH
     Host: ${B}$HOST${R}   User: ${B}agent${R}

  ${B}2.${R} Add project on environment ${B}$NAME${R}, paste this path (don't browse):
     ${B}$INNER_DIR${R}

  ${B}3.${R} Verify — ask the agent to run: ${B}whoami; uname -s; pwd${R}
     Expect: ${B}agent${R}, ${B}Linux${R}, the path above. Anything else = not sandboxed.

EOF