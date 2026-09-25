#!/usr/bin/env bash
set -o pipefail

ROFI_THEME="$HOME/.config/waybar/rofi/waybar-latte.rasi"
ROFI=(rofi -dmenu -i -theme "$ROFI_THEME")

notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Bluetooth" "$1"
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

parse_devices() {
  awk '/^Device / {
    mac = $2;
    name = $0;
    sub(/^Device [0-9A-Fa-f:]+[[:space:]]+/, "", name);
    if (name == "") name = mac;
    printf("%s\t%s\n", mac, name);
  }'
}

list_devices() {
  bluetoothctl devices 2>/dev/null | parse_devices
}

adapter_exists() {
  bluetoothctl show >/dev/null 2>&1
}

powered() {
  bluetoothctl show 2>/dev/null | grep -q "Powered: yes"
}

connected_devices() {
  if bluetoothctl devices Connected >/dev/null 2>&1; then
    bluetoothctl devices Connected 2>/dev/null | parse_devices
  else
    list_devices | while IFS=$'\t' read -r mac name; do
      if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
        printf '%s\t%s\n' "$mac" "$name"
      fi
    done
  fi
}

status() {
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    json "" "bluez/bluetoothctl не найден" "absent"
    return
  fi

  if ! adapter_exists; then
    json "" "Bluetooth адаптер не найден" "absent"
    return
  fi

  if ! powered; then
    json "" "Bluetooth выключен" "off"
    return
  fi

  local connected count tooltip
  connected=$(connected_devices)

  if [[ -z "$connected" ]]; then
    json "" "Bluetooth включён" "on"
    return
  fi

  count=$(wc -l <<<"$connected")
  tooltip="Bluetooth: подключено устройств: $count"

  while IFS=$'\t' read -r mac name; do
    local batt
    batt=$(bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Battery:/ {print $2; exit}')

    tooltip+=$'\n'"$name"
    [[ -n "$batt" ]] && tooltip+=" — батарея: $batt"
  done <<<"$connected"

  json "" "$tooltip" "connected"
}

device_menu() {
  local mac="$1"
  local info name paired connected options choice

  info=$(bluetoothctl info "$mac" 2>/dev/null)
  [[ -z "$info" ]] && return

  name=$(awk -F': ' '/Name:/ {print $2; exit}' <<<"$info")
  [[ -z "$name" ]] && name="$mac"

  paired="no"
  connected="no"

  grep -q "Paired: yes" <<<"$info" && paired="yes"
  grep -q "Connected: yes" <<<"$info" && connected="yes"

  options=()

  if [[ "$connected" == "yes" ]]; then
    options+=("Отключить")
  else
    options+=("Подключить")
  fi

  if [[ "$paired" != "yes" ]]; then
    options+=("Сопрячь")
  fi

  options+=("Доверять")
  options+=("Удалить")

  choice=$(printf '%s\n' "${options[@]}" | "${ROFI[@]}" -p "$name") || return

  case "$choice" in
    "Подключить")
      if timeout 10 bluetoothctl connect "$mac" >/dev/null 2>&1; then
        notify "Подключено: $name"
      else
        notify "Не удалось подключиться: $name"
      fi
      ;;

    "Отключить")
      timeout 10 bluetoothctl disconnect "$mac" >/dev/null 2>&1
      notify "Отключено: $name"
      ;;

    "Сопрячь")
      bluetoothctl agent on >/dev/null 2>&1 || true
      bluetoothctl default-agent >/dev/null 2>&1 || true

      if timeout 20 bluetoothctl pair "$mac" >/dev/null 2>&1; then
        bluetoothctl trust "$mac" >/dev/null 2>&1 || true
        bluetoothctl connect "$mac" >/dev/null 2>&1 || true
        notify "Сопряжено: $name"
      else
        notify "Не удалось сопрячь: $name"
      fi
      ;;

    "Доверять")
      bluetoothctl trust "$mac" >/dev/null 2>&1
      notify "Доверие установлено: $name"
      ;;

    "Удалить")
      bluetoothctl remove "$mac" >/dev/null 2>&1
      notify "Удалено: $name"
      ;;
  esac
}

scan_devices() {
  notify "Сканирование 10 секунд..."

  if bluetoothctl --timeout 10 scan >/dev/null 2>&1; then
    :
  else
    bluetoothctl scan on >/dev/null 2>&1 &
    local pid=$!
    sleep 10
    kill "$pid" >/dev/null 2>&1 || true
    bluetoothctl scan off >/dev/null 2>&1 || true
  fi

  exec "$0" menu
}

menu() {
  if ! command -v bluetoothctl >/dev/null 2>&1; then
    notify "Нужен bluez/bluetoothctl"
    return
  fi

  if ! adapter_exists; then
    notify "Bluetooth адаптер не найден"
    return
  fi

  if ! powered; then
    local choice
    choice=$(printf 'Включить Bluetooth\n' | "${ROFI[@]}" -p "Bluetooth") || return

    if [[ "$choice" == "Включить Bluetooth" ]]; then
      bluetoothctl power on >/dev/null 2>&1
      notify "Bluetooth включён"
    fi

    return
  fi

  declare -A dev_mac
  local options=("Выключить Bluetooth" "Сканировать 10 секунд")

  while IFS=$'\t' read -r mac name; do
    [[ -z "$mac" ]] && continue

    local state=""

    if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
      state=" [подключено]"
    fi

    if bluetoothctl info "$mac" 2>/dev/null | grep -q "Paired: yes"; then
      state+=" [сопряжено]"
    fi

    local line="$name$state"

    dev_mac["$line"]="$mac"
    options+=("$line")
  done < <(list_devices)

  local choice
  choice=$(printf '%s\n' "${options[@]}" | "${ROFI[@]}" -p "Bluetooth") || return

  case "$choice" in
    "Выключить Bluetooth")
      bluetoothctl power off >/dev/null 2>&1
      notify "Bluetooth выключен"
      ;;

    "Сканировать 10 секунд")
      scan_devices
      ;;

    *)
      local mac="${dev_mac[$choice]}"
      [[ -n "$mac" ]] && device_menu "$mac"
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