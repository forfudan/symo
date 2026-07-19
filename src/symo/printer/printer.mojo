"""Expression printers.

Currently provides `to_string`, which renders an expression to infix notation
with correct operator precedence and minimal parentheses. The rendering
algorithm itself lives on `Expression.write_to` (in `symo.core`) so that `print(expr)`
and `String(expr)` work directly; `to_string` is the module's public entry
point and the place where richer formats (e.g. LaTeX) will be added.
"""

from symo.core.expression import Expression


def to_string(e: Expression) -> String:
    """Renders an expression to an infix string.

    Args:
        e: The expression to render.

    Returns:
        The infix representation, e.g. `"x**2 + 3*x - 1"`.
    """
    return String(e)
