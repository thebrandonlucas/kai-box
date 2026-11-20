# Onboarding

Work through this in the customer's repository. kai refuses to build the box
while a secret it declares is missing, so nothing is billed before 1–2 are
done.

- [ ] **1. Tailnet.** The customer creates a Tailscale tailnet and invites
  you as an Admin. In its access controls add

  ```json
  "tagOwners": { "tag:kai-box": ["autogroup:admin"] },
  "grants": [{ "src": ["autogroup:admin"], "dst": ["tag:kai-box"], "ip": ["*"] }]
  ```

  Under Settings → Keys, generate an auth key: **pre-approved, tagged
  `tag:kai-box`, not ephemeral, not reusable.** Tagged devices have key
  expiry off. Write the tailnet's MagicDNS suffix (such as `tail1234.ts.net`)
  to `aion/tailnet`, then:

  ```sh
  printf %s "$AUTH_KEY" | kai secret set box tailscale-authkey
  ```

  The key is single-use: installing again needs a new one.

- [ ] **2. Console password**, for Vultr's web console when the tailnet is
  down. Keep the password in your password manager.

  ```sh
  mkpasswd -m yescrypt | kai secret set box root-password-hash
  ```

- [ ] **3. AI key.** Either the customer's own Anthropic Console org (they
  add you as a developer, create a `kai-box` workspace with a spend limit and
  issue its key), or a key from your org's workspace for this customer, with
  a cap. It becomes the `anthropic-api-key` secret once the box runs Liton.

- [ ] **4. Backups.** A bucket at a provider other than Vultr and a key
  scoped to it, and a restic password kept in your password manager. They
  become the `restic-env` and `restic-password` secrets with kai-box's
  backup module.

- [ ] **5. Status.** A check in Healthchecks for this box; its ping URL
  becomes the `status-ping-url` secret with kai-box's status module.

- [ ] **6. SMS (only if the box sends texts).** A2P 10DLC through the SMS
  provider, under the customer's own brand (a subaccount) so it can leave
  with them. Brand registration needs their legal name, EIN, address and a
  website with a privacy policy and SMS terms. Campaign registration needs the
  use case (such as appointment reminders), sample messages and the opt-in
  flow. Allow 1–3 weeks. The provider's token is a secret declared in
  `boxes/box.nix`.

- [ ] **7. Install.**

  ```sh
  kai update
  aion customer machine new <slug> box
  git add -A && git commit -m "Install the box"
  ```

  Then check that the box is on the tailnet and at the collector.
