# Secrets reference

## Components

| Component | Contract |
| --- | --- |
| `secrets` capability | Verify the 1Password CLI (nixpkgs-owned); do not inspect authentication or vault state |
| Configured vault | `$WORKSTATION_VAULT` — dedicated scope for this workstation's secrets |
| `/skill:secrets` | Explicit-only policy for safe metadata, references, and approved mutations |
| Declared source | Store `op://` references and non-secret schema only |

The capability name describes the workstation concern; 1Password is its current
backend. The desktop application, account session, and vault contents remain
host-owned mutable state.

## Boundaries

- Normal apply, sync, verify, and CI never require vault authentication.
- Never commit or render secret values into persistent configuration.
- Prefer `op run` or `op inject` over retrieving values into agent context.
- Enter secret-reference/vault work only when the user explicitly invokes `/skill:secrets`; other skills must request that invocation, not invoke it automatically.
- Scope every operation to `$WORKSTATION_VAULT`.
- Require explicit user approval for each create, edit, archive, or delete.
- Use a vault-scoped service account when technical enforcement is required on a headless host.

## Desktop authentication

```text
Unlock 1Password
  -> Settings > Developer > Integrate with 1Password CLI
  -> op whoami
```

## Headless setup

Interactive account sessions do not exist on headless hosts. Use a vault-scoped
service account instead:

1. Create a service account at 1Password.com (Developer tools -> Service
   accounts). Permissions are immutable after creation: grant
   `$WORKSTATION_VAULT` with read and write access at creation time.
2. Place the token in a root-only env file (mode 0600) at the capability's
   `workstation.secrets.envFile` (default `/etc/workstation/secrets.env`;
   per-host override in the machine file's settings):

   ```bash
   read -rs OP_SA_TOKEN
   printf 'OP_SERVICE_ACCOUNT_TOKEN=%s\n' "$OP_SA_TOKEN" > /etc/workstation/secrets.env
   chmod 600 /etc/workstation/secrets.env && unset OP_SA_TOKEN
   ```

3. The session env sources the file in login shells when it exists (the
   source line is guarded with `[ -r … ]`; an absent file is inert).

These are operator-run steps, not commands for an agent to execute. Values never
enter Git, agent context or chat; the root-only env file stays the live
mechanism and the vault is the recovery source of truth. Service account tokens
cannot be rotated in place; revoke and recreate the account to change access.

## Authentication recovery

Within an explicitly invoked secrets workflow, failed authentication/vault checks
stop further operations. Desktop users should unlock the app and restore CLI
integration. Headless operators should restore their service-account environment
and vault permissions out of band, recreating the account if necessary.
Never ask for or inspect the token value, print account/vault details, or start
an interactive sign-in flow. A missing `op` is an installation issue; use the
[install guide](../README.md), not an implicit authentication-time install.
Normal lifecycle verification remains version-only.

## Vault items

Items are host inventory, not source: each host's items (its notification
bridge, deploy panels, game servers, API keys) live in the configured vault
with stable names, non-secret fields declared here only when a substrate
surface consumes them, secret fields populated in the 1Password application.
Agents never copy values between a host file and the vault.

## Reference form

`<vault>` = `$WORKSTATION_VAULT`. Use stable item and field names:

```dotenv
<UPPER_SNAKE_KEY>=op://<vault>/<item>/<field>
```

Consume references without exposing resolved values:

```bash
op run --env-file ~/.config/workstation/secrets.env -- <command>
```

No consumer-specific secret reference is managed until its item schema and
launch path are deliberately added.
