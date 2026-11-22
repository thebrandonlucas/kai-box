# Backs the box up with restic, every night, to object storage at a
# provider other than Vultr, and restores it once a month to prove the
# backups work.
#
# The b2 backup goes to the repository the restic-env secret names, with
# its credentials, and is encrypted with the restic-password secret:
#
#   RESTIC_REPOSITORY=s3:https://s3.us-east-005.backblazeb2.com/BUCKET/SLUG
#   AWS_ACCESS_KEY_ID=...        # a Backblaze application key scoped
#   AWS_SECRET_ACCESS_KEY=...    # to the bucket
#
# A second target is another services.restic.backups.NAME in
# boxes/box.nix, and gets everything below too:
#
# - kai-backup-dump runs first, writing each of kaiBox.backup.dumps (and
#   PostgreSQL, when the box runs it) to /data/backup, so databases are
#   restored from a consistent dump rather than files copied mid-write;
# - a canary, /var/lib/kai/backup-canary, holding the time each run starts;
# - /var/lib/kai/status.d/backup-NAME.json after every run, which the
#   status report carries, and a ping to Healthchecks' check
#   <hostname>-backup-NAME: start when it begins, then success or fail
#   with the run's log, so a backup that fails or stops running alerts;
# - kai-restore-test-NAME, monthly: `restic check` reads a twelfth of the
#   repository's data (so a year reads all of it), then the latest
#   snapshot's /var/lib/kai and /data/backup are restored into
#   /var/lib/kai-restore-test/NAME and verified against the snapshot. The
#   canary must be younger than kaiBox.backup.maxAgeHours and every dump
#   must be there and not empty. It writes restore-test-NAME.json, pings
#   <hostname>-restore-test-NAME the same way, and fails, leaving the
#   system degraded, when any check does.
{ config, lib, pkgs, ... }:
let
  cfg = config.kaiBox.backup;
  backups = config.services.restic.backups;
  canary = "/var/lib/kai/backup-canary";
  dumpDir = "/data/backup";
  reports = "/var/lib/kai/status.d";
  scratch = "/var/lib/kai-restore-test";
  postgres = config.services.postgresql;
  dumps = cfg.dumps // lib.optionalAttrs (postgres.enable && !(cfg.dumps ? postgresql)) {
    postgresql = "${pkgs.util-linux}/bin/runuser -u postgres -- ${postgres.package}/bin/pg_dumpall";
  };
  ping = "${config.kaiBox.healthchecks.ping}/bin/kai-box-ping";
  # Pings check NAME as a unit starts; its failure is ignored.
  start = name: "-" + pkgs.writeShellScript "kai-start-${name}" "${ping} ${name} start </dev/null";
  # Writes NAME.json from what systemd tells a unit's ExecStopPost, and
  # pings check NAME with the result and this run's log.
  report = name: pkgs.writeShellScript "kai-report-${name}" ''
    mkdir -p ${reports}
    printf '{"time":"%s","result":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SERVICE_RESULT" \
      > ${reports}/${name}.json
    signal=fail
    [ "$SERVICE_RESULT" = success ] && signal=
    ${config.systemd.package}/bin/journalctl -o cat --no-pager \
      _SYSTEMD_INVOCATION_ID="$INVOCATION_ID" | tail -c 90000 | ${ping} ${name} $signal
  '';
  repository = backup:
    lib.optionalAttrs (backup.repository != null) { RESTIC_REPOSITORY = backup.repository; }
    // lib.optionalAttrs (backup.repositoryFile != null) {
      RESTIC_REPOSITORY_FILE = toString backup.repositoryFile;
    }
    // lib.optionalAttrs (backup.passwordFile != null) {
      RESTIC_PASSWORD_FILE = toString backup.passwordFile;
    }
    // { RESTIC_CACHE_DIR = "/var/cache/kai-restore-test"; };
  restoreTest = name: backup: {
    description = "Restore test of backup ${name}";
    path = [ backup.package pkgs.coreutils ];
    environment = repository backup;
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = lib.optional (backup.environmentFile != null) backup.environmentFile;
      CacheDirectory = "kai-restore-test";
      StateDirectory = "kai-restore-test";
      ExecStartPre = [ (start "restore-test-${name}") ];
      ExecStopPost = [ (report "restore-test-${name}") ];
    };
    script = ''
      set -eu
      restic check --read-data-subset="$(date +%-m)/12"
      restored=${scratch}/${name}
      rm -rf "$restored"
      trap 'rm -rf "$restored"' EXIT
      restic restore latest --target "$restored" --verify \
        --include /var/lib/kai --include ${dumpDir}
      if [ ! -f "$restored${canary}" ]; then
        echo "the latest snapshot holds no ${canary}: back up /var/lib/kai" >&2
        exit 1
      fi
      age=$(( $(date +%s) - $(cat "$restored${canary}") ))
      if [ "$age" -gt ${toString (cfg.maxAgeHours * 3600)} ]; then
        echo "the latest snapshot is $(( age / 3600 )) hours old" >&2
        exit 1
      fi
      for dump in ${lib.escapeShellArgs (lib.attrNames dumps)}; do
        if [ ! -s "$restored${dumpDir}/$dump" ]; then
          echo "the latest snapshot's dump ${dumpDir}/$dump is missing or empty" >&2
          exit 1
        fi
      done
      echo "restored and verified the latest snapshot, $(( age / 3600 )) hours old"
    '';
  };
in
{
  imports = [ ./healthchecks.nix ];

  options.kaiBox.backup = {
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/var/lib" "/data" ];
      description = "What the b2 backup saves. It must include /var/lib/kai and /data/backup.";
    };
    dumps = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { "crm.sqlite" = "\${pkgs.sqlite}/bin/sqlite3 /var/lib/crm/crm.db .dump"; };
      description = ''
        Commands, run as root before each backup, whose output is saved as
        /data/backup/NAME. PostgreSQL is dumped as postgresql without one.
      '';
    };
    at = lib.mkOption {
      type = lib.types.str;
      default = "03:00";
      description = "When the b2 backup runs each day, as a systemd calendar event.";
    };
    keep = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "--keep-daily 7" "--keep-weekly 5" "--keep-monthly 12" ];
      description = "The snapshots the b2 backup keeps, as restic forget's options.";
    };
    maxAgeHours = lib.mkOption {
      type = lib.types.ints.positive;
      default = 48;
      description = "How old the latest snapshot may be when a restore test runs.";
    };
  };

  config = lib.mkMerge [
    {
      services.restic.backups.b2 = {
        environmentFile = config.age.secrets."restic-env".path;
        passwordFile = config.age.secrets."restic-password".path;
        initialize = true;
        paths = cfg.paths;
        exclude = [ scratch ];
        pruneOpts = cfg.keep;
        timerConfig = {
          OnCalendar = cfg.at;
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    }
    (lib.mkIf (backups != { }) {
      assertions = map (dump: {
        assertion = builtins.match "[A-Za-z0-9_][A-Za-z0-9._-]*" dump != null;
        message = "kaiBox.backup.dumps.\"${dump}\": a dump's name is a file name of letters, digits and ._-";
      }) (lib.attrNames dumps);
      systemd.tmpfiles.rules = [
        "d /var/lib/kai 0755 root root -"
        "d ${dumpDir} 0700 root root -"
      ];
      systemd.services =
        {
          kai-backup-dump = {
            description = "Dump databases to ${dumpDir} for the backup";
            serviceConfig.Type = "oneshot";
            script = ''
              set -eu
            '' + lib.concatStrings (lib.mapAttrsToList (dump: command: ''
              ${command} > ${dumpDir}/.${dump}.tmp
              mv ${dumpDir}/.${dump}.tmp ${lib.escapeShellArg "${dumpDir}/${dump}"}
            '') dumps);
          };
        }
        // lib.mapAttrs' (name: _: lib.nameValuePair "restic-backups-${name}" {
          requires = [ "kai-backup-dump.service" ];
          after = [ "kai-backup-dump.service" ];
          serviceConfig.ExecStartPre = lib.mkBefore [
            (start "backup-${name}")
            (pkgs.writeShellScript "kai-backup-canary" "date +%s > ${canary}")
          ];
          serviceConfig.ExecStopPost = [ (report "backup-${name}") ];
        }) backups
        // lib.mapAttrs' (name: backup:
          lib.nameValuePair "kai-restore-test-${name}" (restoreTest name backup)) backups;
      systemd.timers = lib.mapAttrs' (name: _: lib.nameValuePair "kai-restore-test-${name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "monthly";
          Persistent = true;
          RandomizedDelaySec = "6h";
        };
      }) backups;
    })
  ];
}
