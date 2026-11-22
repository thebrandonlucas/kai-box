# Serves the box's projects under paths of one site, its tailnet name
# (such as https://acme-box.tail1234.ts.net/crm/), on the tailnet only.
#
# The Kaifile declares the site with kai's typed Caddy service, whose own
# target answers whatever no route here takes:
#
#   Services([Caddy([Site("acme-box.tail1234.ts.net", Files("/etc/kai-box/www"))])]),
#
# and boxes/box.nix names the site and its routes, each a path served by an
# upstream that sees the path without its prefix:
#
#   kaiBox.routes.site = "acme-box.tail1234.ts.net";
#   kaiBox.routes.paths."/crm" = "localhost:8080";
#
# Caddy gets the site's certificate from tailscaled, which the tailnet's
# HTTPS certificates setting must allow. tailnet.nix opens no port to the
# internet, Caddy's included, so only the tailnet reaches it.
# /etc/kai-box/www/index.html lists the routes, and the status report
# carries them as extra.caddy.
#
# Once kai has Options, this becomes a Roc helper writing the same Caddy
# lines from the Kaifile, and kai's Caddy can say which interface it serves.
{ config, lib, pkgs, ... }:
let
  cfg = config.kaiBox.routes;
  # Each value lands in a Caddyfile, so it is checked, as kai's Caddy
  # checks its own, rather than escaped.
  path = lib.types.strMatching "/[a-z0-9][a-z0-9._-]*";
  upstream = lib.types.strMatching "([a-z0-9.-]+|[[][0-9a-fA-F:]+[]]):[0-9]+";
  handle = prefix: target: ''
    redir ${prefix} ${prefix}/
    handle_path ${prefix}/* {
    	reverse_proxy ${target}
    }
  '';
  links = lib.concatMapStrings (prefix: ''
    <li><a href="${prefix}/">${prefix}</a></li>
  '') (lib.attrNames cfg.paths);
in
{
  options.kaiBox.routes = {
    site = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[a-z0-9-]+(\\.[a-z0-9-]+)*\\.ts\\.net");
      default = null;
      description = "The box's name on its tailnet, the Caddy Site the routes are added to.";
    };
    paths = lib.mkOption {
      type = lib.types.attrsOf upstream;
      default = { };
      example = { "/crm" = "localhost:8080"; };
      description = "Each path's upstream, host:port or [ipv6]:port, which sees requests without the path.";
    };
  };

  config = lib.mkIf (cfg.site != null) {
    assertions = [
      {
        assertion = config.services.caddy.enable;
        message = "kaiBox.routes.site ${cfg.site} needs Services([Caddy([Site(\"${cfg.site}\", ...)])]) in the Kaifile";
      }
    ] ++ map (prefix: {
      assertion = path.check prefix;
      message = "kaiBox.routes.paths.\"${prefix}\" is no path such as /crm of a-z, 0-9 and ._-";
    }) (lib.attrNames cfg.paths);
    services.caddy.virtualHosts.${cfg.site}.extraConfig =
      lib.concatStrings (lib.mapAttrsToList handle cfg.paths);
    services.tailscale.permitCertUid = config.services.caddy.user;
    environment.etc."kai-box/www/index.html".text = ''
      <!doctype html>
      <title>${config.networking.hostName}</title>
      <h1>${config.networking.hostName}</h1>
      <ul>
      ${links}</ul>
    '';
    environment.etc."kai/status.d/caddy.json".text = builtins.toJSON {
      inherit (cfg) site;
      routes = lib.mapAttrsToList (prefix: target: { path = prefix; upstream = target; }) cfg.paths;
    };
  };
}
