# A customer's Kai box. `aion customer new` copies this directory into the
# customer's own repository and writes the aion/ files: the customer's slug,
# the keys that may log in as root and the Operators who can read the
# secrets. Everything else is this file, the kai-box modules it names and
# boxes/box.nix, the customer's own projects and routes.
#
# After install the box is reached only over the customer's tailnet, as
# root@<slug>-box, so `kai machine switch box` applies a change.
app [kaifile] {
	machine: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.13/machine-2i4asMSMGmUHdfaADoxSsYyDwyKvpm6hfGdrp1DqhVc.tar.zst",
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.13/6T3kaftw9oSnAgw4KkodsGVhroQvVb2LZnxRZCqsWKek.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.13/std-H7SpbnSTMkdUqJjSYVqXiKRqQUmefutvMTC81Rv2ZYjo.tar.zst",
}

import pf.Kaifile
import std.Config
import std.Std
import machine.Machine

import "aion/name" as name : Str
import "aion/root-keys" as root_keys : Str
import "aion/operators" as operators : Str

lines = |text| text.split_on("\n").map(Str.trim).keep_if(|line| !line.is_empty())

box = "${name.trim()}-box"

project : List(Config.Setting)
project = [
	Name(name.trim()),
	Input("kai-box", "github:thebrandonlucas/kai-box"),
]

kaifile = Kaifile.new([
	Std.plugin(project),
	Machine.plugin(
		project,
		[
			Machine(
				"box",
				[
					System("x86_64-linux"),
					StateVersion("26.05"),
					HostName(box),
					Host("root@${box}"),
					User("root", [SshKeys(lines(root_keys))]),
					Ssh,
					Disk(SingleDisk("/dev/vda")),
					Operators(lines(operators)),
					Secrets([
						Secret("tailscale-authkey", []),
						Secret("root-password-hash", []),
						Secret("restic-env", []),
						Secret("restic-password", []),
						Secret("healthchecks-url", []),
						Secret("healthchecks-ping-key", []),
					]),
					InputModules("kai-box", ["profiles/vultr.nix", "tailnet.nix", "backup.nix", "status.nix"]),
					Modules(["revision.nix", "boxes/box.nix"]),
				],
			),
		],
	),
])
