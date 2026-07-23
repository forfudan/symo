"""Expression printers.

Currently provides `to_string`, which renders an expression to infix notation
with correct operator precedence and minimal parentheses. The rendering
algorithm itself lives on `Expression.write_to` (in `symo.core`) so that `print(expr)`
and `String(expr)` work directly; `to_string` is the module's public entry
point and the place where richer formats (e.g. LaTeX) will be added.

Overloads of `to_string` also render the step-trace types (`Step`, `Trace`,
`Derivation` from `symo.steps`) to plain text; their `write_to`
implementations likewise live on the types themselves so that `print(trace)`
works directly.
"""

from symo.core.expression import Expression
from symo.steps.steps import Derivation, Step, Trace


def to_string(e: Expression) -> String:
    """Renders an expression to an infix string.

    Args:
        e: The expression to render.

    Returns:
        The infix representation, e.g. `"x**2 + 3*x - 1"`.
    """
    return String(e)


def to_string(s: Step) -> String:
    """Renders a recorded step to plain text.

    Args:
        s: The step to render.

    Returns:
        A line like `"[core] power-rule: d/dx(x**2) -> 2*x**1*d/dx(x)"`.
    """
    return String(s)


def to_string(t: Trace) -> String:
    """Renders a trace to plain text, one numbered line per step.

    Args:
        t: The trace to render.

    Returns:
        The numbered steps, or `"(no steps recorded)"` when empty.
    """
    return String(t)


def to_string(d: Derivation) -> String:
    """Renders a derivation to plain text: the steps, then the result.

    Args:
        d: The derivation to render.

    Returns:
        The numbered steps followed by a final `"=> result"` line.
    """
    return String(d)
