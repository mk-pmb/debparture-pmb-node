
Ubuntu GRUB cheat sheet
=======================

* To get all the usual GRUBs but none of the config update scripts:

  ```bash
  sudo aptitude install grub2-common grub-{pc,efi-{ia32,amd64}}{_,-bin}
  # or
  sudo apt install grub2-common grub-{pc,efi-{ia32,amd64}}-bin
  sudo apt remove               grub-{pc,efi-{ia32,amd64}}
  ```

  * `grub2-common` provides the `grub-install` command.
  * `grub-…-bin` are the architecture-specific implementations
    that `grub-install` can install onto disks.

