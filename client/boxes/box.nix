# This customer's own part of the box: its Liton setup, its projects, each
# in its own container, and any other Caddy routes. kai-box's modules hold
# the rest.
{ config, lib, ... }:
{
  # The box's name on the tailnet, the Site the Kaifile gives Caddy.
  kaiBox.routes.site = "${config.networking.hostName}.${lib.trim (builtins.readFile ../aion/tailnet)}";

  # Liton at the site's root (see kai-box's liton.nix): the setup
  # Litonfile.roc evaluates to, and the owner's key, which the operator
  # writes to aion/liton-owner after pairing (ONBOARDING.md, step 8).
  kaiBox.liton.setupFile = ../liton.setup.json;
  kaiBox.liton.owner = lib.trim (builtins.readFile ../aion/liton-owner);

  # Each project, served at https://<site>/<name>/ when it has a port
  # (see kai-box's projects.nix), such as
  #
  #   kaiBox.projects.crm = {
  #     memory = 2048;
  #     cpus = 2;
  #     address = "10.77.0.2";
  #     egress = "none";
  #     port = 8080;
  #     config = { pkgs, ... }: {
  #       systemd.services.crm = {
  #         wantedBy = [ "multi-user.target" ];
  #         serviceConfig.ExecStart = "${pkgs.crm}/bin/crm --data /data --port 8080";
  #       };
  #     };
  #   };
  kaiBox.projects = { };

  # Anything else under a path of the site, such as
  #   kaiBox.routes.paths."/files" = "localhost:8081";
  kaiBox.routes.paths = { };
}
