#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/bkochavy/openclaw-build.git"
TARGET_DIR="${OPENCLAW_BUILD_DIR:-${HOME}/.openclaw/workspace/skills/openclaw-build}"
MIN_NODE_MAJOR=18

log() {
  printf "[%s] %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    die "Missing required dependency: ${cmd}. ${hint}"
  fi
}

check_node() {
  require_cmd node "Install Node.js ${MIN_NODE_MAJOR}+ from https://nodejs.org"

  local node_major
  node_major="$(node -p "process.versions.node.split('.')[0]")"
  if [[ -z "${node_major}" ]] || ! [[ "${node_major}" =~ ^[0-9]+$ ]]; then
    die "Unable to determine Node.js version. Expected Node.js ${MIN_NODE_MAJOR}+"
  fi

  if (( node_major < MIN_NODE_MAJOR )); then
    die "Node.js ${MIN_NODE_MAJOR}+ required. Found: $(node -v)"
  fi
}

check_engine_cli() {
  if ! command -v codex >/dev/null 2>&1 && ! command -v claude >/dev/null 2>&1; then
    die "Missing coding engine CLI. Install either 'codex' or 'claude' and ensure it is on PATH."
  fi
}

clone_repo_if_needed() {
  local parent_dir
  parent_dir="$(dirname "${TARGET_DIR}")"
  mkdir -p "${parent_dir}"

  if [[ -d "${TARGET_DIR}/.git" ]]; then
    log "Using existing install at ${TARGET_DIR}"
    return
  fi

  if [[ -e "${TARGET_DIR}" ]]; then
    die "Target path exists but is not a git checkout: ${TARGET_DIR}"
  fi

  require_cmd git "Install Git to clone the repository"
  log "Cloning openclaw-build into ${TARGET_DIR}"
  git clone "${REPO_URL}" "${TARGET_DIR}" >/dev/null
}

run_monitor_setup() {
  local loop_installer="${TARGET_DIR}/loops/install.sh"
  [[ -f "${loop_installer}" ]] || die "Missing loop installer: ${loop_installer}"

  log "Running monitor setup"
  bash "${loop_installer}"
}

main() {
  log "Checking dependencies"
  require_cmd bash "Bash is required to run installers"
  require_cmd openclaw "Install OpenClaw first: curl -fsSL https://openclaw.ai/install.sh | bash"
  require_cmd ralphy "Install ralphy-cli: npm i -g ralphy-cli"
  require_cmd tmux "Install tmux (e.g. brew install tmux or apt install tmux)"
  check_node
  check_engine_cli

  clone_repo_if_needed
  run_monitor_setup

  log "Install complete"
  cat <<DONE

openclaw-build is installed and ready.
Path: ${TARGET_DIR}

Next step:
  Tell your agent: "spec this" or "build me X"
DONE
}

main "$@"
