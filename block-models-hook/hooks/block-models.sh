#!/bin/bash
# Blocks prompts and subagents whose model matches BLOCKED_MODEL_PATTERNS.
# Registered for beforeSubmitPrompt and subagentStart in ~/.cursor/hooks.json.
set -euo pipefail

# Case-insensitive jq regexes, matched against the model slug (e.g. cursor-grok-4.7)
# and the catalog model id. Every entry of a multi-model selection is checked.
BLOCKED_MODEL_PATTERNS='["grok", "(^|[^a-z])xai([^a-z]|$)"]'

# Cursor launched from the Dock may not have Homebrew on PATH; macOS ships /usr/bin/jq.
JQ=$(command -v jq || true)
JQ=${JQ:-/usr/bin/jq}
if [[ ! -x "$JQ" ]]; then
  echo "block-models: jq not found; blocking" >&2
  exit 2
fi

"$JQ" -c --argjson patterns "$BLOCKED_MODEL_PATTERNS" '
  (.hook_event_name // (if has("subagent_id") then "subagentStart" else "beforeSubmitPrompt" end)) as $event
  | (if $event == "subagentStart" then [.subagent_model] else [.model, .model_id] end)
  | [.[] | strings | split(",")[] | gsub("^\\s+|\\s+$"; "")]
  | map(select(. as $model | any($patterns[]; . as $pattern | $model | test($pattern; "i"))))
  | first as $blocked
  | if $event == "subagentStart" then
      if $blocked then
        {permission: "deny", user_message: "Subagent blocked: \($blocked) is on your blocked-models list (~/.cursor/hooks/block-models.sh)."}
      else
        {permission: "allow"}
      end
    else
      if $blocked then
        {continue: false, user_message: "Blocked: \($blocked) is on your blocked-models list (~/.cursor/hooks/block-models.sh). Pick another model and resend."}
      else
        {continue: true}
      end
    end
'
