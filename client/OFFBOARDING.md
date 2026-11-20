# Offboarding: moving the box into the customer's own account

kai needs only an SSH address, so this needs no access to the customer's
Vultr account (or any other provider's).

1. **A server of theirs.** The customer creates a Linux server with at least
   2 GB of RAM in their own account, authorizing your SSH key for root.
   Generate a new tailnet auth key (onboarding step 1), then:

   ```sh
   printf %s "$AUTH_KEY" | kai secret set box tailscale-authkey
   aion customer machine install <slug> box --to <their-ip>
   ```

   That is the same install with the same host key and secrets. The box
   rejoins the customer's tailnet as before.

2. **Data.** Make a bucket in the customer's own account, `restic copy` the
   box's repository into it, set `restic-env` to the new bucket's key, switch,
   and restore on the new box.

3. **Keys.** Add the customer's SSH key to `aion/root-keys` and their key or
   age recipient to `aion/operators`. Run `kai secret rekey box` and `kai
   machine switch box`, then confirm they can log in. Remove your key and the
   recovery recipient, then rekey and switch again. Rotate a managed AI key
   and hand over the SMS subaccount.

4. **Hand over.** Transfer this repository to the customer's organisation.
   Remove yourself as an admin of their tailnet. Run `aion customer machine
   destroy <slug> box` for the old instance in your account, and delete
   its Healthchecks check.
