# Skeleton — partial order refunds

Add Stripe-backed partial/full refunds for paid orders. Synchronous (inline provider call), no queue.

## File tree
```
+ app/handlers/refund.py            NEW
+ app/schemas/refund.py             NEW
~ app/routes/orders.py              + POST /orders/{id}/refund, get_order gains include_refunds
~ app/crud/orders.py                Fetch.refundable_total, Update.mark_refunded
~ app/providers/stripe.py           + refund()
- app/handlers/legacy_refund.py     DELETE — superseded by handlers/refund.py
```

## app/schemas/refund.py  (NEW)
```python
class RefundRequest(BaseModel):
    """Body for POST /orders/{id}/refund."""
    amount: Decimal  # must be > 0 and <= amount paid

class RefundResult(BaseModel):
    """Outcome of a refund attempt."""
    order_id: UUID
    status: OrderStatus
    refunded_total: Decimal
```

## app/handlers/refund.py  (NEW)
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
        RefundResult with the new status and cumulative refunded total.
    Raises:
        RefundError: amount exceeds paid total, or order is not refundable.
    """
    ...
```

## app/crud/orders.py  (MODIFIED)
```python
class Fetch:
    # … unchanged …

    # [NEW]
    async def refundable_total(self, order_id: UUID, session: AsyncSession) -> Decimal:
        """Amount paid minus amount already refunded for the order."""
        ...

class Update:
    # … unchanged …

    # [NEW]
    async def mark_refunded(
        self, order_id: UUID, refunded_total: Decimal, session: AsyncSession
    ) -> None:
        """Persist the cumulative refunded total and updated order status."""
        ...
```

## app/providers/stripe.py  (MODIFIED)
```python
# [NEW]
async def refund(payment_intent_id: str, amount: Decimal) -> StripeRefund:
    """Create a Stripe refund against a payment intent. Raises StripeError on failure."""
    ...
```

## app/routes/orders.py  (MODIFIED)
```python
# [MODIFIED]
# was: async def get_order(order_id: UUID) -> OrderResponse:
async def get_order(order_id: UUID, include_refunds: bool = False) -> OrderResponse:
    """Fetch an order, optionally embedding its refund history."""
    ...

# [NEW]
async def refund_order(order_id: UUID, body: RefundRequest) -> RefundResult:
    """POST /orders/{id}/refund — delegates to handlers.refund.process_refund."""
    ...
```

## Assumptions
- Refund is synchronous (inline Stripe call), not queued via a Dramatiq actor.
- Partial refunds allowed; over-refunding is rejected in `process_refund`, not at the route layer.
