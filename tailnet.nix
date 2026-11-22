# A box lives on its customer's tailnet and nowhere else. It joins with the
# pre-approved auth key tagged tag:kai-box (the tailscale-authkey secret)
# on first boot, and the firewall trusts only tailscale0: OpenSSH and Caddy
# keep listening but no port is open to the internet, not even the ones
# kai's Caddy service opens, only Tailscale's own. If the box never joins,
# the Vultr web console logs root in with the root-password-hash secret.
#
# Once kai can scope Firewall and Caddy to an interface, the mkForce goes.
{ config, lib, ... }:
{
  services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets."tailscale-authkey".path;
    extraUpFlags = [ "--advertise-tags=tag:kai-box" ];
  };
  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedTCPPorts = lib.mkForce [ ];
    allowedUDPPorts = lib.mkForce [ config.services.tailscale.port ];
  };
  services.openssh.openFirewall = false;
  users.users.root.hashedPasswordFile = config.age.secrets."root-password-hash".path;
}
