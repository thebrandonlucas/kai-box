# A box lives on its customer's tailnet and nowhere else. It joins with the
# pre-approved auth key tagged tag:kai-box (the tailscale-authkey secret)
# on first boot, and the firewall trusts only tailscale0: OpenSSH keeps
# listening but no port is open to the internet. If the box never joins,
# the Vultr web console logs root in with the root-password-hash secret.
{ config, ... }:
{
  services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets."tailscale-authkey".path;
    extraUpFlags = [ "--advertise-tags=tag:kai-box" ];
  };
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };
  services.openssh.openFirewall = false;
  users.users.root.hashedPasswordFile = config.age.secrets."root-password-hash".path;
}
