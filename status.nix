# Reports the box's status to the operator's Healthchecks every
# kaiBox.status.interval, as the body of a ping to check <hostname>-status,
# which Healthchecks keeps. A box with a problem (a failed unit, a system
# not running, a disk fuller than kaiBox.status.diskPercent) pings /fail,
# so Healthchecks alerts; so does one that stops pinging.
#
# kai-box-status prints the document, on the box too:
#
#   { "schema": 1, "machine": "acme-box", "time": "...",
#     "health": "running", "failed_units": [], "problems": [],
#     "generation": 43, "revision": "1a2b3c4...", "nixos": "26.05...",
#     "inputs": { "kai-box": "abc123..." },
#     "disk": [{ "mount": "/", "size": ..., "used": ..., "percent": 41 }],
#     "memory": { "total": ..., "available": ..., "swap_total": ..., "swap_free": ... },
#     "guests": [{ "name": "crm", "state": "active", "address": "10.77.0.2",
#                  "memory_mib": 2048, "cpus": 2, "egress": "none", "port": 8080,
#                  "memory_current": ... }],
#     "extra": { "backup-b2": { "time": "...", "result": "success" }, "caddy": {...} } }
#
# extra holds every /etc/kai/status.d, /run/kai/status.d and
# /var/lib/kai/status.d/NAME.json, as NAME: backup.nix writes its backups'
# and restore tests' results there and routes.nix the Caddy routes.
# guests lists projects.nix's containers with their units' state.
# This is the shape kai's planned `kai machine status` prints; once kai
# ships it, kai-box-status gives way to it.
{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.kaiBox.status;
  ping = "${config.kaiBox.healthchecks.ping}/bin/kai-box-ping";
  # What is known when the system is built. revision is the commit of the
  # customer's repository, which its revision.nix sets.
  built = {
    machine = config.networking.hostName;
    revision = config.system.configurationRevision;
    nixos = config.system.nixos.version;
    inputs."kai-box" = inputs."kai-box".rev or inputs."kai-box".dirtyRev or null;
  };
  status = pkgs.writeShellApplication {
    name = "kai-box-status";
    runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.gawk pkgs.gnused config.systemd.package ];
    text = ''
      health=$(systemctl is-system-running || true)
      failed=$(systemctl list-units --state=failed --output=json --no-pager | jq -c 'map(.unit)')
      generation=$( (readlink /nix/var/nix/profiles/system || true) | sed -n 's/^system-\([0-9]*\)-link$/\1/p')
      disk=$(df -B1 --output=target,size,used -x tmpfs -x devtmpfs -x efivarfs -x overlay -x vfat \
        | tail -n +2 | jq -R -s -c 'split("\n") | map(select(. != "") | [splits(" +")]
          | { mount: .[0], size: (.[1] | tonumber), used: (.[2] | tonumber) }
          | .percent = (if .size > 0 then (100 * .used / .size | floor) else 0 end))')
      memory=$(awk '
        /^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 }
        /^SwapTotal:/ { st = $2 } /^SwapFree:/ { sf = $2 }
        END { printf "{\"total\":%d,\"available\":%d,\"swap_total\":%d,\"swap_free\":%d}", t*1024, a*1024, st*1024, sf*1024 }
      ' /proc/meminfo)
      # Each project container projects.nix declares, with its unit's state.
      guests='[]'
      if [ -f /etc/kai/guests.json ]; then
        while read -r guest; do
          name=$(jq -r .name <<<"$guest")
          state=$(systemctl show -P ActiveState "container@$name.service")
          used=$(systemctl show -P MemoryCurrent "container@$name.service")
          guests=$(jq -c --argjson guest "$guest" --arg state "$state" --arg used "$used" \
            '. + [$guest + { state: $state, memory_current: ($used | tonumber? // null) }]' <<<"$guests")
        done < <(jq -c '.[]' /etc/kai/guests.json)
      fi
      extra='{}'
      for fragment in /etc/kai/status.d/*.json /run/kai/status.d/*.json /var/lib/kai/status.d/*.json; do
        [ -f "$fragment" ] || continue
        name=$(basename "$fragment" .json)
        if value=$(jq -c . "$fragment" 2>/dev/null); then
          extra=$(jq -c --arg name "$name" --argjson value "$value" '.[$name] = $value' <<<"$extra")
        else
          extra=$(jq -c --arg name "$name" '.[$name] = { error: "not JSON" }' <<<"$extra")
        fi
      done
      jq -n \
        --argjson built ${lib.escapeShellArg (builtins.toJSON built)} \
        --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg health "$health" \
        --argjson failed "$failed" \
        --arg generation "$generation" \
        --argjson disk "$disk" \
        --argjson memory "$memory" \
        --argjson extra "$extra" \
        --argjson guests "$guests" \
        --argjson full ${toString cfg.diskPercent} '
        { schema: 1, machine: $built.machine, time: $time, health: $health,
          failed_units: $failed,
          problems: (
            (if $health == "running" then [] else ["the system is \($health)"] end)
            + ($failed | map("\(.) failed"))
            + ($disk | map(select(.percent >= $full) | "\(.mount) is \(.percent)% full"))
            + ($guests | map(select(.state != "active") | "project \(.name) is \(.state)"))),
          generation: ($generation | tonumber? // null),
          revision: $built.revision, nixos: $built.nixos, inputs: $built.inputs,
          guests: $guests, disk: $disk, memory: $memory, extra: $extra }'
    '';
  };
in
{
  imports = [ ./healthchecks.nix ];

  options.kaiBox.status = {
    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "How often to report, as a systemd time span. Set the check's period in Healthchecks to match.";
    };
    diskPercent = lib.mkOption {
      type = lib.types.ints.between 1 100;
      default = 90;
      description = "How full a disk may be, in percent, before the report is a failure.";
    };
  };

  config = {
    environment.systemPackages = [ status ];
    systemd.tmpfiles.rules = [ "d /var/lib/kai/status.d 0755 root root -" ];
    systemd.services.kai-status-push = {
      description = "Report the box's status to Healthchecks";
      path = [ status pkgs.jq ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        report=$(kai-box-status)
        if jq -e '.problems == []' <<<"$report" >/dev/null; then
          ${ping} status <<<"$report"
        else
          ${ping} status fail <<<"$report"
        fi
      '';
    };
    systemd.timers.kai-status-push = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = cfg.interval;
      };
    };
  };
}
