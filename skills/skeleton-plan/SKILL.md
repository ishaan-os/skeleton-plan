---
name: skeleton-plan
description: Use when the user wants a structural skeleton of a proposed change — file-tree changes (new/modified/deleted files) plus in-file skeletons (typed signatures, docstrings, tagged edits) at code-review fidelity — instead of, or alongside, a prose plan or flow diagram. Triggers on "/skeleton-plan", "skeleton", "show me the file changes / signatures / stubs", or a request to include a skeleton inside a larger plan-mode plan.
---

# skeleton-plan

Produce a **structural skeleton** of a proposed change: the *shape* of the code, not the narrative. A flow diagram shows control flow; a prose plan shows intent and milestones. Neither shows the actual file tree that will change or the typed signatures, docstrings, and edits that reviewers reason about. This skill fills that gap so plan approval and later code review are faster.

The precise implementation is deliberately omitted — bodies are stubs. The deliverable is enough structure (tree + signatures + docstrings) to understand and approve the *shape* of the change.

## Core principle

**Render real findings, not invented ones.** Investigate the actual codebase first. Every signature, import path, type, and existing class/function name in the skeleton must be real — read from the files, not guessed. The artifact is a render of what you found, not a discovery tool. If you haven't read the relevant code, you cannot write the skeleton yet.

**Never edit real source files.** This skill produces a documentation artifact only. No stub files in the repo tree, no `git` changes to source.

## Two entry points, one format

| Trigger | Behavior |
|---|---|
| **Standalone** — user drops `/skeleton-plan <ask>` in a request | Investigate, then write a self-contained markdown file (see *Output*) and restate its path so the user can open or review it. |
| **Inside a larger plan** — user mentions `/skeleton-plan` while you're drafting a plan-mode plan | Do NOT write a separate file. Embed the skeleton as an inline `## Skeleton` section in the single plan markdown you're already producing, using the same format below. |

## Fidelity levels

Default to **lean**. Bump only when asked.

- **Default — docstring only.** Each member: typed signature + a full docstring (purpose, args, returns, raises). Body is `...`. Nothing else.
- **Logic mode** — triggered by `--logic`, "with logic", "verbose", or "sketch the logic". Same as default, plus **numbered comment steps** inside each body sketching the algorithm and key branch / error points. Still no real expressions — comments only.

## Workflow

1. **Scope the ask.** Identify which files are touched: new, modified, deleted, moved. If the ask is vague about scope, state your assumption in one line and proceed (don't stall).
2. **Investigate.** Read the real files you'll modify. For modified files, note the *current* signature of anything you'll change. Match the repo's existing conventions — its directory layout, layering, and naming — and place new code where analogous code already lives.
3. **Write the skeleton** in the structure below.
4. **Standalone only:** write the file and restate its path so the user can open or review it.

## Output structure

A markdown document with these sections:

### 1. Title + objective
One `#` title and a single sentence stating what the change accomplishes.

### 2. File tree
A flat list of every path touched, each with a marker and a terse note:

```
+ api/app/handlers/refund.py            NEW
~ api/app/routes/orders.py              + POST /orders/{id}/refund
~ api/app/crud/orders.py                Fetch.refundable_total, Update.mark_refunded
- api/app/handlers/legacy_refund.py     DELETE — folded into handlers/refund.py
> api/app/schemas/refund.py             MOVED from schemas/orders_refund.py
```

Markers: `+` new, `~` modified, `-` deleted, `>` moved/renamed.

### 3. Per-file skeletons
One block per touched file (deleted files need no block — the tree line + reason is enough). Header is the path and its status:

- **NEW file** → full skeleton: every class/function as a typed signature + docstring.
- **MODIFIED file** → **changed members only.** Tag each with a `# [NEW]` or `# [MODIFIED]` comment. Elide everything untouched with `# … unchanged …`. For a **changed signature**, show the old one on a `# was:` line directly above the new signature.
- **MOVED file** → note source path; show skeleton only if its contents also change.

### 4. Assumptions / open questions
A short footer listing anything you assumed about scope or anything a reviewer should decide. Keep it tight; omit if there's nothing real to flag.

## Example (default fidelity)

````markdown
# Skeleton — partial order refunds

Add Stripe-backed partial/full refunds for paid orders.

## File tree
```
+ api/app/handlers/refund.py        NEW
~ api/app/routes/orders.py          + POST /orders/{id}/refund
~ api/app/crud/orders.py            Update.mark_refunded
- api/app/handlers/legacy_refund.py DELETE — superseded
```

## api/app/handlers/refund.py  (NEW)
```python
async def process_refund(
    order_id: UUID,
    amount: Decimal,
    session: AsyncSession,
) -> RefundResult:
    """Issue a partial or full refund for a paid order.

    Args:
        order_id: order to refund.
        amount: amount to refund; must be <= amount already paid.
        session: active DB session (caller owns the transaction).
    Returns:
        RefundResult with new status and cumulative refunded total.
    Raises:
        RefundError: amount exceeds paid total or order not refundable.
    """
    ...
```

## api/app/crud/orders.py  (MODIFIED)
```python
class Update:
    # … unchanged …

    # [NEW]
    async def mark_refunded(
        self, order_id: UUID, refunded_total: Decimal, session: AsyncSession
    ) -> None:
        """Persist the cumulative refunded total and updated order status."""
        ...
```

## api/app/routes/orders.py  (MODIFIED)
```python
# [MODIFIED]
# was: async def get_order(order_id: UUID) -> OrderResponse:
async def get_order(order_id: UUID, include_refunds: bool = False) -> OrderResponse:
    """Fetch an order, optionally embedding its refund history."""
    ...

# [NEW]
async def refund_order(order_id: UUID, body: RefundRequest) -> RefundResult:
    """POST /orders/{id}/refund — issue a refund via the refund handler."""
    ...
```

## Assumptions
- Refunds are synchronous (Stripe call inline), not queued via an actor.
````

In **logic mode**, each `...` body is preceded by numbered steps, e.g.:

```python
    # 1. Fetch order + payment; 404 if missing
    # 2. Guard amount <= paid_total, else raise RefundError
    # 3. provider.stripe.refund(payment_intent, amount)
    # 4. Update.mark_refunded(...) and recompute status
    # 5. Return RefundResult(status, refunded_total)
    ...
```

## File location (standalone)

Default: `~/.skeleton-plans/<YYYY-MM-DD>/<slug>.md` (home-dir, dated, harness-agnostic, never pollutes the repo). Create the dated directory if needed (`mkdir -p`), derive `<slug>` from the objective. This is just a default — change it to wherever you keep working notes.

## Common mistakes

| Mistake | Fix |
|---|---|
| Inventing signatures/imports without reading the code | Investigate first. The skeleton must reflect real symbols. |
| Writing full implementations | Bodies are `...` (or `...` + numbered comments in logic mode). If you're writing real expressions, stop. |
| Dumping whole modified files | Show changed members only; elide the rest with `# … unchanged …`. |
| Hiding a signature change | Always show the old signature on a `# was:` line above the new one. |
| Creating stub files in the repo | This skill writes ONE markdown doc. It never touches source files. |
| Writing a separate file during plan mode | Inside a larger plan, embed an inline `## Skeleton` section instead. |
