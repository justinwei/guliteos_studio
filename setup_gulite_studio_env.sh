#!/usr/bin/env bash
set -Eeuo pipefail

STUDIO_REPO="${GULITE_STUDIO_REPO:-git@gitlab.gurobot.cn:yunxigu/guliteos_studio.git}"
STUDIO_DIR_NAME="${GULITE_STUDIO_DIR:-guliteos_studio}"
INSTALL_DIR="${GULITE_INSTALL_DIR:-$PWD}"
APP_REPO="${GULITE_APP_REPO:-}"
APP_BRANCH="${GULITE_APP_BRANCH:-}"
APP_DIR_NAME="${GULITE_APP_DIR:-}"
ENGINE_REPO="${GULITE_ENGINE_REPO:-git@gitlab.gurobot.cn:yunxigu/gulite_app_engine.git}"
SIMULATOR_REPO="${GULITE_SIMULATOR_REPO:-git@gitlab.gurobot.cn:yunxigu/gulite_simulator.git}"
ENGINE_BRANCH="${GULITE_ENGINE_BRANCH:-}"
SIMULATOR_BRANCH="${GULITE_SIMULATOR_BRANCH:-SDL2_Support}"
SIMULATOR_VERSION="${GULITE_SIMULATOR_VERSION:-Gulite_SF_2.0.x_performance_optimize}"
PATCH_REL_PATH="${GULITE_BUILD_ONLY_PATCH:-shell/patch17.x/0001-compile-add-build-only-flag.patch}"
CLONE_REPOS_INPUT="${GULITE_CLONE_REPOS_INPUT:-}"
LAUNCH_COMMAND="${GULITE_LAUNCH_COMMAND:-}"
LAUNCH_TIMEOUT="${GULITE_LAUNCH_TIMEOUT:-25s}"
STRICT_LAUNCH="${GULITE_STRICT_LAUNCH:-0}"

NON_INTERACTIVE=0
ASSUME_YES="${GULITE_ASSUME_YES:-0}"
SKIP_LAUNCH="${GULITE_SKIP_LAUNCH:-0}"
ALLOWED_ENGINE_BRANCHES=(
  "Gulite_SF_1.17.x"
  "Gulite_SF_2.0.x_performance_optimize"
)

usage() {
  cat <<'USAGE'
Usage:
  setup_gulite_studio_env.sh --app-repo <repo> --app-branch <branch> [options]

For curl pipe bash:
  curl -fsSL <url>/setup_gulite_studio_env.sh | \
    GULITE_APP_REPO=git@gitlab.gurobot.cn:yunxigu/guliteapp-ai-alarmclock.git \
    GULITE_APP_BRANCH=feat/tinglibao_v20260422 \
    GULITE_ASSUME_YES=1 \
    bash

Options:
  --install-dir <dir>          Parent directory for guliteos_studio. Default: current directory
  --studio-repo <repo>         Studio git repo URL
  --studio-dir <name>          Studio directory name. Default: guliteos_studio
  --app-repo <repo>            Application git repo URL
  --app-branch <branch>        Application branch name
  --app-dir <name>             Application directory name. Default: derived from repo URL
  --engine-repo <repo>         Engine git repo URL
  --simulator-repo <repo>      Simulator git repo URL
  --engine-branch <name>       Engine branch. Allowed: Gulite_SF_1.17.x or Gulite_SF_2.0.x_performance_optimize
  --simulator-branch <name>    Simulator branch. Default: SDL2_Support
  --simulator-version <name>   Prebuilt simulator version for gulite_studio/tools
  --clone-repos-input <text>   Legacy mode: exact input for shell/clone_repos.sh
  --launch-command <cmd>       Command used to start/check studio
  --skip-launch                Skip studio launch check
  --strict-launch              Fail if no launch command can be detected
  --non-interactive            Do not prompt; require app repo and branch
  -y, --yes                    Confirm without prompting
  -h, --help                   Show this help

Environment variables mirror the options:
  GULITE_APP_REPO, GULITE_APP_BRANCH, GULITE_INSTALL_DIR, GULITE_ASSUME_YES,
  GULITE_SKIP_LAUNCH, GULITE_LAUNCH_COMMAND, GULITE_CLONE_REPOS_INPUT, etc.
USAGE
}

log() {
  printf '[gulite-setup] %s\n' "$*"
}

warn() {
  printf '[gulite-setup] WARN: %s\n' "$*" >&2
}

fatal() {
  printf '[gulite-setup] ERROR: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  while (($#)); do
    case "$1" in
      --install-dir)
        INSTALL_DIR="${2:?missing value for --install-dir}"
        shift 2
        ;;
      --studio-repo)
        STUDIO_REPO="${2:?missing value for --studio-repo}"
        shift 2
        ;;
      --studio-dir)
        STUDIO_DIR_NAME="${2:?missing value for --studio-dir}"
        shift 2
        ;;
      --app-repo)
        APP_REPO="${2:?missing value for --app-repo}"
        shift 2
        ;;
      --app-branch)
        APP_BRANCH="${2:?missing value for --app-branch}"
        shift 2
        ;;
      --app-dir)
        APP_DIR_NAME="${2:?missing value for --app-dir}"
        shift 2
        ;;
      --engine-repo)
        ENGINE_REPO="${2:?missing value for --engine-repo}"
        shift 2
        ;;
      --simulator-repo)
        SIMULATOR_REPO="${2:?missing value for --simulator-repo}"
        shift 2
        ;;
      --engine-branch)
        ENGINE_BRANCH="${2:?missing value for --engine-branch}"
        shift 2
        ;;
      --simulator-branch)
        SIMULATOR_BRANCH="${2:?missing value for --simulator-branch}"
        shift 2
        ;;
      --simulator-version)
        SIMULATOR_VERSION="${2:?missing value for --simulator-version}"
        shift 2
        ;;
      --clone-repos-input)
        CLONE_REPOS_INPUT="${2:?missing value for --clone-repos-input}"
        shift 2
        ;;
      --launch-command)
        LAUNCH_COMMAND="${2:?missing value for --launch-command}"
        shift 2
        ;;
      --skip-launch)
        SKIP_LAUNCH=1
        shift
        ;;
      --strict-launch)
        STRICT_LAUNCH=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      -y|--yes)
        ASSUME_YES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fatal "unknown argument: $1"
        ;;
    esac
  done

  if [[ ! -t 0 ]]; then
    NON_INTERACTIVE=1
  fi
}

prompt_value() {
  local label="$1"
  local current="$2"
  local value

  [[ "$NON_INTERACTIVE" == "0" ]] || printf '%s' "$current"
  [[ "$NON_INTERACTIVE" == "0" ]] || return 0

  if [[ -n "$current" ]]; then
    printf '%s [%s]: ' "$label" "$current" > /dev/tty
  else
    printf '%s: ' "$label" > /dev/tty
  fi

  IFS= read -r value < /dev/tty || true
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$current"
  fi
}

confirm_or_exit() {
  [[ "$ASSUME_YES" == "1" ]] && return 0

  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    fatal "non-interactive install requires --yes or GULITE_ASSUME_YES=1"
  fi

  local answer
  printf 'Continue with this setup? [y/N]: ' > /dev/tty
  IFS= read -r answer < /dev/tty || true
  case "$answer" in
    y|Y|yes|YES)
      ;;
    *)
      fatal "cancelled"
      ;;
  esac
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fatal "required command not found: $1"
}

is_allowed_engine_branch() {
  local branch="$1"
  local allowed
  for allowed in "${ALLOWED_ENGINE_BRANCHES[@]}"; do
    [[ "$branch" == "$allowed" ]] && return 0
  done
  return 1
}

allowed_engine_branches_text() {
  local IFS=", "
  printf '%s' "${ALLOWED_ENGINE_BRANCHES[*]}"
}

validate_engine_branch() {
  [[ -n "$ENGINE_BRANCH" ]] || return 0
  is_allowed_engine_branch "$ENGINE_BRANCH" || fatal "invalid engine branch: $ENGINE_BRANCH; allowed values: $(allowed_engine_branches_text)"
}

derive_repo_dir_name() {
  local repo="$1"
  local name="${repo##*/}"
  name="${name%.git}"
  [[ -n "$name" ]] || fatal "cannot derive app directory name from repo: $repo"
  printf '%s' "$name"
}

is_dir_empty() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  [[ -z "$(find "$dir" -mindepth 1 -maxdepth 1 -print -quit)" ]]
}

validate_inputs() {
  if [[ "$NON_INTERACTIVE" == "0" ]]; then
    APP_REPO="$(prompt_value "Application repository URL" "$APP_REPO")"
    APP_BRANCH="$(prompt_value "Application branch" "$APP_BRANCH")"
  fi

  if [[ -z "$APP_REPO" || -z "$APP_BRANCH" ]]; then
    fatal "non-interactive setup needs GULITE_APP_REPO/--app-repo and GULITE_APP_BRANCH/--app-branch"
  fi

  if [[ -z "$APP_DIR_NAME" ]]; then
    APP_DIR_NAME="$(derive_repo_dir_name "$APP_REPO")"
  fi

  INSTALL_DIR="$(cd "$INSTALL_DIR" 2>/dev/null && pwd || printf '%s' "$INSTALL_DIR")"
}

print_summary() {
  log "Install directory: $INSTALL_DIR"
  log "Studio repo: $STUDIO_REPO"
  log "Studio directory: $STUDIO_DIR_NAME"
  log "App repo: $APP_REPO"
  log "App branch: $APP_BRANCH"
  log "App directory: $APP_DIR_NAME"
  log "Engine repo: $ENGINE_REPO"
  log "Engine choice: ${ENGINE_BRANCH:-manual selection}"
  log "Simulator repo: $SIMULATOR_REPO"
  log "Simulator choice: $SIMULATOR_BRANCH"
  log "Simulator version: $SIMULATOR_VERSION"
  if [[ "$SKIP_LAUNCH" == "1" ]]; then
    log "Launch check: skipped"
  elif [[ -n "$LAUNCH_COMMAND" ]]; then
    log "Launch check command: $LAUNCH_COMMAND"
  else
    log "Launch check command: auto-detect"
  fi
}

clone_studio() {
  mkdir -p "$INSTALL_DIR"
  local studio_dir="$INSTALL_DIR/$STUDIO_DIR_NAME"

  if [[ -d "$studio_dir" && ! -d "$studio_dir/.git" && "$(is_dir_empty "$studio_dir"; echo $?)" != "0" ]]; then
    fatal "$studio_dir already exists and is not an empty git checkout"
  fi

  if [[ -d "$studio_dir/.git" ]]; then
    log "Using existing studio checkout: $studio_dir"
  else
    log "Cloning studio repository"
    git clone "$STUDIO_REPO" "$studio_dir"
  fi
}

clone_app() {
  local studio_dir="$INSTALL_DIR/$STUDIO_DIR_NAME"
  local app_dir="$studio_dir/$APP_DIR_NAME"

  if [[ -d "$app_dir" && ! -d "$app_dir/.git" && "$(is_dir_empty "$app_dir"; echo $?)" != "0" ]]; then
    fatal "$app_dir already exists and is not an empty git checkout"
  fi

  if [[ -d "$app_dir/.git" ]]; then
    log "Using existing application checkout: $app_dir"
  else
    log "Cloning application repository"
    (
      cd "$studio_dir"
      git clone -b "$APP_BRANCH" "$APP_REPO" --recursive "$APP_DIR_NAME"
    )
  fi
}

app_has_build_only_support() {
  local app_dir="$1"
  local file
  for file in "$app_dir/compile/compile.sh" "$app_dir/build/build.js"; do
    if [[ -f "$file" ]] && grep -Eq -- '--build-only|build[ _-]?only|buildOnly|BUILD_ONLY' "$file"; then
      return 0
    fi
  done
  return 1
}

ensure_build_only_patch() {
  local studio_dir="$INSTALL_DIR/$STUDIO_DIR_NAME"
  local app_dir="$studio_dir/$APP_DIR_NAME"
  local patch_file="$studio_dir/$PATCH_REL_PATH"

  if app_has_build_only_support "$app_dir"; then
    log "Application already contains build-only support"
    return 0
  fi

  [[ -f "$patch_file" ]] || fatal "application lacks build-only support and patch is missing: $patch_file"

  log "Applying build-only patch to application"
  if git -C "$app_dir" apply --check "$patch_file"; then
    git -C "$app_dir" apply "$patch_file"
  elif app_has_build_only_support "$app_dir"; then
    log "Build-only support appears to be already applied"
  else
    fatal "cannot apply build-only patch: $patch_file"
  fi

  if ! app_has_build_only_support "$app_dir"; then
    fatal "build-only patch applied, but application still does not expose build-only support"
  fi
}

clone_branch_if_needed() {
  local repo_url="$1"
  local branch="$2"
  local target_dir="$3"
  local name="$4"

  if [[ -d "$target_dir/.git" ]]; then
    log "Using existing $name checkout: $target_dir"
    return 0
  fi

  if [[ -d "$target_dir" && "$(is_dir_empty "$target_dir"; echo $?)" != "0" ]]; then
    fatal "$target_dir already exists and is not an empty git checkout"
  fi

  log "Cloning $name repository"
  git clone -b "$branch" "$repo_url" "$target_dir"
}

require_tty_for_manual_selection() {
  true < /dev/tty > /dev/tty 2>/dev/null || fatal "manual engine selection requires a TTY; set GULITE_ENGINE_BRANCH for non-interactive installs"
}

choose_engine_branch() {
  local choice

  require_tty_for_manual_selection
  printf '[gulite-setup] Select engine branch:\n' > /dev/tty
  printf '  1) %s\n' "${ALLOWED_ENGINE_BRANCHES[0]}" > /dev/tty
  printf '  2) %s\n' "${ALLOWED_ENGINE_BRANCHES[1]}" > /dev/tty
  printf 'Enter number or exact branch: ' > /dev/tty
  IFS= read -r choice < /dev/tty || true

  case "$choice" in
    1)
      ENGINE_BRANCH="${ALLOWED_ENGINE_BRANCHES[0]}"
      ;;
    2)
      ENGINE_BRANCH="${ALLOWED_ENGINE_BRANCHES[1]}"
      ;;
    *)
      if is_allowed_engine_branch "$choice"; then
        ENGINE_BRANCH="$choice"
      else
        fatal "invalid engine branch selection: ${choice:-<empty>}; allowed values: $(allowed_engine_branches_text)"
      fi
      ;;
  esac
}

clone_engine_and_simulator() {
  local studio_dir="$INSTALL_DIR/$STUDIO_DIR_NAME"
  local clone_script="$studio_dir/shell/clone_repos.sh"
  local engine_dir="$studio_dir/gulite_app_engine"
  local simulator_dir="$studio_dir/gulite_simulator"

  [[ -f "$clone_script" ]] || fatal "clone_repos.sh not found: $clone_script"

  if [[ -n "$CLONE_REPOS_INPUT" ]]; then
    fatal "GULITE_CLONE_REPOS_INPUT is no longer supported because engine branch selection is restricted"
  fi

  if [[ -z "$ENGINE_BRANCH" ]]; then
    choose_engine_branch
  fi
  validate_engine_branch
  clone_branch_if_needed "$ENGINE_REPO" "$ENGINE_BRANCH" "$engine_dir" "engine"

  clone_branch_if_needed "$SIMULATOR_REPO" "$SIMULATOR_BRANCH" "$simulator_dir" "simulator"
}

select_simulator_version() {
  local studio_dir="$INSTALL_DIR/$STUDIO_DIR_NAME"
  local switch_script="$studio_dir/shell/switch_simulator.sh"
  local selected_version="$SIMULATOR_VERSION"

  [[ -x "$switch_script" ]] || return 0

  [[ -n "$selected_version" ]] || return 0
  log "Selecting simulator version: $selected_version"
  (
    cd "$studio_dir"
    ./shell/switch_simulator.sh "$selected_version"
  )
}

detect_launch_command() {
  local studio_dir="$1"

  if [[ -x "$studio_dir/bootstrap.sh" ]]; then
    printf './bootstrap.sh --start'
  elif [[ -x "$studio_dir/start.sh" ]]; then
    printf './start.sh'
  elif [[ -x "$studio_dir/studio.sh" ]]; then
    printf './studio.sh'
  elif [[ -x "$studio_dir/run.sh" ]]; then
    printf './run.sh'
  elif [[ -x "$studio_dir/shell/start_studio.sh" ]]; then
    printf './shell/start_studio.sh'
  elif [[ -f "$studio_dir/package.json" ]] && command -v npm >/dev/null 2>&1; then
    printf 'npm start'
  else
    return 1
  fi
}

run_with_timeout() {
  local command_text="$1"
  local studio_dir="$2"
  local status

  if command -v timeout >/dev/null 2>&1; then
    set +e
    (
      cd "$studio_dir"
      timeout "$LAUNCH_TIMEOUT" bash -lc "$command_text"
    )
    status=$?
    set -e
    if [[ "$status" == "124" ]]; then
      log "Studio launch command stayed running for $LAUNCH_TIMEOUT; treating this as a successful start check"
      return 0
    fi
    return "$status"
  fi

  (
    cd "$studio_dir"
    bash -lc "$command_text"
  )
}

verify_studio_http() {
  local studio_dir="$1"
  local config="$studio_dir/config.json"
  local ports port

  [[ -f "$config" ]] || return 1
  command -v node >/dev/null 2>&1 || return 1
  command -v curl >/dev/null 2>&1 || return 1

  ports="$(node -e "const fs=require('fs'); const c=JSON.parse(fs.readFileSync(process.argv[1],'utf8')); console.log([c.studioPort,c.device_serverPort].filter(Boolean).join(' '));" "$config")"
  [[ -n "$ports" ]] || return 1

  for port in $ports; do
    curl -fsS --max-time 5 -I "http://127.0.0.1:$port" >/dev/null || return 1
  done
}

launch_studio_check() {
  local studio_dir="$INSTALL_DIR/$STUDIO_DIR_NAME"
  local command_text="$LAUNCH_COMMAND"
  local status

  if [[ "$SKIP_LAUNCH" == "1" ]]; then
    log "Skipping studio launch check"
    return 0
  fi

  select_simulator_version

  if [[ -z "$command_text" ]]; then
    if ! command_text="$(detect_launch_command "$studio_dir")"; then
      if [[ "$STRICT_LAUNCH" == "1" ]]; then
        fatal "no studio launch command detected; pass --launch-command or set GULITE_LAUNCH_COMMAND"
      fi
      warn "no studio launch command detected; environment setup finished but studio was not started"
      return 0
    fi
  fi

  log "Running studio launch check: $command_text"
  set +e
  run_with_timeout "$command_text" "$studio_dir"
  status=$?
  set -e

  if [[ "$status" != "0" ]]; then
    if verify_studio_http "$studio_dir"; then
      warn "launch command exited with status $status, but Studio HTTP endpoints are reachable"
      return 0
    fi
    fatal "studio launch check failed: $command_text"
  fi

  if [[ "$command_text" == *"bootstrap.sh --start"* ]]; then
    verify_studio_http "$studio_dir" || fatal "studio launch command finished, but Studio HTTP endpoints are not reachable"
    log "Studio HTTP endpoints are reachable"
  fi
}

main() {
  parse_args "$@"
  require_command git
  require_command bash
  require_command grep
  require_command find

  validate_inputs
  validate_engine_branch
  print_summary
  confirm_or_exit

  clone_studio
  clone_app
  ensure_build_only_patch
  clone_engine_and_simulator
  launch_studio_check

  log "Environment setup completed: $INSTALL_DIR/$STUDIO_DIR_NAME"
}

main "$@"
