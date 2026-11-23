# Runs Liton, the rooms the customer's staff talk in, with their agents,
# at the root of the box's site: https://acme-box.tail1234.ts.net/. The
# Kaifile takes Liton's module from its flake and gives the site to it:
#
#   Input("liton", "github:thebrandonlucas/liton/v0.1.0"),
#   ...
#   Services([Caddy([Site(site, ReverseProxy("127.0.0.1:8095"))])]),
#   InputModules("liton", ["nix/module.nix"]),
#   InputModules("kai-box", [..., "liton.nix"]),
#
# and boxes/box.nix names the customer's setup, which its Litonfile.roc
# evaluates to, and the owner's key:
#
#   kaiBox.liton.setupFile = ../liton.setup.json;
#   kaiBox.liton.owner = lib.trim (builtins.readFile ../aion/liton-owner);
#
# The daemon listens on 127.0.0.1 alone, so only Caddy, on the tailnet,
# reaches it; it answers the site's name and requires a paired device.
# The owner is the operator's key in this box's rooms, an operator who
# can't be removed; it is added to the setup here, so the template names
# no one. Until it is set, the operator pairs as one with `liton pair`.
#
# Liton keeps its rooms, people and devices in /var/lib/liton/liton.db.
# Before each backup it is dumped, consistently, to /data/backup/liton.sql,
# which the restore test requires; kai-box-status gives liton's state.
#
# Root's shell has LITON_DB and LITON_URL set, so `liton pair` writes a
# pairing code into the daemon's database and prints a link on the site.
{ config, lib, pkgs, ... }:
let
  cfg = config.kaiBox.liton;
  liton = config.services.liton;
  site = config.kaiBox.routes.site;
  database = "/var/lib/liton/liton.db";
  setup = lib.importJSON cfg.setupFile // { inherit (cfg) owner; };
in
{
  options.kaiBox.liton = {
    setupFile = lib.mkOption {
      type = lib.types.path;
      description = "The customer's liton.setup.json, which `liton setup` makes from their Litonfile.roc.";
    };
    owner = lib.mkOption {
      type = lib.types.strMatching "([0-9a-f]{64})?";
      default = "";
      description = "The owner's Nostr public key, 64 hex digits, or none.";
    };
  };

  config = {
    assertions = [
      {
        assertion = site != null;
        message = "liton.nix serves Liton at kaiBox.routes.site, which boxes/box.nix sets";
      }
      {
        assertion = liton.host == "127.0.0.1" && liton.port == 8095;
        message = "the Kaifile's Site proxies to 127.0.0.1:8095, where services.liton must listen";
      }
    ];

    services.liton = {
      enable = true;
      allowedHosts = lib.optional (site != null) site;
      auth = "required";
      setupFile = pkgs.writeText "liton.setup.json" (builtins.toJSON setup);
      # Rooms are the relay's alone, without the mock's scripted ones.
      extraEnvironment.LITON_MOCK = "off";
    };
    # The daemon exits 143 on SIGTERM, which would make every stop, a
    # switch's restart included, a failure. Liton's module should say so.
    systemd.services.liton.serviceConfig.SuccessExitStatus = [ 143 ];

    environment.variables = {
      LITON_DB = database;
    } // lib.optionalAttrs (site != null) { LITON_URL = "https://${site}"; };
    environment.systemPackages = [ pkgs.sqlite ];

    kaiBox.backup.dumps."liton.sql" = "${pkgs.sqlite}/bin/sqlite3 -readonly ${database} .dump";
    kaiBox.status.services = [ "liton" ];
    environment.etc."kai/status.d/liton.json".text = builtins.toJSON {
      version = liton.package.version;
      inherit (cfg) owner;
      roles = map (role: role.name) setup.roles;
    };
  };
}
