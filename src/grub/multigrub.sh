#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function multigrub_main () {
  local SUDO_CMD=
  [ "$USER" == root ] || SUDO_CMD='sudo -E'

  local STOPWATCH_PREV_UTS=
  local BOOT_DIR="$1"
  BOOT_DIR="${BOOT_DIR%/}"
  if [ -z "$BOOT_DIR" ]; then
    for BOOT_DIR in /target/{mnt/esp,boot}; do
      [ -d "$BOOT_DIR" ] && break
    done
    echo "D: No boot directory given. Defaulting to '$BOOT_DIR'." >&2
  fi
  local GRUB_DIR="$BOOT_DIR"/grub
  multigrub_is_plausible_boot_dir || return $?

  local EFI_DIR="$BOOT_DIR/EFI"
  case "$BOOT_DIR" in
    */kernels | \
    / ) EFI_DIR="${BOOT_DIR%/*}/EFI";;
  esac
  local ESP_MPT= ESP_PTN= ESP_DISK=
  multigrub_verify_esp_mpt || return $?

  local GI_OPTS=(
    --boot-directory="$BOOT_DIR"
    --efi-directory="$ESP_MPT"
    --skip-fs-probe
    )
  multigrub_detect_bootloader_id || return $?

  local GRUB_DISK="$(df -- "$GRUB_DIR" | grep -oPe '^/\S+(?=\s)')"
  case "$GRUB_DISK" in
    *$'\n'* | \
    '' ) echo E: 'Failed to detect target disk device name!' >&2; return 4;;
  esac

  if guess_disk_could_likely_be_removable "$GRUB_DISK"; then
    GI_OPTS+=( --no-nvram --removable )
  fi

  GI_OPTS+=( -- "$ESP_DISK" )
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

  [ -f "$GRUB_DIR"/grub.cfg ] && return 0 # Seems well-established.
  [ -f "$GRUB_DIR"/sgd/main.cfg ] && return 0 # SuperGRUB Disk, a good choice.

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
  [ -d "$EFI_DIR" ] || return 4$(echo E: "Not a directory: $EFI_DIR" >&2)
  ESP_MPT="$(stat --dereference --format='%m' -- "$EFI_DIR")"
  local ED_PAR="$(readlink -m -- "$EFI_DIR/..")"
  [ "$ESP_MPT" == "$ED_PAR" ] || return 4$(
    echo E: "EFI directory's mountpoint '$ESP_MPT'" \
      "is not its parent directory '$ED_PAR'." >&2)

  local VAL=" on $ESP_MPT type "
  local BUF="$(mount | grep -Pe '^/' | cut -d '(' -f 1 |
    grep -Fe "$VAL" | sed -rf <(echo "$BUF") )"
  BUF="${BUF% }"
  [ -n "$BUF" ] || return 6$(echo E: >&2 \
    "Cannot find details for EFI directory's mountpoint '$ESP_MPT'")
  if [ "${BUF:0:1}" == = ]; then
    BUF="${BUF:1}"
    ESP_DISK="${BUF%% *}"
    BUF="${BUF#* }"
  fi
  ESP_PTN="${BUF%% *}"
  [ -b "$ESP_PTN" ] || return 4$(echo E: "Cannot find ESP by mountpoint" \
    "'$ESP_MPT': Not a block device: '$ESP_PTN'" >&2)
  BUF=" ${BUF#* }" # we need the initial space for the VAL check:
  [ "${BUF:0:${#VAL}}" == "$VAL" ] || return 7$(
    echo E: 'Control flow bug or very exotic mount output:' \
      'Result from grep seems to not include the match string.' >&2)
  BUF="${BUF:${#VAL}}"
  VAL='vfat'
  [[ ",$VAL," == *",$BUF,"* ]] || return 6$(
    echo E: "Expected the file system of ESP mountpoint '$ESP_MPT'" \
      "to be one of {$VAL}, not '$BUF'" >&2)

  ESP_DISK='
    s~^(/dev/[sh]d[a-z]+)[0-9]+$~\1~p
    s~^(/dev/mmcblk[0-9]+)p[0-9]+$~\1~p
    s~^(/dev/nvme[0-9]+n[0-9]+)p[0-9]+$~\1~p
    '
  ESP_DISK="$(<<<"$ESP_PTN" sed -nrf <(echo "$ESP_DISK"))"
  [ -b "$ESP_DISK" ] || return 4$(
    echo E: "Cannot find disk for ESP '$ESP_PTN' mounted on '$ESP_MPT'" >&2)
}


function multigrub_detect_bootloader_id () {
  local -A DICT=()
  local KEY= VAL=

  local PKJS="$GRUB_DIR"/package.json
  if [ -f "$PKJS" ]; then
    # We can expect users to format their package.json in a simplified
    # format, where the relevant key/value pairs are on their own line
    # and have no weird characters in them:
    VAL='s~^\{? *"([a-z]+)": "([ !#%-Z_a-z]+)",?$~[\1]=\x27\2\x27~p'
    eval "DICT=( $(sed -nre "$VAL" -- "$PKJS") )"
    if [ -n "${DICT[name]}" ]; then
      GI_OPTS+=( --bootloader-id="${DICT[name]}" )
      [ -z "${DICT[version]}" ] || GI_OPTS+=(
        --product-version="${DICT[version]}" )
      return 0
    fi
  fi
}


function guess_disk_could_likely_be_removable () {
  local DISK_DEV="$1"
  local HW_PATH='
    s~/([0-9][0-9a-f:.]+/)+~/~g
    s~^/devices/~~
    s~^pci[0-9:]+/~~
    s~/[^/]+$~~
    s~[0-9:./]+~:~g
    s~:[:-]+~\n~g # so we can use uniq
    s~\n$~~'
  HW_PATH="$(udevadm info --query=path -- "$DISK_DEV" |
    sed -re "$HW_PATH" | uniq)"
  HW_PATH="${HW_PATH//$'\n'/:}"
  case "$HW_PATH:" in
    usb:* ) return 0;;
    *:mmc:* ) return 0;; # (Micro)SD Memory Card
    ata:host:target:block:* ) return 1;;
    *:nvme:* ) return 1;;
  esac
  echo W: $FUNCNAME: "No idea whether '$DISK_DEV' is removable." \
    "Simplified hardware connection path is '$HW_PATH'." >&2
}







multigrub_main "$@"; exit $?
