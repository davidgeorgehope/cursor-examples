# Cursor MDM baseline configs

Draft profiles for locking Cursor via MDM and file-based controls. Built from public Cursor enterprise docs and patterns used with regulated / financial-services customers. Not customer-specific.

**Sources:**
- https://cursor.com/docs/enterprise/deployment-patterns#mdm-configuration
- https://cursor.com/docs/enterprise/llm-safety-and-controls
- https://cursor.com/docs/agent/hooks
- https://cursor.com/docs/context/rules

**Before use:** Replace `YOUR_TEAM_ID` with the real team ID from https://cursor.com/dashboard. Confirm OS mix (macOS / Windows / Linux). Do not claim another named customer's exact profile externally.

---

## How to think about the layers

Two layers:

1. **MDM / device policies** — lock login, updates, workspace trust, extension allowlists (`AllowedTeamId`, `UpdateMode`, etc.).
2. **File-based agent controls** — deploy `~/.cursor/permissions.json`, optional `hooks.json` / hooks scripts, and team/project Rules.

Admin dashboard settings (model allowlists, Privacy Mode, browser origin allowlist, audit log streaming, MCP server controls) sit above both. File allowlists lose to team-dashboard allowlists when both are set.

Suggested sequence:
1. Pick a baseline tier and push MDM + `permissions.json`.
2. Later: config-as-code / change management for the same files.

---

## Tier A — Lightweight (pilot / early adopters)

**Goal:** Corporate Cursor login + sensible defaults. Minimal friction.

### MDM policies (macOS `.mobileconfig` keys)

| Policy | Value | Why |
| --- | --- | --- |
| `AllowedTeamId` | `YOUR_TEAM_ID` | Only your org team(s) can stay signed in |
| `WorkspaceTrustEnabled` | `true` | Prompt trust for new workspaces |
| `UpdateMode` | `manual` or leave unset | Users can update; IT not yet owning the channel |

Optional: omit `AllowedExtensions` until IT has a publisher list.

### `~/.cursor/permissions.json` (lightweight)

```json
{
  "terminalAllowlist": [
    "npm test",
    "npm run lint",
    "pnpm test",
    "pytest",
    "python -m pytest",
    "go test"
  ],
  "mcpAllowlist": [],
  "autoRun": {
    "block_instructions": [
      "Block commands that delete repositories, force-push to shared branches, or drop production databases."
    ]
  }
}
```

Empty `mcpAllowlist` means editor/team defaults apply. Keep MCP off or dashboard-gated until you name approved servers.

### Dashboard (lightweight)
- Privacy Mode on (org default for FS pilots).
- Auto-review as default Run Mode (Cursor 3.6+).
- No broad terminal allowlist at team level yet.

---

## Tier B — Semi-strict (recommended starting point)

**Goal:** What most FS customers land on after first security review: locked team login, IT-owned updates, workspace trust, narrow auto-run, hooks for high-risk shell.

### MDM policies

| Policy | Value | Why |
| --- | --- | --- |
| `AllowedTeamId` | `YOUR_TEAM_ID` | Forced logout if wrong team |
| `WorkspaceTrustEnabled` | `true` | Restricted mode for untrusted folders |
| `UpdateMode` | `none` | IT ships approved versions via Jamf/Intune/etc. |
| `AllowedExtensions` | `{"anysphere": true, "github": true}` | Start tight; expand publishers by exception |
| `NetworkDisableHttp2` | only if your proxy requires it | Leave unset unless needed |

### Example macOS profile fragment

```xml
<key>AllowedTeamId</key>
<string>YOUR_TEAM_ID</string>
<key>WorkspaceTrustEnabled</key>
<true/>
<key>UpdateMode</key>
<string>none</string>
<key>AllowedExtensions</key>
<string>{"anysphere":true,"github":true}</string>
```

Bundle ID (production): `com.todesktop.230313mzl4w4u92`.

Linux equivalent: `~/.cursor/policy.json` with the same keys (Cursor 2.0+). Windows: ADMX under Cursor policies.

### `~/.cursor/permissions.json` (semi-strict)

```json
{
  "terminalAllowlist": [
    "npm test",
    "npm run lint",
    "npm run typecheck",
    "pnpm test",
    "pnpm lint",
    "yarn test",
    "pytest",
    "python -m pytest",
    "go test ./...",
    "cargo test",
    "make test"
  ],
  "mcpAllowlist": [
    "github:get_pull_request",
    "github:list_pull_requests",
    "github:get_file_contents",
    "linear:get_issue",
    "linear:list_issues"
  ],
  "autoRun": {
    "allow_instructions": [
      "Allow read-only git status, diff, and log.",
      "Allow unit test and linter commands already on the allowlist."
    ],
    "block_instructions": [
      "Block any command that drops, truncates, or deletes database tables.",
      "Block force-push, hard reset of shared branches, and mass delete of files outside the repo.",
      "Block curl/wget that posts secrets or exfiltrates env files.",
      "Block package publish and production deploy commands."
    ]
  }
}
```

Trim `mcpAllowlist` to your real MCP servers. Syntax is `server:tool`, `server:*`, `*:tool`, or `*:*`.

### Hooks (semi-strict, recommended)

Deploy org hooks that:
- Deny shell matching `rm -rf`, `DROP TABLE`, `git push --force` to protected branches.
- Optionally scan prompts/files for secret-looking tokens before model send / before write.

See https://cursor.com/docs/agent/hooks for `hooks.json` layout. Example model-gate hook: https://github.com/davidgeorgehope/cursor-examples/tree/main/block-models-hook. Offer a live troubleshooting session if MDM file paths fight Jamf/Intune.

### Dashboard (semi-strict)
- Privacy Mode enforced.
- Model allowlist = approved providers only.
- Browser origin allowlist for Agent browser (if used).
- Audit log streaming to your SIEM/S3.
- MCP: only approved servers; prefer tool-level allow via dashboard + `mcpAllowlist`.
- Enable ".cursor Directory Protection" so agents cannot rewrite project rules unnoticed.

---

## Tier C — Strict (high-sensitivity / regulated pods)

**Goal:** Maximum deterministic controls. Expect more approval prompts.

### MDM policies

Same as Tier B, plus:
- `AllowedExtensions` limited to the minimum you will support (often anysphere-only until each publisher is reviewed).
- `UpdateMode`: `none` with a short approved-version pin.
- `AllowedTeamId`: comma-list only for the strict teams (split power vs standard teams if you use multiple team IDs).

### `~/.cursor/permissions.json` (strict)

```json
{
  "terminalAllowlist": [
    "npm test",
    "pytest",
    "go test ./..."
  ],
  "mcpAllowlist": [],
  "autoRun": {
    "block_instructions": [
      "Block all network-mutating commands (package publish, cloud CLIs that create or destroy resources, kubectl apply/delete).",
      "Block database migrations and any SQL that writes data.",
      "Block git push, git commit --amend, and history rewrites.",
      "Block reading or printing .env, credentials, and keychain material."
    ]
  }
}
```

Empty MCP allowlist + dashboard with no MCP servers = MCP effectively off for auto-run. Users can still be prompted depending on Run Mode; prefer dashboard disable for true off.

### Hooks (strict)
- Before shell: allowlist-only enforcement (deny everything not matching approved patterns).
- Before read: block secrets paths (`.env`, `*.pem`, keystores).
- Before submit: DLP-style scan for keys/PII (hook can call your DLP API).
- After write: block commits that introduce hardcoded credentials.

### Dashboard (strict)
- Everything in Tier B.
- Disable Agent Browser or keep a tiny origin allowlist.
- Disable or tightly gate Cloud Agents until network/DLP review.
- Codebase indexing: off or CMEK + exclude sensitive repos (walk tradeoffs with security/compliance).
- Require Auto-review or Allowlist Run Mode; do not allow "Run Everything" for strict cohort.

### Sandbox note
Cursor's local sandbox is secure-by-default for many shell commands but not a substitute for MDM + hooks. If you already sandbox via SSH into controlled Linux hosts, agents inherit those host controls. See terminal/sandbox docs for `sandbox.json` when you want file-level network/fs policy on the laptop sandbox itself.

---

## Deploy checklist (any tier)

1. Package Cursor from https://cursor.com/download into Jamf / Intune / Kandji.
2. Push MDM policy profile (`AllowedTeamId` first).
3. Write `~/.cursor/permissions.json` (and hooks) with the same tool.
4. Set `UpdateMode` to `none` if IT owns updates; verify min version floor.
5. Allowlist network domains per https://cursor.com/docs/enterprise/network-configuration.
6. Spot-check: sign-in forced to your team, untrusted workspace prompt, sample Agent command approval path, MCP blocked/allowed as designed.
7. Stream audit logs; confirm Privacy Mode.

---

## Suggested customer email blurb (optional)

> Attached are three baseline profiles (lightweight / semi-strict / strict) for locking Cursor via MDM and file-based controls (`policy` + `permissions.json` + optional hooks). Most FS teams start at semi-strict, then tighten per pod. Swap in your team ID, trim the MCP/tool allowlists to what you already trust, and we can jump on a short troubleshooting call if the MDM paths need a Jamf/Intune tweak. Config-as-code / change management for these same files can follow once the first MDM push is stable.

---

## Checklist before publishing / sending

- [ ] Replace `YOUR_TEAM_ID` with real team ID(s)
- [ ] Confirm OS mix (mac-heavy vs Windows)
- [ ] Which MCP servers are already allowed (if any)
- [ ] Whether IT will own updates (`UpdateMode=none`) from day one
- [ ] Attach official doc links only; no named-customer claims in external notes
