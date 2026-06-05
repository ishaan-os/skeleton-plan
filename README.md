# skeleton-plan

A Claude Code / Cursor skill that turns "what are you about to change?" into a **code skeleton** instead of a wall of prose: a file-tree diff plus the typed signatures, docstrings, and tagged edits of everything you're adding or changing. Bodies stay stubs — the *shape* is the deliverable.

## Why

- Plans came back formatted a dozen different ways depending on the model and harness, and reading all of it was its own tax.
- "Reasonable-looking" plans kept turning into over-engineered diffs — assumptions I never agreed to, surfacing only at PR time.
- Mermaid diagrams are great for *logic*. But what I actually wanted to approve was the **structure**: which functions the agent is adding or changing, the agent's thinking expressed in types and steps, the agent's logic visible in comments. The exact execution isn't the point — the skeleton is.

It's most useful in two places: small tasks that don't warrant full plan mode but still need precision — touching the *right* things, especially critical code paths — and large plans where you want a digestible preview of the core sections before it's a 5k-line PR.

## What it produces

Rendered **right in the chat reply by default** — or written to a markdown file, or embedded as an inline `## Skeleton` section in a bigger plan. Same structure either way:

1. **File tree** — every path touched, marked `+` new / `~` modified / `-` deleted / `>` moved.
2. **Per-file skeletons** — for new files, full typed signatures + docstrings; for modified files, **only the changed members**, tagged `# [NEW]`/`# [MODIFIED]`, with a `# was:` line showing the old signature when it changes. Everything untouched is elided.
3. **Assumptions / open questions** footer.

Two fidelity levels:

| Mode | Bodies | Invoke with |
|---|---|---|
| **Default** | `...` (signature + docstring only) | `/skeleton-plan <ask>` |
| **Logic** | `...` preceded by numbered comment steps sketching the algorithm | `/skeleton-plan --logic <ask>` (or "with logic" / "verbose") |

It **investigates the real codebase first** — every signature, import, and symbol is read from the actual files, not invented — and it **never edits source files**. It outputs *only* the skeleton: no preamble, no recap, no per-file prose. The structure is the message.

## Install

### Claude Code — as a plugin (recommended)

```text
/plugin marketplace add ishaan-os/skeleton-plan
/plugin install skeleton-plan@skeleton-plan
```

That's it. Plugin skills are namespaced, so invoke it as `/skeleton-plan:skeleton-plan …` — or just ask in natural language ("skeleton-plan this change") and it triggers automatically. Update later with `/plugin marketplace update skeleton-plan`.

> The plugin ships the skill only. It does **not** auto-enable the prompt hook below — that stays opt-in (see [Stitching it in as a hook](#stitching-it-in-as-a-hook)).

### Cursor — as a skill

Cursor doesn't use Claude Code plugins; point it at the skill directory directly:

```bash
git clone https://github.com/ishaan-os/skeleton-plan
ln -s "$PWD/skeleton-plan/skills/skeleton-plan" ~/.cursor/skills/skeleton-plan
```

Then invoke it as `/skeleton-plan`. (Update later with `git -C skeleton-plan pull`.)

### Claude Code — manual skill (no plugin)

Prefer a bare `/skeleton-plan` over the namespaced plugin form? Symlink the skill instead of installing the plugin:

```bash
git clone https://github.com/ishaan-os/skeleton-plan
ln -s "$PWD/skeleton-plan/skills/skeleton-plan" ~/.claude/skills/skeleton-plan
```

## Using it

**In chat (default)** — the common case. Drop it into any request:

```
/skeleton-plan add partial refunds to the orders flow
```

It investigates the real code and renders the skeleton **right in the reply** — file tree + signatures, nothing else. No file written, no prose to wade through.

**Save it to a file** — when you want a persistent, reviewable artifact, or the change spans many files and a long chat reply gets unwieldy:

```
/skeleton-plan --file add partial refunds to the orders flow
```

It writes `~/.skeleton-plans/<date>/<slug>.md` and restates the path.

**With logic steps** — when you want to verify the algorithm, not just the contract:

```
/skeleton-plan --logic rework the dedupe pass in the search indexer
```

**Inside a larger plan** — mention it while the agent is drafting a plan-mode plan, and instead of a separate file it embeds a `## Skeleton` section directly in the plan so you approve the structure alongside the narrative.

## What it looks like in a plan

A normal plan tells you *what* and *why*. The skeleton section shows you the **shape you're approving** — so you catch an unexpected new dependency, a wrong layer, or a signature change *before* the code exists:

````markdown
## Plan — partial order refunds
Add Stripe-backed partial/full refunds for paid orders. Synchronous, no queue.

## Skeleton

### File tree
```
+ app/handlers/refund.py        NEW
~ app/routes/orders.py          + POST /orders/{id}/refund
~ app/crud/orders.py            Update.mark_refunded
- app/handlers/legacy_refund.py DELETE — superseded
```

### app/handlers/refund.py  (NEW)
```python
async def process_refund(
    order_id: UUID, amount: Decimal, session: AsyncSession,
) -> RefundResult:
    """Issue a partial or full refund for a paid order.

    Raises RefundError if amount exceeds the amount already paid.
    """
    ...
```

### app/routes/orders.py  (MODIFIED)
```python
# [MODIFIED]
# was: async def get_order(order_id: UUID) -> OrderResponse:
async def get_order(order_id: UUID, include_refunds: bool = False) -> OrderResponse:
    """Fetch an order, optionally embedding its refund history."""
    ...

# [NEW]
async def refund_order(order_id: UUID, body: RefundRequest) -> RefundResult:
    """POST /orders/{id}/refund — delegates to the refund handler."""
    ...
```

### Assumptions
- Refund is synchronous (inline Stripe call), not queued via an actor.
````

**Why it helps:** the `# was:` line flags the signature change at a glance; the `+`/`~`/`-` tree shows blast radius in four lines; and the docstrings let you sanity-check intent without reading any implementation. A full sample artifact lives in [`examples/refund-skeleton.md`](examples/refund-skeleton.md).

## Logic mode — for critical paths

On a critical path — money, auth, concurrency, idempotency — the signature isn't the risky part. The **order of the guards** is. Default fidelity shows you *that* a function captures a payment; `--logic` shows you *how*, as numbered comment steps you can approve or reject before a line of it exists:

````markdown
## app/handlers/capture.py  (NEW)
```python
async def capture_payment(
    payment_id: UUID, idempotency_key: str, session: AsyncSession,
) -> CaptureResult:
    """Capture an authorized payment exactly once.

    Safe under concurrent retries: a given idempotency_key yields the
    same result and never double-charges.
    """
    # 1. Look up idempotency_key; if a record exists, return its stored
    #    result immediately — do NOT touch the provider again.
    # 2. SELECT ... FOR UPDATE the payment row so concurrent captures
    #    of the same payment serialize here.
    # 3. Re-check state UNDER the lock: already captured -> return that;
    #    voided/expired -> raise PaymentNotCapturable.
    # 4. provider.capture(...) — the ONLY non-idempotent side effect;
    #    everything above exists to guard this one line.
    # 5. Persist captured state + idempotency record in the SAME
    #    transaction, then commit (atomic: no orphan charge).
    # 6. On ProviderError: record a terminal attempt and raise —
    #    never silently retry an unknown provider outcome.
    ...
```
````

That double-charge guard, the lock *before* the re-check, the atomic persist, the no-blind-retry rule — those are the review. None of them are visible from the signature, and you'd otherwise only catch a missing one in the PR (or in production). Full artifact: [`examples/logic-mode-payment-capture.md`](examples/logic-mode-payment-capture.md).

## Stitching it in as a hook

You can make the skeleton a default reflex instead of something you remember to type.

### Claude Code (real hook)

Claude Code's `UserPromptSubmit` hook can inject context the model sees. The script below nudges the agent to produce a skeleton on change-shaped requests — and stays quiet otherwise so it isn't noise on every message.

`~/.claude/hooks/skeleton-nudge.sh` (see [`hooks/claude/skeleton-nudge.sh`](hooks/claude/skeleton-nudge.sh)):

```bash
#!/usr/bin/env bash
set -euo pipefail
prompt=$(cat | jq -r '.prompt // ""' | tr '[:upper:]' '[:lower:]')

# Don't double up if the user already invoked the skill.
case "$prompt" in *skeleton-plan*) exit 0 ;; esac

# Only nudge on change/plan-shaped requests.
if printf '%s' "$prompt" | grep -Eq '\b(plan|implement|refactor|add|change|build|migrate|rework)\b'; then
  cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "Before proposing or writing changes, use the skeleton-plan skill: present a structural skeleton (file tree of new/modified/deleted files + typed signatures and docstrings of what you'll add or change, edits tagged with before->after signatures, bodies left as stubs). For larger plan-mode plans, embed it as an inline '## Skeleton' section."
  }
}
JSON
fi
```

Then `chmod +x ~/.claude/hooks/skeleton-nudge.sh` and register it in `~/.claude/settings.json` (user-level) or `.claude/settings.json` (per-project) — see [`hooks/claude/settings.snippet.json`](hooks/claude/settings.snippet.json):

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/skeleton-nudge.sh", "timeout": 5 } ] }
    ]
  }
}
```

### Cursor (rule — the hook-equivalent)

Cursor's prompt hook (`beforeSubmitPrompt`) is **informational only** — it can't inject instructions back into the agent, so a hook can't nudge behavior here. The Cursor-native way to make this automatic is a **Rule**.

`.cursor/rules/skeleton-plan.mdc` (see [`hooks/cursor/skeleton-plan.mdc`](hooks/cursor/skeleton-plan.mdc)):

```markdown
---
description: For change/precision tasks, lead with a code skeleton (file tree + typed signatures) before writing implementation.
alwaysApply: false
---

When asked to plan, propose, or implement changes, first use the skeleton-plan skill:
present a file-tree diff (new/modified/deleted) plus typed signatures and docstrings
of the functions/classes you'll add or change — edits tagged with before->after
signatures, bodies left as stubs. Only write full implementations after the skeleton
is acknowledged. For larger plans, embed it as an inline "## Skeleton" section.
```

Set `alwaysApply: true` to attach it to every request, or keep it `false` and let the description pull it in for relevant tasks. Drop it in `.cursor/rules/` (per-project) or your global rules.

## License

MIT
