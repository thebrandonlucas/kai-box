# Pings the operator's Healthchecks, which alerts when a box's checks fail
# or stop arriving. Each check is named by slug, <hostname>-<what>, under
# one project's ping key, and created on its first ping, so a new box needs
# nothing made by hand. The URL (such as https://hc.example.com/ping) and
# the key are the healthchecks-url and healthchecks-ping-key secrets.
#
# backup.nix and status.nix import this; config.kaiBox.healthchecks.ping
# is the command they run:
#
#   kai-box-ping WHAT [start|fail] < body
#
# A ping that cannot be delivered is logged and otherwise ignored, so the
# collector being down never fails a backup.
{ config, lib, pkgs, ... }:
let
  cfg = config.kaiBox.healthchecks;
  ping = pkgs.writeShellApplication {
    name = "kai-box-ping";
    runtimeInputs = [ pkgs.curl pkgs.coreutils ];
    text = ''
      slug=${lib.escapeShellArg config.networking.hostName}-$1
      signal=''${2:+/$2}
      url=$(cat ${lib.escapeShellArg cfg.urlFile})
      key=$(cat ${lib.escapeShellArg cfg.pingKeyFile})
      # Healthchecks keeps the first 100 kB of a body. Three tries of 15 s at
      # most: under a minute, inside the 90 s systemd gives an ExecStopPost.
      if ! head -c 100000 | curl -fsS --connect-timeout 10 -m 15 --retry 2 --data-binary @- \
        "$url/$key/$slug$signal?create=1" >/dev/null; then
        echo "kai-box-ping: could not ping $slug$signal" >&2
      fi
    '';
  };
in
{
  options.kaiBox.healthchecks = {
    urlFile = lib.mkOption {
      type = lib.types.str;
      default = config.age.secrets."healthchecks-url".path;
      defaultText = lib.literalExpression ''config.age.secrets."healthchecks-url".path'';
      description = "A file holding Healthchecks' ping URL, without a trailing slash.";
    };
    pingKeyFile = lib.mkOption {
      type = lib.types.str;
      default = config.age.secrets."healthchecks-ping-key".path;
      defaultText = lib.literalExpression ''config.age.secrets."healthchecks-ping-key".path'';
      description = "A file holding the ping key of the Healthchecks project the box reports to.";
    };
    ping = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = ping;
      description = "kai-box-ping WHAT [start|fail]: pings check <hostname>-WHAT with stdin as its body.";
    };
  };
}
