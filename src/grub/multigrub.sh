#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function multigrub_main () {
  local SUDO_CMD=
  [ "$USER" == root ] || SUDO_CMD='sudo -E'

  local STOPWATCH_PREV_UTS=
  local BOOT_DIR="$1"
  if [ -z "$BOOT_DIR" ]; then
    for BOOT_DIR in /target/{mnt/esp,boot}; do
      [ -d "$BOOT_DIR" ] && break
    done
    echo "D: No boot directory given. Defaulting to '$BOOT_DIR'." >&2
  fi
  multigrub_is_plausible_boot_dir || return $?

  local EFI_DIR="$BOOT_DIR/EFI"
  local ESP_MPT=
  multigrub_verify_esp_mpt || return $?

  local ESP_PTN="$(findmnt --noheadings --output source --evaluate \
    --target "$ESP_MPT")"
  [ -b "$ESP_PTN" ] || return 4$(echo "E: cannot find ESP by mountpoint" \
    "'$ESP_MPT'" >&2)
  local ESP_DISK='
    s~^(/dev/[sh]d[a-z]+)[0-9]+$~\1~p
    s~^(/dev/mmcblk[0-9]+)p[0-9]+$~\1~p
    s~^(/dev/nvme[0-9]+n[0-9]+)p[0-9]+$~\1~p
    '
  ESP_DISK="$(<<<"$ESP_PTN" sed -nrf <(echo "$ESP_DISK"))"
  [ -b "$ESP_DISK" ] || return 4$(
    echo "E: cannot find disk for ESP '$ESP_PTN' mounted on '$ESP_MPT'" >&2)

  # :TODO: verify it's a proper ESP

  local GI_OPTS=(
    --boot-directory="$BOOT_DIR"
    --efi-directory="$ESP_MPT"
    --no-nvram
    --skip-fs-probe
    --removable
    -- "$ESP_DISK"
    )
  local PLATFS=(
    # Fallbacks first, best platforms last, so their changes will prevail.
    pc
    efi
    )
  local PLATF=
  local GRUB_CMD="grub-install --target="
  echo "D: cmd template: ${GRUB_CMD}PLAT ${GI_OPTS[*]}"

  for PLATF in "${PLATFS[@]}"; do
    for PLATF in /usr/lib/grub/*-"$PLATF"/; do
      [ -f "$PLATF/modinfo.sh" ] || continue
      PLATF="$(basename -- "${PLATF%/}")"
      stopwatch_start_line
      # ^-- No "D:" prefix because the next line(s) printed may stem from
      # GRUB hook scripts and may carry their own log level markers.
      SECONDS=0
      $SUDO_CMD $GRUB_CMD"$PLATF" "${GI_OPTS[@]}" || return $?
    done
  done

  stopwatch_start_line
  echo 'Done.'
}


function stopwatch_start_line () {
  local NOW= DELTA='0s'
  printf -v NOW '%(%s)T' -1
  if [ -n "$STOPWATCH_PREV_UTS" ]; then
    (( DELTA = NOW - STOPWATCH_PREV_UTS ))
    TZ=UTC printf -v DELTA '%(%Hh%Mm%Ss)T' "$DELTA"
    DELTA="${DELTA#00h}"
    DELTA="${DELTA#00m}"
    DELTA="${DELTA#0}"
  fi
  printf '[%(%F %T)T = +%s] ' "$NOW" "$DELTA"
  STOPWATCH_PREV_UTS="$NOW"
}


function multigrub_is_plausible_boot_dir () {
  local UNBOOT="E: Probably not bootable: Boot directory '$BOOT_DIR' $(
    )contains none of the files we'd typically expect, especially not"

  local ITEM=
  for ITEM in "$BOOT_DIR"/memtest86*.{bin,elf}; do
    [ -f "$ITEM" ] && return 0   # any memtest is good enough
  done

  local GR="$BOOT_DIR"/grub
  [ -f "$GR"/grub.cfg ] && return 0 # Seems well-established.
  [ -f "$GR"/sgd/main.cfg ] && return 0 # SuperGRUB Disk, a good choice.

  for ITEM in "$BOOT_DIR"/initrd.img-[0-9]* ''; do
    [ -f "$ITEM" ] && break
    [ -n "$ITEM" ] || return 3$(echo "$UNBOOT an initrd." >&2)
  done
  for ITEM in "$BOOT_DIR"/vmlinuz-[0-9]* ''; do
    [ -f "$ITEM" ] && break
    [ -n "$ITEM" ] || return 3$(echo "$UNBOOT a vmlinuz." >&2)
  done
  # echo "D: found an initrd and a vmlinuz." >&2
}


function multigrub_verify_esp_mpt () {
  $SUDO_CMD mkdir --parents "$EFI_DIR"
  [ -d "$EFI_DIR" ] || return 4$(echo "E: not a directory: $EFI_DIR" >&2)
  local ED_MPT="$(stat --dereference --format='%m' -- "$EFI_DIR")"
  local ED_PAR="$(readlink -m -- "$EFI_DIR/..")"
  [ "$ED_MPT" == "$ED_PAR" ] || return 4$(
    echo "E: EFI directory's mountpoint '$ED_MPT'" \
      "is not its parent directory '$ED_PAR'." >&2)
  ESP_MPT="$ED_MPT"
}







multigrub_main "$@"; exit $?
