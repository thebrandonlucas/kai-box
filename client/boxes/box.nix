# This customer's own part of the box: its projects' microVMs, Caddy
# routes and any secrets they read. kai-box's modules hold the rest.
{ config, lib, ... }:
{
  # The box's name on the tailnet, the Site the Kaifile gives Caddy.
  kaiBox.routes.site = "${config.networking.hostName}.${lib.trim (builtins.readFile ../aion/tailnet)}";
  # Each project under a path of it, such as
  #   kaiBox.routes.paths."/crm" = "localhost:8080";
  kaiBox.routes.paths = { };
}
