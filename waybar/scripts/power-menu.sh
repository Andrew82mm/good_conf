#!/usr/bin/env bash
set -o pipefail

ROFI_THEME="$HOME/.config/waybar/rofi/waybar-latte.rasi"

lock_session() {
  if command -v hyprlock >/dev/null 2>&1; then
    hyprlock >/dev/null 2>&1 &
    sleep 0.5
  elif command -v swaylock >/dev/null 2>&1; then
    swaylock -f >/dev/null 2>&1 &
    sleep 0.5
  else
    loginctl lock-session 2>/dev/null || true
    sleep 0.5
  fi
}

choice=$(printf 'Выключить\nПерезагрузить\nСон\n' | rofi -dmenu -i -theme "$ROFI_THEME" -p "Питание") || exit 0

case "$choice" in
  "Выключить")
    systemctl poweroff
    ;;
  "Перезагрузить")
    systemctl reboot
    ;;
  "Сон")
    lock_session
    systemctl suspend
    ;;
esac