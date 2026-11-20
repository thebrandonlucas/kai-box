# What a Vultr cloud compute instance needs of a NixOS machine that kai
# installs with Disk(SingleDisk("/dev/vda")). kai's nixos-facter report
# brings the virtio drivers and Disk the layout, which boots on BIOS and
# UEFI alike, so this only adds the QEMU guest profile. Vultr hands the
# main IPv4 out by DHCP and IPv6 by router advertisement, which NixOS's
# default networking takes.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  services.qemuGuest.enable = true;
}
