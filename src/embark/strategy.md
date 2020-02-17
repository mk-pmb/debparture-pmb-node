
Strategy
========

1.  Assume the target computer already has a good enough boot loader.
1.  Install minimum drone system.
1.  Extend the drone system.



Need a boot loader?
===================

I haven't yet found a boot loader that both does what I want
and is easy to install.
My [multigrub script](../../grub/multigrub.sh)
is a fickle crutch, but in no way ready for a general audience.

In hopes you already have a solution that works for you,
I'll leave boot loader installation as an exercise to the reader.

If you need to bridge an initial gap to then
install your favorite boot loader via SSH
(possibly via some automation software like [ansible][ansible]),
the [SuperGrub Disk][supergrub] might help.

  [ansible]: https://www.ansible.com/
  [supergrub]: https://www.supergrubdisk.org/



Install minimum drone system
============================

Caveats
-------

* `multistrap` @ 3d1d339 (committed 2018-11-21 13:54), run at 2020-02-14:
  * had problems installing anything when `/target/tmp` was a tmpfs.
    &rArr; Mount `/target/tmp` only after multistrap.
  * ignored host's APT proxy settings
    &rArr; Provide proxy via `http{,s}_proxy` env vars.
  * `Warning: unrecognised value 'no' for Multi-Arch field in ` (package name)
    `. (Expecting 'same', 'foreign' or 'allowed'.)`
    seems to be unimportant.










