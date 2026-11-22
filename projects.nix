# Runs each of the box's projects in its own NixOS container (systemd-nspawn),
# declared in boxes/box.nix:
#
#   kaiBox.projects.crm = {
#     memory = 2048;            # MiB, the container@crm unit's MemoryMax
#     cpus = 2;                 # its CPUQuota, 200%
#     address = "10.77.0.2";    # fixed, on the host's 10.77.0.0/24
#     egress = "none";          # or "any": out to the internet, NATed
#     port = 8080;              # optional: served at https://<site>/crm/
#     config = { pkgs, ... }: { services.crm.enable = true; };
#   };
#
# A project's container:
#
# - has its own network: a veth to the host, which is 10.77.0.1 to it.
#   The host forwards nothing for it, so it reaches the host's open ports
#   (none but Tailscale's) and nothing else, unless egress is "any": then
#   it reaches the internet, but still not the tailnet, another project or
#   a private address. Only the host reaches it, and through routes.nix the
#   tailnet reaches its port;
# - runs as its own range of user IDs (privateUsers "pick"), so its root is
#   nobody on the host;
# - sees none of the host's secrets: /run/secrets and the host key are not
#   in it. A project's own secret is declared in the Kaifile and named in
#   bindMounts by hand until kai's Guests copies them in;
# - keeps its data in /data, which is /var/lib/kai/guests/NAME on the host,
#   in the nightly backup, and restored and verified by the restore test.
#   A project with a database dumps it to /data/backup itself before 03:00.
#
# The option names follow kai's planned typed Guests, Guest(name,
# [Memory(MiB), Cpus(n), GuestAddress, Egress(None | Any)]), so moving a
# project to it is a matter of rewriting the entry (README.md has the
# table). Containers, not microVMs, because Vultr's hosts have no KVM.
{ config, lib, pkgs, ... }:
let
  projects = config.kaiBox.projects;
  hostAddress = "10.77.0.1";
  dataDir = name: "/var/lib/kai/guests/${name}";
  routed = lib.filterAttrs (_: p: p.port != null) projects;
  egressing = lib.attrNames (lib.filterAttrs (_: p: p.egress == "any") projects);
  addresses = lib.mapAttrsToList (_: p: p.address) projects;
  project = { name, ... }: {
    options = {
      memory = lib.mkOption {
        type = lib.types.ints.between 64 1048576;
        description = "The most memory the project's container may use, in MiB.";
      };
      cpus = lib.mkOption {
        type = lib.types.ints.between 1 256;
        description = "How many CPUs' worth of time the project's container may use.";
      };
      address = lib.mkOption {
        type = lib.types.strMatching "10\\.77\\.0\\.([2-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-4])";
        description = "The container's fixed IPv4 address, 10.77.0.2 to 10.77.0.254.";
      };
      egress = lib.mkOption {
        type = lib.types.enum [ "none" "any" ];
        default = "none";
        description = "Whether the container may open connections to the internet.";
      };
      port = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "The TCP port the project serves HTTP on, which routes.nix serves at /${name}/.";
      };
      config = lib.mkOption {
        type = lib.types.deferredModule;
        default = { };
        description = "The container's NixOS configuration.";
      };
    };
  };
in
{
  options.kaiBox.projects = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule project);
    default = { };
    description = "The box's projects, each in its own NixOS container.";
  };

  config = lib.mkMerge [
    {
      # The forward chain drops what no rule below accepts, whichever
      # table Tailscale adds its own rules to.
      networking.nftables.enable = true;
      networking.firewall.filterForward = true;
      systemd.services.tailscaled.environment.TS_DEBUG_FIREWALL_MODE = "nftables";
    }
    (lib.mkIf (projects != { }) {
      assertions = [
        {
          assertion = lib.length addresses == lib.length (lib.unique addresses);
          message = "kaiBox.projects: two projects have the same address";
        }
      ] ++ lib.mapAttrsToList (name: _: {
        assertion = builtins.match "[a-z][a-z0-9-]{0,10}" name != null;
        message = "kaiBox.projects.${name}: a project's name is 1 to 11 of a-z, 0-9 and -, starting with a letter";
      }) projects;

      systemd.tmpfiles.rules = lib.mapAttrsToList (name: _: "d ${dataDir name} 0755 root root -") projects;

      containers = lib.mapAttrs (name: p: {
        autoStart = true;
        privateNetwork = true;
        inherit hostAddress;
        localAddress = p.address;
        privateUsers = "pick";
        # idmap: the container's root owns /data as the host's root does.
        extraFlags = [ "--bind=${dataDir name}:/data:idmap" ];
        config = {
          imports = [ p.config ];
          system.stateVersion = lib.mkDefault config.system.stateVersion;
          # Only the host reaches the container.
          networking.firewall.enable = false;
          # The host's resolver is on the tailnet, which the container
          # does not reach.
          networking.useHostResolvConf = lib.mkIf (p.egress == "any") (lib.mkForce false);
          networking.nameservers = lib.mkIf (p.egress == "any") [ "1.1.1.1" "9.9.9.9" ];
        };
      }) projects;

      systemd.services = lib.mapAttrs' (name: p: lib.nameValuePair "container@${name}" {
        serviceConfig = {
          MemoryMax = "${toString p.memory}M";
          MemorySwapMax = "0";
          CPUQuota = "${toString (p.cpus * 100)}%";
        };
      }) projects;

      networking.nat = lib.mkIf (egressing != [ ]) {
        enable = true;
        internalInterfaces = map (name: "ve-${name}") egressing;
      };
      networking.firewall.extraForwardRules = lib.concatMapStrings (name: ''
        iifname "ve-${name}" oifname "tailscale0" drop
        iifname "ve-${name}" oifname "ve-*" drop
        iifname "ve-${name}" ip daddr { 10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16 } drop
        iifname "ve-${name}" accept
      '') egressing;

      kaiBox.routes.paths = lib.mapAttrs' (name: p:
        lib.nameValuePair "/${name}" "${p.address}:${toString p.port}") routed;
      kaiBox.backup.required = lib.mapAttrsToList (name: _: dataDir name) projects;

      environment.etc."kai/guests.json".text = builtins.toJSON (lib.mapAttrsToList (name: p: {
        inherit name;
        inherit (p) address egress port;
        memory_mib = p.memory;
        inherit (p) cpus;
      }) projects);
    })
  ];
}
