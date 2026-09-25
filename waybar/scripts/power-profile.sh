#!/usr/bin/env bash
set -o pipefail

ROFI_THEME="$HOME/.config/waybar/rofi/waybar-latte.rasi"
ROFI=(rofi -dmenu -i -theme "$ROFI_THEME")

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Режим питания" "$1"
  fi
}

esc() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/ }"
  printf '%s' "$s"
}

json() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg text "$1" --arg tooltip "$2" --arg class "$3" '{text:$text, tooltip:$tooltip, class:$class}'
  else
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$(esc "$1")" "$(esc "$2")" "$3"
  fi
}

current_profile() {
  powerprofilesctl get 2>/dev/null | tr -d '[:space:]'
}

profile_label() {
  case "$1" in
    performance)
      echo "Производительность"
      ;;
    balanced)
      echo "Сбалансированный"
      ;;
    power-saver)
      echo "Энергосбережение"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

profile_icon() {
  case "$1" in
    performance)
      echo ""
      ;;
    balanced)
      echo ""
      ;;
    power-saver)
      echo ""
      ;;
    *)
      echo ""
      ;;
  esac
}

status() {
  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    json "" "power-profiles-daemon не найден" "error"
    return
  fi

  local profile
  profile=$(current_profile)
  [[ -z "$profile" ]] && profile="balanced"

  json "$(profile_icon "$profile")" "Режим питания: $(profile_label "$profile")" "$profile"
}

menu() {
  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    notify "power-profiles-daemon не найден"
    return
  fi

  local current
  current=$(current_profile)
  [[ -z "$current" ]] && current="balanced"

  local options=()

  for prof in performance balanced power-saver; do
    local label
    label=$(profile_label "$prof")

    if [[ "$prof" == "$current" ]]; then
      label="* $label"
    fi

    options+=("$label")
  done

  local choice
  choice=$(printf '%s\n' "${options[@]}" | "${ROFI[@]}" -p "Режим питания") || return

  case "$choice" in
    *Производительность*)
      powerprofilesctl set performance
      notify "Производительность"
      ;;
    *Сбалансированный*)
      powerprofilesctl set balanced
      notify "Сбалансированный"
      ;;
    *Энергосбережение*)
      powerprofilesctl set power-saver
      notify "Энергосбережение"
      ;;
  esac
}

case "${1:-status}" in
  status)
    status
    ;;
  menu)
    menu
    ;;
  *)
    echo "Usage: $0 status|menu" >&2
    exit 1
    ;;
esac