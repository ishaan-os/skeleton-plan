# Skeleton (logic mode) — idempotent payment capture

Capture an authorized payment exactly once, safe under concurrent retries.

## File tree
```
+ app/handlers/capture.py        NEW
~ app/crud/payments.py           Fetch.lock_for_update, Create.idempotency_record
~ app/routes/payments.py         + POST /payments/{id}/capture
```

## app/handlers/capture.py  (NEW)
```python
async def capture_payment(
    payment_id: UUID,
    idempotency_key: str,
    session: AsyncSession,
) -> CaptureResult:
    """Capture an authorized payment exactly once.

    Safe to call concurrently and to retry: a given idempotency_key yields
    the same CaptureResult and never double-charges.

    Args:
        payment_id: the authorized payment to capture.
        idempotency_key: client-supplied key; identical keys are deduped.
        session: active DB session (this handler owns the transaction).
    Returns:
        CaptureResult with the settled amount and provider charge id.
    Raises:
        PaymentNotCapturable: payment is voided, expired, or already settled.
        ProviderError: the gateway call failed in a non-retriable way.
    """
    # 1. Look up idempotency_key. If a record exists, return its stored
    #    CaptureResult immediately — do NOT call the provider again.
    # 2. Open a transaction and SELECT ... FOR UPDATE the payment row, so
    #    concurrent captures of the same payment serialize at this point.
    # 3. Re-read state UNDER the lock: already captured -> store + return
    #    that result; voided/expired -> raise PaymentNotCapturable.
    # 4. Call provider.capture(auth_token, amount). This is the ONLY
    #    non-idempotent side effect — every step above exists to guard it.
    # 5. On success: persist captured state + write the idempotency record
    #    in the SAME transaction, then commit (atomic: no orphan charge).
    # 6. On ProviderError: mark the attempt terminal, commit that fact,
    #    and raise — never silently retry an unknown provider outcome.
    ...
```

## app/crud/payments.py  (MODIFIED)
```python
class Fetch:
    # … unchanged …

    # [NEW]
    async def lock_for_update(self, payment_id: UUID, session: AsyncSession) -> Payment:
        """Row-lock the payment (SELECT ... FOR UPDATE) for serialized capture."""
        ...

class Create:
    # … unchanged …

    # [NEW]
    async def idempotency_record(
        self, key: str, result: CaptureResult, session: AsyncSession
    ) -> None:
        """Persist the capture outcome keyed by idempotency_key (unique-constrained)."""
        ...
```

## app/routes/payments.py  (MODIFIED)
```python
# [NEW]
async def capture(payment_id: UUID, idempotency_key: str = Header(...)) -> CaptureResult:
    """POST /payments/{id}/capture — delegates to handlers.capture.capture_payment."""
    ...
```

## Assumptions
- `idempotency_key` is unique-constrained; a duplicate insert is the last-resort concurrency backstop behind the row lock.
- The provider's capture is not idempotent on its own, so step 1's cached result is mandatory, not an optimization.
- Capture is synchronous; partial captures are out of scope (full amount only).
