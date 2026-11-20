# kai-box

The template every customer's Kai box is built from: NixOS modules that
customers' Kaifiles name with `InputModules("kai-box", [...])`, and `client/`,
the skeleton `aion customer new` copies into each customer's repository.

| File | What |
|---|---|
| `profiles/vultr.nix` | What a Vultr instance needs beyond kai's `Disk` and hardware facts. |
| `tailnet.nix` | Join the customer's tailnet with the `tailscale-authkey` secret; nothing open to the internet; console login with `root-password-hash`. |
| `client/` | The customer's `Kaifile.roc`, `boxes/box.nix` and `ONBOARDING.md`. The `aion/` files there are placeholders, so `kai check` works in `client/` itself. |
| `flake.nix` | Empty: kai locks an `Input` as a flake. |

Customers pin a revision in their `.kai/lock.json`, and `kai update kai-box`
moves them to a new one. Move the operator's canary box first.
