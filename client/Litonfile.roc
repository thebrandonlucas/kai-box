## This customer's Liton: rooms alone, in the Sky theme, with no agents'
## sessions, code or attention to show. Liton's examples/litonfile-kai-box
## at v0.1.0, with an admin role added: the office manager's, who invites
## and removes staff in Settings → People. Staff and agents keep to the
## rooms, their UI locked.
##
## liton.setup.json beside it is what this evaluates to, which the box's
## services.liton reads. The owner is not here: kai-box's liton.nix adds
## aion/liton-owner's key. Liton publishes its setup package with no
## release yet, so this is evaluated in a checkout of Liton v0.1.0, where
## the import below resolves:
##
##   cp Litonfile.roc $LITON/examples/litonfile-kai-box/
##   (cd $LITON && liton setup examples/litonfile-kai-box)
##   cp $LITON/liton.setup.json .
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	setup: "../../setup/main.roc",
}

import pf.Stdout
import setup.Default
import setup.Setup

setup : Setup.Declared
setup = {
	..Setup.empty,
	presets: [Default.rooms],
	default_preset: Default.rooms.name,
	themes: [Default.sky],
	default_theme: Default.sky.name,
	deck: [Default.rooms.name],
	roles: [
		{ name: "admin", capabilities: ["rooms.v1", "voice.v1", "attention.v1", "people.v1"], presets: [Default.rooms.name], locked: Bool.False },
		{ name: "staff", capabilities: ["rooms.v1", "voice.v1", "attention.v1"], presets: [Default.rooms.name], locked: Bool.True },
		{ name: "agent", capabilities: ["rooms.v1"], presets: [], locked: Bool.True },
	],
}

main! = |_arguments| Stdout.line!(Setup.to_json(setup))

expect setup.presets.map(|preset| preset.name) == ["Rooms"] and setup.deck == ["Rooms"] and setup.transformers == [] and setup.roles.map(|role| role.name) == ["admin", "staff", "agent"]
