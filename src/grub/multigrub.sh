#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function multigrub_main () {
  local ESP_MPT="${1:-/target/boot}"; shift
  ESP_MPT="${ESP_MPT%/}"
  local EFI_DIR="$ESP_MPT/EFI"

  local SUDO_CMD=
  [ "$USER" == root ] || SUDO_CMD='sudo -E'

  multigrub_ensure_efi_dir || return $?

  mountpoint -q -- "$ESP_MPT" || return 4$(
    echo "E: ESP path '$ESP_MPT' seems to not be a mounted mountpoint." >&2)
  local ESP_PTN="$(mount | grep -Fe " on $ESP_MPT type " | grep -Poe '^/\S+')"
  [ -b "$ESP_PTN" ] || return 4$(echo "E: cannot find ESP by mountpoint" >&2)
  local ESP_DISK='
    s~^(/dev/[sh]d[a-z]+)[0-9]+$~\1~p
    '
  ESP_DISK="$(<<<"$ESP_PTN" sed -nrf <(echo "$ESP_DISK"))"
  [ -b "$ESP_DISK" ] || return 4$(
    echo "E: cannot find disk for ESP '$ESP_PTN' mounted on '$ESP_MPT'" >&2)
  # :TODO: verify it's a proper ESP

  local GI_OPTS=(
    --{efi,boot}-directory="$ESP_MPT"
    --no-nvram
    --skip-fs-probe
    --removable
    -- "$ESP_DISK"
    )
  local PLATF=
  for PLATF in /usr/lib/grub/*-{efi,pc}/; do
    [ -f "$PLATF/modinfo.sh" ] || continue
    PLATF="$(basename -- "${PLATF%/}")"
    $SUDO_CMD grub-install --target="$PLATF" "${GI_OPTS[@]}" || return $?
  done
}


function multigrub_ensure_efi_dir () {
  [ -d "$EFI_DIR" ] && return 0
  multigrub_is_plausible_esp || return 3$(
    echo "E: '$EFI_DIR' seems to not be a directory and '$ESP_MPT'" \
      "doesn't looks like a plausible ESP." >&2)
  $SUDO_CMD mkdir -- "$EFI_DIR" || return $?
}


function multigrub_is_plausible_esp () {
  local ITEM=

  for ITEM in "$ESP_MPT"/memtest86*.{bin,elf}; do
    [ -f "$ESP_MPT" ] && return 0   # any memtest is good enough
  done

  for ITEM in "$ESP_MPT"/initrd.img-[0-9]* ''; do
    [ -f "$ITEM" ] && break
    [ -n "$ITEM" ] || return 3   # no initrd = not a typical Ubuntu
  done
  for ITEM in "$ESP_MPT"/vmlinuz-[0-9]* ''; do
    [ -f "$ITEM" ] && break
    [ -n "$ITEM" ] || return 3   # no vmlinuz = not a typical Ubuntu
    return 3
  done
}







multigrub_main "$@"; exit $?
