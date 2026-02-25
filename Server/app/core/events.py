from typing import Any, Callable, Dict, List
import asyncio

# Simple in-process event emitter for decoupling concerns
_subscribers: Dict[str, List[Callable[..., Any]]] = {}


def subscribe(event_name: str, callback: Callable[..., Any]) -> None:
    """Register a callback for the given event name.

    Callbacks may be normal functions or coroutines. They are executed in the
    order they were registered when the event is emitted.
    """
    _subscribers.setdefault(event_name, []).append(callback)


async def emit(event_name: str, *args: Any, **kwargs: Any) -> None:
    """Emit an event asynchronously.

    All registered callbacks for ``event_name`` are invoked. If a callback is
    a coroutine function it will be ``await``ed; otherwise it is executed
    synchronously.
    """
    handlers = list(_subscribers.get(event_name, []))
    for handler in handlers:
        try:
            if asyncio.iscoroutinefunction(handler):
                await handler(*args, **kwargs)
            else:
                handler(*args, **kwargs)
        except Exception:
            # swallow exceptions to avoid a single subscriber breaking the
            # emitter; subscribers are responsible for their own logging
                    pass


def clear_subscribers() -> None:
    """Remove all registered event handlers (used by tests to reset state)."""
    _subscribers.clear()
