# A VM test of a box's modules together: Liton at the site's root, two
# project containers, the backup, the status report and the routes, and a
# host standing in for the internet at 203.0.113.1. Run it with
#
#   nix-build tests/box.nix --arg pkgs 'import <nixpkgs> { }'
#
# kai's agenix secrets are files in /etc here, Healthchecks is not there
# (its pings fail, which must not matter) and Caddy's site has a
# certificate of its own CA rather than Tailscale's.
{ pkgs }:
let
  site = "box.tail0000.ts.net";
  # Liton's module, from the release the Kaifile's Input pins.
  liton = builtins.fetchTarball {
    url = "https://github.com/thebrandonlucas/liton/archive/v0.1.0.tar.gz";
    sha256 = "0aqfdh907mcmisxlrch2wjm00hja4j3wfrflzr145r8ylv9lcass";
  };
  owner = lib.concatStrings (lib.replicate 32 "ab");
  inherit (pkgs) lib;
  secrets = { lib, ... }: {
    options.age.secrets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options.path = lib.mkOption { type = lib.types.str; default = "/etc/test-secrets/${name}"; };
      }));
      default = { };
    };
    config = {
      age.secrets = lib.genAttrs [ "restic-env" "restic-password" "healthchecks-url" "healthchecks-ping-key" ] (_: { });
      environment.etc = {
        "test-secrets/restic-env".text = "RESTIC_REPOSITORY=/var/backup-repo\n";
        "test-secrets/restic-password".text = "test\n";
        "test-secrets/healthchecks-url".text = "http://192.168.1.2:9/ping";
        "test-secrets/healthchecks-ping-key".text = "key";
      };
    };
  };
  # Serves /data/www, which says hello from NAME, on port.
  web = name: port: { pkgs, ... }: {
    environment.systemPackages = [ pkgs.curl ];
    systemd.services.web = {
      wantedBy = [ "multi-user.target" ];
      script = ''
        mkdir -p /data/www
        echo "hello from ${name}" > /data/www/index.html
        exec ${pkgs.python3}/bin/python3 -m http.server ${toString port} --directory /data/www
      '';
    };
  };
in
pkgs.testers.runNixOSTest {
  name = "kai-box";

  nodes.internet = {
    networking.interfaces.eth1.ipv4.addresses = [ { address = "203.0.113.1"; prefixLength = 24; } ];
    networking.firewall.allowedTCPPorts = [ 80 ];
    services.nginx = {
      enable = true;
      virtualHosts.default.locations."/".return = "200 'internet'";
    };
  };

  nodes.box = { config, lib, ... }: {
    imports = [
      secrets ../backup.nix ../status.nix ../routes.nix ../projects.nix
      "${liton}/nix/module.nix" ../liton.nix
    ];
    # kai passes its flake's inputs; status.nix reads kai-box's revision.
    _module.args.inputs = { };
    virtualisation.memorySize = 2048;
    # Containers bind /nix/store with an idmapped mount, which neither the
    # default virtiofs store nor an erofs store image allows: the box is
    # installed on an ext4 disk, as a Vultr box is.
    virtualisation.useBootLoader = true;
    networking.hostName = "box";
    services.openssh = { enable = true; openFirewall = false; };
    networking.interfaces.eth1.ipv4.routes = [ { address = "203.0.113.0"; prefixLength = 24; } ];
    environment.systemPackages = [ pkgs.curl pkgs.jq ];
    services.tailscale.enable = true;
    services.caddy = {
      enable = true;
      virtualHosts.${site}.extraConfig = lib.mkMerge [
        # What kai's Site(site, ReverseProxy("127.0.0.1:8095")) renders.
        "reverse_proxy 127.0.0.1:8095"
        (lib.mkAfter "tls internal")
      ];
    };
    networking.hosts."127.0.0.1" = [ site ];
    kaiBox.routes.site = site;
    kaiBox.liton = { setupFile = ../client/liton.setup.json; inherit owner; };
    kaiBox.projects = {
      web = { memory = 256; cpus = 1; address = "10.77.0.2"; port = 8080; config = web "web" 8080; };
      fetch = { memory = 256; cpus = 1; address = "10.77.0.3"; egress = "any"; config = web "fetch" 8081; };
    };
  };

  testScript = ''
    start_all()
    internet.wait_for_unit("nginx.service")
    box.wait_for_unit("container@web.service")
    box.wait_for_unit("container@fetch.service")
    box.wait_until_succeeds("curl -sf http://10.77.0.2:8080/ | grep 'hello from web'", timeout=120)

    def run(container, command):
        return f"nixos-container run {container} -- {command}"

    with subtest("limits are on the container units"):
        box.succeed("systemctl show -P MemoryMax container@web | grep -x 268435456")
        box.succeed("systemctl show -P CPUQuotaPerSecUSec container@web | grep -x 1s")

    with subtest("a container runs as its own user range and sees no host secrets"):
        print(box.succeed(run("web", "cat /proc/self/uid_map")))
        box.succeed(run("web", "awk '$1 == 0 && $2 >= 65536' /proc/self/uid_map | grep ."))
        box.succeed(run("web", "test ! -e /run/secrets -a ! -e /etc/test-secrets -a ! -e /etc/ssh/ssh_host_ed25519_key"))
        box.succeed("test -e /etc/test-secrets/restic-password -a -e /etc/ssh/ssh_host_ed25519_key")

    with subtest("/data is the host's /var/lib/kai/guests/NAME, owned alike"):
        box.succeed(run("web", "touch /data/from-container"))
        box.succeed("stat -c %U /var/lib/kai/guests/web/from-container | grep -x root")
        box.succeed("grep 'hello from web' /var/lib/kai/guests/web/www/index.html")

    with subtest("egress none reaches nothing"):
        box.fail(run("web", "curl -sf -m 5 http://203.0.113.1/"))
        box.fail(run("web", "curl -sf -m 5 http://10.77.0.3:8081/"))
        box.succeed("timeout 5 bash -c 'echo > /dev/tcp/127.0.0.1/22'")
        box.fail(run("web", "timeout 5 bash -c 'echo > /dev/tcp/10.77.0.1/22'"))

    with subtest("egress any reaches the internet, but no other project or private address"):
        box.succeed(run("fetch", "curl -sf -m 10 http://203.0.113.1/ | grep internet"))
        box.fail(run("fetch", "curl -sf -m 5 http://10.77.0.2:8080/"))
        box.fail(run("fetch", "curl -sf -m 5 http://192.168.1.2/"))

    with subtest("the isolation holds whatever nixos-fw's forward chain accepts"):
        box.succeed("nft list chain inet kai-projects forward | grep 'priority filter - 1'")
        box.succeed("nft insert rule inet nixos-fw forward accept comment kai-test")
        box.fail(run("web", "curl -sf -m 5 http://203.0.113.1/"))
        box.fail(run("fetch", "curl -sf -m 5 http://10.77.0.2:8080/"))
        box.fail(run("fetch", "curl -sf -m 5 http://192.168.1.2/"))
        box.succeed(run("fetch", "curl -sf -m 10 http://203.0.113.1/ | grep internet"))
        handle = box.succeed("nft -a list chain inet nixos-fw forward | awk '/comment \"kai-test\"/ { print $NF }'").strip()
        box.succeed(f"nft delete rule inet nixos-fw forward handle {handle}")

    with subtest("Liton answers the site's root, its manifest to a paired device"):
        box.wait_for_unit("liton.service")
        box.wait_for_unit("caddy.service")
        box.wait_until_succeeds("curl -skf -o /dev/null https://${site}/ui/index.html", timeout=60)
        box.succeed("curl -sk -o /dev/null -w '%{http_code} %{redirect_url}' https://${site}/ | grep '^302 https://${site}/ui/index.html'")
        box.succeed("curl -sk -o /dev/null -w '%{http_code}' https://${site}/liton/v1/manifest | grep -x 401")
        box.fail("curl -sf -m 5 http://192.168.1.1:8095/")
        pairing = box.succeed("bash -lc 'liton pair'")
        print(pairing)
        assert "https://${site}/ui/index.html#pair=" in pairing
        code = pairing.split()[0]
        token = box.succeed(
            f"curl -skf https://${site}/liton/v1/pair -H 'Content-Type: application/json'"
            f" -d '{{\"code\": \"{code}\", \"name\": \"test\", \"token\": true}}' | jq -r .token"
        ).strip()
        box.succeed(f"curl -skf -H 'Authorization: Bearer {token}' https://${site}/liton/v1/manifest | jq -e '.access.role == \"operator\"'")
        setup = box.succeed("systemctl show -P Environment liton | tr ' ' '\\n' | sed -n 's/^LITON_SETUP=//p'").strip()
        box.succeed(f"jq -e '.owner == \"${owner}\" and ([.roles[].name] == [\"admin\", \"staff\", \"agent\"])' {setup}")

    with subtest("Caddy serves a project with a port under /NAME/"):
        box.wait_for_unit("caddy.service")
        box.wait_until_succeeds("curl -skf https://${site}/web/ | grep 'hello from web'", timeout=60)
        box.succeed("curl -sk -o /dev/null -w '%{redirect_url}' https://${site}/web | grep '/web/$'")
        box.fail("curl -skf https://${site}/fetch/ | grep 'hello from fetch'")
        box.succeed("curl -skf https://${site}/projects/ | grep 'href=\"/web/\"'")

    with subtest("kai-box-status lists the containers"):
        status = box.succeed("kai-box-status")
        print(status)
        box.succeed("kai-box-status | jq -e '[.guests[] | select(.state == \"active\")] | length == 2'")
        box.succeed("kai-box-status | jq -e '.guests[] | select(.name == \"web\") | .memory_mib == 256 and .memory_current > 0'")
        box.succeed("systemctl stop container@web")
        box.wait_until_fails("systemctl is-active container@web")
        box.succeed("kai-box-status | jq -e '.problems | index(\"project web is inactive\")'")
        box.succeed("kai-box-status | jq -e '(.memory.total > 0) and (.guests[] | select(.name == \"web\") | .memory_current == null)'")
        box.succeed("systemctl start container@web")
        box.succeed("kai-box-status | jq -e '.services.liton == \"active\"'")
        box.succeed("systemctl stop liton")
        box.succeed("kai-box-status | jq -e '.problems | index(\"liton is inactive\")'")
        box.succeed("systemctl start liton")

    with subtest("the backup holds the projects' data and the restore test checks it"):
        box.succeed("systemctl start restic-backups-b2")
        box.succeed("systemctl start kai-restore-test-b2")
        box.succeed("jq -e '.result == \"success\"' /var/lib/kai/status.d/restore-test-b2.json")
        box.succeed("journalctl -u kai-restore-test-b2 | grep 'restored and verified'")
        box.succeed("restic-b2 ls latest | grep -x /var/lib/kai/guests/web/from-container")
        box.succeed("restic-b2 ls latest | grep -x /data/backup/liton.sql")
        box.succeed("grep -q 'CREATE TABLE' /data/backup/liton.sql")
  '';
}
