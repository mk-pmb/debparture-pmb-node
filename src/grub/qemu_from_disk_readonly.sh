#!/bin/bash
# -*- coding: utf-8, tab-width: 2 -*-


function qemu_from_disk_readonly_cli_init () {
  export LANG{,UAGE}=en_US.UTF-8  # make error messages search engine-friendly
  [ -d "$XDG_RUNTIME_DIR" ] || return 4$(
    echo E: "XDG_RUNTIME_DIR is not a directory: $XDG_RUNTIME_DIR" >&2)
  local BOOTDISK="$1"
  [ -n "$BOOTDISK" ] || BOOTDISK="$(
    printf -- '%s\n' /dev/disk/by-id/usb-* | grep -vFe '-part')"
  [ -f "$BOOTDISK" ] || [ -b "$BOOTDISK" ] || return 4$(echo E: >&2 \
    "Boot disk must be a file or a block device: ${BOOTDISK:-(none)}")

  local QEMU_OVERLAY_FORMAT='qcow2'
  local QEMU_OVERLAY_SIZE_MB=1
  local QEMU_RAM_LIMIT_MB=128 # Should be plenty sufficient for GRUB.
  local QEMU_OVERLAY_FILE="$XDG_RUNTIME_DIR/qemu/readonly-disk-overlays"
  mkdir --parents --mode=0700 -- "$QEMU_OVERLAY_FILE" || return $?
  QEMU_OVERLAY_FILE="$(mktemp --tmpdir="$QEMU_OVERLAY_FILE" --suffix=".$QEMU_OVERLAY_FORMAT")"
  [ -f "$QEMU_OVERLAY_FILE" ] || return 4$(
    echo E: 'Failed to create temporaty overlay file' >&2)
  qemu-img create -f "$QEMU_OVERLAY_FORMAT" \
    -- "$QEMU_OVERLAY_FILE" "$QEMU_OVERLAY_SIZE_MB"M || return $?
  echo

  local QEMU_CMD=(
    sudo
    qemu-system-x86_64
    -machine pc
    -m "$QEMU_RAM_LIMIT_MB"M
    -enable-kvm
    -drive if=virtio,file="$BOOTDISK",format=raw,readonly=on
    -drive id=drv0,if=none,file="$QEMU_OVERLAY_FILE",driver=qcow2
    -device virtio-blk-pci,drive=drv0
    -boot strict=on,order=c
    -bios /usr/share/ovmf/OVMF.fd # required to enforce strict boot order
    )
  "${QEMU_CMD[@]}"
  local QEMU_RV="$?"
  echo

  rm --verbose -- "$QEMU_OVERLAY_FILE" || true
  return "$QEMU_RV"
}










qemu_from_disk_readonly_cli_init "$@"; exit $?
