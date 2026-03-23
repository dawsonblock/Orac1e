"""lifecycle.py — Centralised run state machine for Oracle Build.

All status mutations in the control plane must go through ``transition()``
rather than setting ``run["status"]`` directly.  This gives a single place
to audit, log, and enforce the allowed state graph.

Valid transition graph::

    created ──► retrieving ──► proposing ──► validating ──► awaiting_approval
                                                                   │       │
                                                               applied  rejected
    Any non-terminal state ──► failed (error path)
"""
from __future__ import annotations

from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from typing import Any

# ---------------------------------------------------------------------------
# State graph
# ---------------------------------------------------------------------------

#: Maps each state to the list of states it may legally transition into.
#: The ``failed`` target is allowed from every non-terminal state and is
#: handled specially in :func:`transition` rather than listed exhaustively.
VALID_TRANSITIONS: dict[str, list[str]] = {
    "created":           ["retrieving", "failed"],
    "retrieving":        ["proposing", "failed"],
    "proposing":         ["validating", "failed"],
    "validating":        ["awaiting_approval", "failed"],
    "awaiting_approval": ["applied", "rejected", "failed"],
}

#: States from which no further transitions are permitted.
TERMINAL_STATES: frozenset[str] = frozenset({"applied", "rejected", "failed"})


# ---------------------------------------------------------------------------
# Error type
# ---------------------------------------------------------------------------

class TransitionError(ValueError):
    """Raised when an invalid or disallowed state transition is attempted."""


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def transition(run: "dict[str, Any]", new_state: str) -> None:
    """Mutate ``run['status']`` to *new_state* after validating the transition.

    Rules:
    * Same-state → same-state is a no-op (idempotent).
    * Any non-terminal state may transition to ``'failed'``.
    * Terminal → any other state raises :class:`TransitionError`.
    * Any transition not listed in :data:`VALID_TRANSITIONS` raises
      :class:`TransitionError`.

    Args:
        run:       The run dict whose ``'status'`` key will be mutated.
        new_state: The desired next state.

    Raises:
        TransitionError: If the transition is not permitted.
    """
    current = run.get("status")

    # Idempotent: already in the desired state.
    if current == new_state:
        return

    # Terminal states cannot transition further.
    if current in TERMINAL_STATES:
        raise TransitionError(
            f"Cannot transition from terminal state {current!r} to {new_state!r}"
        )

    allowed = VALID_TRANSITIONS.get(current, [])
    if new_state not in allowed:
        allowed_display = allowed or "(none — unknown state)"
        raise TransitionError(
            f"Invalid transition {current!r} → {new_state!r}; "
            f"allowed from {current!r}: {allowed_display}"
        )

    run["status"] = new_state


def is_terminal(run: "dict[str, Any]") -> bool:
    """Return ``True`` if the run is in a terminal state."""
    return run.get("status") in TERMINAL_STATES


def assert_state(run: "dict[str, Any]", *expected: str) -> None:
    """Raise :class:`TransitionError` if the run is not in one of *expected* states.

    Useful for guard clauses at the top of promotion/rejection handlers.
    """
    current = run.get("status")
    if current not in expected:
        raise TransitionError(
            f"Expected run to be in state {expected!r}, got {current!r}"
        )
