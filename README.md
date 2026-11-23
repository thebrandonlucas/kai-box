# kai-box

The template every customer's Kai box is built from: NixOS modules that
customers' Kaifiles name with `InputModules("kai-box", [...])`, and `client/`,
the skeleton `aion customer new` copies into each customer's repository.

| File | What |
|---|---|
| `profiles/vultr.nix` | What a Vultr instance needs beyond kai's `Disk` and hardware facts. |
| `tailnet.nix` | Join the customer's tailnet with the `tailscale-authkey` secret; nothing open to the internet, Caddy included; console login with `root-password-hash`. |
| `backup.nix` | Nightly restic backups of `/var/lib` and `/data` to the B2 repository in `restic-env`, encrypted with `restic-password`; database dumps to `/data/backup` first; a monthly restore test. |
| `healthchecks.nix` | `kai-box-ping`, which backup.nix and status.nix use to ping the operator's Healthchecks with the `healthchecks-url` and `healthchecks-ping-key` secrets. |
| `status.nix` | `kai-box-status`, the box's status as JSON (failed units, disk, memory, revision, generation, backups, routes), pushed to Healthchecks every 15 minutes. |
| `routes.nix` | Projects under paths of the Caddy site on the box's tailnet name, from `kaiBox.routes` in `boxes/box.nix`. |
| `projects.nix` | Each project of `kaiBox.projects` (in `boxes/box.nix`) in its own NixOS container: fixed address, memory and CPU limits, no outbound network unless `egress = "any"`, no host secrets, `/data` backed up and restore-tested, and a route at `/<name>/` when it has a `port`. |
| `tests/projects.nix` | A NixOS VM test of `projects.nix` with the backup, status and routes modules: `nix-build tests/projects.nix --arg pkgs 'import <nixpkgs> { }'`. |
| `client/` | The customer's `Kaifile.roc`, `boxes/box.nix`, `revision.nix` and `ONBOARDING.md`. The `aion/` files there are placeholders, so `kai check` works in `client/` itself. |
| `flake.nix` | Empty: kai locks an `Input` as a flake. |

Customers pin a revision in their `.kai/lock.json`, and `kai update kai-box`
moves them to a new one. Move the operator's canary box first.

## Projects now, kai's Guests later

Vultr's instances have no KVM, so each project runs in a NixOS container
(systemd-nspawn) rather than a microVM. kai is getting a typed
`Guests([Guest(name, [...])])` setting for this; until it is released,
`kaiBox.projects` uses its names, so moving a project there is a rewrite
of its entry:

| `kaiBox.projects.NAME` | kai's `Guest("NAME", [...])` |
|---|---|
| `memory = 2048;` (MiB) | `Memory(2048)` |
| `cpus = 2;` | `Cpus(2)` |
| `address = "10.77.0.2";` | the address `GuestAddress("NAME")` refers to |
| `egress = "none";` / `"any"` | `Egress(None)` / `Egress(Any)` |
| `config = ...;` | `Use(...)`, `Modules`, `InputModules` |
| `port = 8080;` | a `Box.routes` entry to `GuestAddress("NAME")` |
| `/data` = `/var/lib/kai/guests/NAME` | the same directory, shared as `/data` |
