#!/usr/bin/env bash
set -o pipefail

ROFI_THEME="$HOME/.config/waybar/rofi/waybar-latte.rasi"
ROFI=(rofi -dmenu -i -theme "$ROFI_THEME")

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Wi-Fi" "$1"
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

status() {
  if ! command -v nmcli >/dev/null 2>&1; then
    json "" "NetworkManager/nmcli не найден" "error"
    return
  fi

  if [[ "$(nmcli radio wifi 2>/dev/null)" != "enabled" ]]; then
    json "" "Wi-Fi выключен" "disconnected"
    return
  fi

  local iface
  iface=$(nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2 == "wifi" {print $1; exit}')

  if [[ -z "$iface" ]]; then
    json "" "Wi-Fi адаптер не найден" "disconnected"
    return
  fi

  local conn ssid signal tooltip
  conn=$(nmcli -g GENERAL.CONNECTION device show "$iface" 2>/dev/null | head -n1)

  if [[ -n "$conn" && "$conn" != "--" ]]; then
    ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | sed -n 's/^yes://p' | head -n1)
    ssid="${ssid//\\:/:}"
    [[ -z "$ssid" ]] && ssid="$conn"

    signal=$(nmcli -t -f IN-USE,SIGNAL dev wifi 2>/dev/null | sed -n 's/^\*://p' | head -n1)

    tooltip="Подключено: $ssid"
    [[ -n "$signal" ]] && tooltip+=$'\n'"Сигнал: ${signal}%"

    json "" "$tooltip" "connected"
  else
    json "" "Wi-Fi включён, подключение отсутствует" "disconnected"
  fi
}

connect_ssid() {
  local ssid="$1"

  if timeout 8 nmcli device wifi connect "$ssid" >/dev/null 2>&1; then
    notify "Подключено к $ssid"
    return
  fi

  local pass
  pass=$(printf '' | "${ROFI[@]}" -password -p "Пароль для $ssid") || return
  [[ -z "$pass" ]] && return

  if timeout 12 nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1; then
    notify "Подключено к $ssid"
  else
    notify "Не удалось подключиться к $ssid"
  fi
}

menu() {
  if ! command -v nmcli >/dev/null 2>&1; then
    notify "Нужен NetworkManager/nmcli"
    return
  fi

  if [[ "$(nmcli radio wifi 2>/dev/null)" != "enabled" ]]; then
    local choice
    choice=$(printf 'Включить Wi-Fi\n' | "${ROFI[@]}" -p "Wi-Fi") || return

    if [[ "$choice" == "Включить Wi-Fi" ]]; then
      nmcli radio wifi on
      notify "Wi-Fi включён"
    fi

    return
  fi

  declare -A network_ssids
  local options=("Выключить Wi-Fi" "Обновить список сетей")

  while IFS= read -r raw; do
    [[ -z "$raw" ]] && continue
    local name="${raw//\\:/:}"
    options+=("Сохранено: $name")
  done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null | sed -n 's/:wifi$//p')

  nmcli dev wifi rescan >/dev/null 2>&1 || true
  sleep 0.6

  while IFS= read -r raw; do
    [[ -z "$raw" || "$raw" == "--" ]] && continue

    local ssid="${raw//\\:/:}"
    local line="Сеть: $ssid"

    network_ssids["$line"]="$ssid"
    options+=("$line")
  done < <(nmcli -t -f SSID dev wifi 2>/dev/null | sort -u)

  local choice
  choice=$(printf '%s\n' "${options[@]}" | "${ROFI[@]}" -p "Wi-Fi") || return

  case "$choice" in
    "Выключить Wi-Fi")
      nmcli radio wifi off
      notify "Wi-Fi выключен"
      ;;

    "Обновить список сетей")
      exec "$0" menu
      ;;

    "Сохранено: "*)
      local name="${choice#Сохранено: }"

      if nmcli connection up "$name" >/dev/null 2>&1; then
        notify "Подключено: $name"
      else
        notify "Не удалось подключить: $name"
      fi
      ;;

    "Сеть: "*)
      local ssid="${network_ssids[$choice]}"
      [[ -n "$ssid" ]] && connect_ssid "$ssid"
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