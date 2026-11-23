# Onboarding

Work through this in the customer's repository. kai refuses to build the box
while a secret it declares is missing, so nothing is billed before 1, 2, 4
and 5 are done.

First lock the repository's inputs: `kai secret set` needs the lock
file, so run this before any of the steps below.

```sh
kai update
```

- [ ] **1. Tailnet.** The customer creates a Tailscale tailnet and invites
  you as an Admin. In its access controls add

  ```json
  "tagOwners": {
    "tag:kai-box": ["autogroup:admin"],
    "tag:<operator-tag>": ["autogroup:admin"]
  },
  "grants": [
    { "src": ["autogroup:admin", "tag:<operator-tag>"], "dst": ["tag:kai-box"], "ip": ["*"] },
    { "src": ["autogroup:member"], "dst": ["tag:kai-box"], "ip": ["tcp:80", "tcp:443"] }
  ]
  ```

  `tag:<operator-tag>` is the tag your own device joins the tailnet with,
  such as `tag:dev`. A tagged device belongs to its tag, not to you, so it
  is not in `autogroup:admin` even though you are: without the tag in the
  first grant your device cannot reach the box. Tailscale refuses a policy
  naming a tag `tagOwners` does not declare, hence its entry there. Leave it
  out if your device is not tagged.

  The second grant lets the customer's staff reach the box's web services,
  and nothing else on it. Under DNS, turn on MagicDNS and **HTTPS
  Certificates**: Caddy serves the projects at
  `https://<slug>-box.<tailnet>/<project>/` with a certificate from
  Tailscale.

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

- [ ] **4. Backups.** In Backblaze B2 (not Vultr, so one provider's outage
  or a closed account can't take the backups with the box), make a private
  bucket for this customer and an application key that can read and write
  only that bucket. Then write the repository and the key, and make the
  restic password. Keep the password in your password manager too: without
  it no backup can be restored.

  ```sh
  printf '%s\n' \
    "RESTIC_REPOSITORY=s3:https://$B2_S3_ENDPOINT/$BUCKET/<slug>" \
    "AWS_ACCESS_KEY_ID=$KEY_ID" \
    "AWS_SECRET_ACCESS_KEY=$APPLICATION_KEY" \
    | kai secret set box restic-env
  head -c 32 /dev/urandom | base64 | kai secret set box restic-password
  ```

  `$B2_S3_ENDPOINT` is the bucket's S3 endpoint, such as
  `s3.us-east-005.backblazeb2.com`. The box backs up `/var/lib` and `/data`
  every night at about 03:00, keeping 7 daily, 5 weekly and 12 monthly
  snapshots, and restores the latest snapshot once a month to test it.

- [ ] **5. Status.** The box pings your Healthchecks: its status every 15
  minutes, each backup and each monthly restore test. Its checks are
  created on their first ping, named `<slug>-box-status`,
  `<slug>-box-backup-b2` and `<slug>-box-restore-test-b2`, in the project
  whose ping key the box holds. Give the box Healthchecks' ping URL and
  that project's ping key (Project Settings → Ping key):

  ```sh
  printf %s "https://$HEALTHCHECKS_HOST/ping" | kai secret set box healthchecks-url
  printf %s "$PING_KEY" | kai secret set box healthchecks-ping-key
  ```

  After the first pings arrive, set each check's period: status 15 minutes
  with 15 minutes' grace, backup 1 day with 6 hours', and restore test
  `0 0 1 * *` (cron) with 1 day's. The status ping's body is the box's
  status as JSON, which Healthchecks keeps; on the box `kai-box-status`
  prints it.

- [ ] **6. SMS (only if the box sends texts).** A2P 10DLC through the SMS
  provider, under the customer's own brand (a subaccount) so it can leave
  with them. Brand registration needs their legal name, EIN, address and a
  website with a privacy policy and SMS terms. Campaign registration needs the
  use case (such as appointment reminders), sample messages and the opt-in
  flow. Allow 1–3 weeks. The provider's token is a secret declared in
  `boxes/box.nix`.

- [ ] **7. Install.**

  ```sh
  aion customer machine new <slug> box
  git add -A && git commit -m "Install the box"
  ```

  Then check that the box is on the tailnet and at the collector. A join
  that failed or timed out has usually consumed the single-use auth key:
  generate a new one and set it as in step 1 before installing again.

- [ ] **8. Liton.** The staff's rooms are at the site's root,
  `https://<slug>-box.<tailnet>/`, for devices on the tailnet alone. The
  roles are `Litonfile.roc`'s: `admin` (the office manager, who invites and
  removes staff), `staff` and `agent`. Change it in a Liton v0.1.0
  checkout as its header says, and commit the `liton.setup.json` it gives.

  Pair your own device first, as an operator. On the box, `liton pair`
  prints a code and a link on the site, good for 10 minutes:

  ```sh
  ssh root@<slug>-box liton pair
  ```

  Open the link on your device and open the Rooms, which makes the
  browser's key. Then make that key the owner, an operator no one can
  remove:

  ```sh
  ssh root@<slug>-box "sqlite3 /var/lib/liton/liton.db \"SELECT name, pubkey FROM devices WHERE pubkey != ''\""
  echo <your pubkey> > aion/liton-owner
  git commit -am "Make the operator Liton's owner" && kai machine switch box
  ```

  Invite the office manager in Settings → People: their name, the `admin`
  role and the rooms they sign into. Send them the link it shows; it works
  once, within 7 days. They invite the staff the same way, as `staff`, or
  you do.

  Each person opens their link, and later `https://<slug>-box.<tailnet>/`,
  on a device signed in to the customer's tailnet with the Tailscale app;
  their phone can add it to the home screen. Anywhere else the name does
  not resolve.

  Liton has no command to create rooms yet. When it does, creating the
  customer's first rooms (such as `#office` and `#dispatch`) belongs here,
  before the invites that name them.
