#!/bin/bash
#!debparture run-file
# -*- coding: utf-8, tab-width: 2 -*-


function multigrub () {
  # local ESP_MNPT="$(stat -c %m -- "$EFI_DIR/")"
  local ESP_MNPT="$1"; shift
  ESP_MNPT="${ESP_MNPT%/}"
  [ -d "$ESP_MNPT/EFI" ] || return 4$(
    echo "E: ESP path '$ESP_MNPT' doesn't have an 'EFI' subdirectory." >&2)
  mountpoint -q -- "$ESP_MNPT" || return 4$(
    echo "E: ESP path '$ESP_MNPT' seems to not be a mounted mountpoint." >&2)
  local ESP_PART="$(mount | grep -Fe " on $ESP_MNPT type " | grep -Poe '^/\S+')"
  [ -b "$ESP_PART" ] || return 4$(
    echo "E: cannot find mountpoint of EFI directory '$EFI_DIR'" >&2)
  local ESP_DISK='
    s~^(/dev/[sh]d[a-z]+)[0-9]+$~\1~p
    '
  ESP_DISK="$(<<<"$ESP_PART" sed -nrf <(echo "$ESP_DISK"))"
  [ -b "$ESP_DISK" ] || return 4$(
    echo "E: cannot find disk for ESP '$ESP_PART' mounted on '$ESP_MNPT'" >&2)
  # :TODO: verify it's a proper ESP

  local GI_OPTS=(
    --{efi,boot}-directory="$ESP_MNPT"
    --no-nvram
    --skip-fs-probe
    --removable
    -- "$ESP_DISK"
    )
  local PLATF=
  for PLATF in /usr/lib/grub/*-{efi,pc}/; do
    [ -f "$PLATF/modinfo.sh" ] || continue
    PLATF="$(basename -- "${PLATF%/}")"
    sudo -E grub-install --target="$PLATF" "${GI_OPTS[@]}" || return $?
  done
}





multigrub "$@"; exit $?
