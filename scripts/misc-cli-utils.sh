#!/usr/bin/env bash
# Common CLI utility functions for bash scripts
# Source this file in your scripts: source "$(dirname "${BASH_SOURCE[0]}")/misc-cli-utils.sh"
#
# Includes: box/info/success/warn/error/header/countdown_progress, plus section, prompt,
# confirm, run_cmd, skip_step, die, require_cmds, bullet_list.
#
# Idempotent: second source returns immediately (no duplicate definitions).
if [[ -n "${_MISC_CLI_UTILS_LOADED:-}" ]]; then
  [[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0
fi
_MISC_CLI_UTILS_LOADED=1

# Colors for output
RESET='\033[0m'
DIM='\033[2m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
BLUE='\033[34m'
BG_CYAN='\033[46m'
BG_GREEN='\033[42m'
BG_YELLOW='\033[43m'
BG_RED='\033[41m'
BG_BLUE='\033[44m'
BLACK='\033[30m'

# Symbols
CHECKMARK='✓'
CROSS='✗'
ARROW='→'

# Box function - creates a colored box around text
# Usage: box "TEXT" [background_color] [foreground_color]
box() {
  local text="$1"
  local bg="${2:-$BG_CYAN}"
  local fg="${3:-$BLACK}"
  echo -e "${bg}${fg} ${text} ${RESET}"
}

# Info message - displays an informational message with cyan box
# Usage: info "Your message here"
info() {
  echo -e "$(box 'INFO' $BG_CYAN $BLACK) ${CYAN}$1${RESET}"
}

# Success message - displays a success message with green box and checkmark
# Usage: success "Your message here"
# If the message starts with a word prefix (like "DONE"), no checkmark is displayed
success() {
  local message="$1"
  # Check if message starts with a word (letters followed by space or colon)
  if [[ "$message" =~ ^[A-Za-z]+[[:space:]:] ]]; then
    # Message has a word prefix, don't show checkmark
    echo -e "$(box 'DONE' $BG_GREEN $BLACK) ${GREEN}${message}${RESET}"
  else
    # Normal message, show checkmark
    echo -e "$(box 'DONE' $BG_GREEN $BLACK) ${GREEN}${CHECKMARK}${RESET} ${GREEN}${message}${RESET}"
  fi
}

# Warning message - displays a warning message with yellow box
# Usage: warn "Your message here"
warn() {
  echo -e "$(box 'WARN' $BG_YELLOW $BLACK) ${YELLOW}$1${RESET}"
}

# Error message - displays an error message with red box and cross
# Usage: error "Your message here"
# If the message starts with a word prefix (like "ERR"), no cross is displayed
error() {
  local message="$1"
  # Check if message starts with a word (letters followed by space or colon)
  if [[ "$message" =~ ^[A-Za-z]+[[:space:]:] ]]; then
    # Message has a word prefix, don't show cross
    echo -e "$(box 'ERR' $BG_RED $BLACK) ${RED}${message}${RESET}"
  else
    # Normal message, show cross
    echo -e "$(box 'ERR' $BG_RED $BLACK) ${RED}${CROSS}${RESET} ${RED}${message}${RESET}"
  fi
}

# Header function - displays a formatted header with label and description using boxen-style borders
# Usage: header "LABEL" "Description text" [color]
# color options: cyan (default), green, yellow, red, blue
header() {
  local label="$1"
  local description="$2"
  local color="${3:-cyan}"
  
  # Map color names to ANSI codes
  local border_color
  local text_color
  
  case "$color" in
    cyan)
      border_color="$CYAN"
      text_color="$CYAN"
      ;;
    green)
      border_color="$GREEN"
      text_color="$GREEN"
      ;;
    yellow)
      border_color="$YELLOW"
      text_color="$YELLOW"
      ;;
    red)
      border_color="$RED"
      text_color="$RED"
      ;;
    blue)
      border_color="$BLUE"
      text_color="$BLUE"
      ;;
    *)
      border_color="$CYAN"
      text_color="$CYAN"
      ;;
  esac
  
  # Calculate width based on both label and description
  # Format: "╭ LABEL ────────╮" and "│   Description text   │"
  local desc_len=${#description}
  local label_len=${#label}
  local label_line_prefix_len=$((label_len + 4))  # "╭ " + label + " " = label_len + 4
  
  # Width should accommodate:
  # - Label line: "╭ LABEL ────────╮" needs at least label_line_prefix_len + some dashes
  # - Description line: "│   Description text   │" needs description + padding (at least 6 chars)
  # Use the maximum of both, with minimum width of 50
  local min_width_for_label=$((label_line_prefix_len + 20))  # Label + some dashes
  local min_width_for_desc=$((desc_len + 12))  # Description + padding on both sides
  local width=$((min_width_for_label > min_width_for_desc ? min_width_for_label : min_width_for_desc))
  
  # Ensure minimum width of 50
  if [ $width -lt 50 ]; then
    width=50
  fi
  
  # Create header box with rounded corners
  # All lines must be exactly 'width' characters long
  echo ""
  
  # Top border: "╭ LABEL ────────────────────────────╮"
  local label_line="╭ ${label} "
  local label_dashes=$((width - ${#label_line} - 1))  # -1 for the closing "╮"
  if [ $label_dashes -lt 0 ]; then
    label_dashes=0
  fi
  echo -e "${border_color}${label_line}$(printf '─%.0s' $(seq 1 $label_dashes))╮${RESET}"
  
  # Empty line: "│                                    │"
  # Must be exactly width characters: "│" + (width-2) spaces + "│"
  echo -e "${border_color}│$(printf ' %.0s' $(seq 1 $((width - 2))))│${RESET}"
  
  # Description line: "│   Description text            │"
  # Must be exactly width characters: "│" + left_pad spaces + description + right_pad spaces + "│"
  # Total: 1 (│) + left_pad + desc_len + right_pad + 1 (│) = width
  # So: left_pad + desc_len + right_pad = width - 2
  local desc_total_padding=$((width - ${#description} - 2))  # -2 for "│" on both sides
  local desc_left_pad=$((desc_total_padding / 2))
  local desc_right_pad=$((desc_total_padding - desc_left_pad))
  echo -e "${border_color}│$(printf ' %.0s' $(seq 1 $desc_left_pad))${text_color}${description}${border_color}$(printf ' %.0s' $(seq 1 $desc_right_pad))│${RESET}"
  
  # Empty line: "│                                    │"
  # Must be exactly width characters: "│" + (width-2) spaces + "│"
  echo -e "${border_color}│$(printf ' %.0s' $(seq 1 $((width - 2))))│${RESET}"
  
  # Bottom border: "╰──────────────────────────────────╯"
  # Must be exactly width characters: "╰" + (width-2) dashes + "╯"
  echo -e "${border_color}╰$(printf '─%.0s' $(seq 1 $((width - 2))))╯${RESET}"
  echo ""
}

# Countdown progress bar - displays a visual countdown with progress bar
# Usage: countdown_progress [seconds] [label]
# Example: countdown_progress 10 "Refreshing in"
countdown_progress() {
  local total_seconds="${1:-10}"
  local label="${2:-Refreshing in}"
  local bar_width=30
  local current=$total_seconds
  
  while [ $current -gt 0 ]; do
    # Calculate progress percentage (elapsed time / total time)
    # elapsed = total - current, so progress = (total - current) * 100 / total
    local elapsed=$((total_seconds - current))
    local progress=$((elapsed * 100 / total_seconds))
    
    # Calculate filled and empty blocks
    local filled=$((progress * bar_width / 100))
    local empty=$((bar_width - filled))
    
    # Ensure filled doesn't exceed bar_width
    if [ $filled -gt $bar_width ]; then
      filled=$bar_width
      empty=0
    fi
    
    # Build progress bar blocks (without colors first)
    local filled_blocks=""
    local empty_blocks=""
    if [ $filled -gt 0 ]; then
      filled_blocks=$(printf '█%.0s' $(seq 1 $filled))
    fi
    if [ $empty -gt 0 ]; then
      empty_blocks=$(printf '░%.0s' $(seq 1 $empty))
    fi
    
    # Print countdown with progress bar (use \r to overwrite same line)
    # Use echo -e to properly interpret escape codes
    echo -ne "\r${CYAN}${label}${RESET} ${YELLOW}${current}s${RESET} [${GREEN}${filled_blocks}${RESET}${DIM}${empty_blocks}${RESET}] ${DIM}${progress}%${RESET}   "
    
    sleep 1
    current=$((current - 1))
  done
  
  # Clear the line and print completion
  local full_bar=$(printf '█%.0s' $(seq 1 $bar_width))
  echo -e "\r${GREEN}${label}${RESET} ${GREEN}Ready!${RESET} [${GREEN}${full_bar}${RESET}] ${GREEN}100%${RESET}"
}

# --- Interactive helpers (sourced by setup / automation scripts) ---

# True when APIGEE_SETUP_NONINTERACTIVE=1 (skip reads in prompt/confirm; used by apigee-hybrid-aks-setup.sh).
_apigee_setup_noninteractive() {
  [[ "${APIGEE_SETUP_NONINTERACTIVE:-0}" == "1" ]]
}

# Section banner — thin wrapper around header()
# Usage: section "Title" ["description"] [color]
section() {
  local title="$1"
  local desc="${2:-}"
  local color="${3:-cyan}"
  header "$title" "$desc" "$color"
}

# Prompt for a variable name with optional default and hint (bash indirect assignment).
# Usage: prompt VAR_NAME [default] [hint]
# When APIGEE_SETUP_NONINTERACTIVE=1: no TTY read; uses existing value or default; dies if still empty.
prompt() {
  local var_name="$1"
  local default="${2:-}"
  local hint="${3:-}"
  local current="${!var_name-}"
  local use="${current:-$default}"
  local input
  if _apigee_setup_noninteractive; then
    if [[ -n "$use" ]]; then
      printf -v "$var_name" '%s' "$use"
      return 0
    fi
    die "APIGEE_SETUP_NONINTERACTIVE: required variable ${var_name} is unset (no value and no default)."
  fi
  if [[ -n "$hint" ]]; then
    read -r -p "${var_name} [${use}] (${hint}): " input || true
  else
    read -r -p "${var_name} [${use}]: " input || true
  fi
  if [[ -n "$input" ]]; then
    printf -v "$var_name" '%s' "$input"
  elif [[ -z "${!var_name+x}" || -z "${!var_name}" ]]; then
    printf -v "$var_name" '%s' "$default"
  fi
}

# Usage: confirm "message" [default y|n]
confirm() {
  local msg="$1"
  local default="${2:-n}"
  if _apigee_setup_noninteractive; then
    [[ "$default" == "y" ]]
    return $?
  fi
  local yn_hint="y/N"
  [[ "$default" == "y" ]] && yn_hint="Y/n"
  read -r -p "$msg [$yn_hint]: " reply || true
  reply="${reply:-}"
  if [[ -z "$reply" ]]; then
    [[ "$default" == "y" ]]
    return $?
  fi
  [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

# Echo then run a command (for interactive walkthroughs).
run_cmd() {
  echo -e "${DIM}+ $*${RESET}" >&2
  "$@"
}

# Usage: skip_step "Skip X?" — returns 0 if user wants to skip
skip_step() {
  local msg="$1"
  if confirm "$msg" "n"; then
    return 0
  fi
  return 1
}

# Usage: die "message" [exit_code]
die() {
  error "$1"
  exit "${2:-1}"
}

# Usage: require_cmds cmd1 cmd2 ...
require_cmds() {
  local missing=()
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if ((${#missing[@]})); then
    die "Missing required commands: ${missing[*]}"
  fi
}

# Print a short bullet list (no boxes); use for menus.
bullet_list() {
  local line
  for line in "$@"; do
    echo -e "  ${ARROW} ${line}"
  done
}

