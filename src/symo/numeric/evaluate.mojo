# ===----------------------------------------------------------------------=== #
#
# Copyright 2026 Yuhao Zhu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ===----------------------------------------------------------------------=== #

"""Implements substitution (`substitute`) and numeric evaluation (`evaluate`).

`substitute(expression, variable, replacement)` returns a copy of `expression` with every
`Symbol` named `variable` replaced by `replacement`. It is purely structural:
no simplification is applied, so the caller can `simplify` the result if
wanted.

`evaluate(expression, precision)` collapses an expression tree to a single Decimo
`BigDecimal` with `precision` significant digits, dispatching each elementary
`Function` node to its Decimo implementation. Every free symbol must have been
substituted away first; a surviving symbol is an error, since it has no numeric
value.

Both share the canonical-form assumptions of `core`: subtraction is `+ (-1)*`
and division is `* **(-1)`, so `evaluate` only needs to handle the six node
kinds, with `Power` covering reciprocals via a negative exponent.
"""

from decimo import BigDecimal
from decimo.bigdecimal.exponential import exp, ln, power, sqrt
from decimo.bigdecimal.trigonometric import cos, sin

from symo.core.expression import Expression, ExpressionKind

# The default precision (in significant digits) used by `evaluate` when the
# caller does not request one. Matches Decimo's own default context precision.
comptime _DEFAULT_PRECISION: Int = 28


# ===----------------------------------------------------------------------=== #
# Substitution
# ===----------------------------------------------------------------------=== #


def substitute(
    expression: Expression, variable: String, replacement: Expression
) raises -> Expression:
    """Substitutes every occurrence of a symbol with an expression.

    The substitution is structural and does not simplify the result; pass the
    output through `simplify` if a reduced form is wanted.

    Args:
        expression: The expression to substitute into.
        variable: The name of the symbol to replace.
        replacement: The expression to put in its place.

    Returns:
        A copy of `expression` with every `Symbol` named `variable` replaced.

    Raises:
        Error: If an internal operation fails.
    """
    var k = expression.kind()
    if k == ExpressionKind.SYMBOL:
        if expression.name() == variable:
            return replacement.copy()
        return expression.copy()
    if k == ExpressionKind.NUMBER:
        return expression.copy()

    var new_arguments = List[Expression]()
    for i in range(expression.num_arguments()):
        new_arguments.append(
            substitute(expression.argument(i), variable, replacement)
        )

    if k == ExpressionKind.ADD:
        return Expression.add(new_arguments^)
    if k == ExpressionKind.MULTIPLY:
        return Expression.multiply(new_arguments^)
    if k == ExpressionKind.POWER:
        return Expression.power(new_arguments[0], new_arguments[1])
    if k == ExpressionKind.FUNCTION:
        return Expression.function(expression.name(), new_arguments^)
    return expression.copy()


def substitute(
    expression: Expression, variable: String, value: BigDecimal
) raises -> Expression:
    """Substitutes a symbol with a Decimo `BigDecimal` value.

    A convenience overload equivalent to substituting `Expression.number(value)`.

    Args:
        expression: The expression to substitute into.
        variable: The name of the symbol to replace.
        value: The numeric value to put in its place.

    Returns:
        A copy of `expression` with every `Symbol` named `variable` replaced by the
        number.

    Raises:
        Error: If an internal operation fails.
    """
    return substitute(expression, variable, Expression.number(value))


def substitute(
    expression: Expression, variable: String, value: Int
) raises -> Expression:
    """Substitutes a symbol with an integer value.

    A convenience overload equivalent to substituting `Expression.number(value)`.

    Args:
        expression: The expression to substitute into.
        variable: The name of the symbol to replace.
        value: The integer value to put in its place.

    Returns:
        A copy of `expression` with every `Symbol` named `variable` replaced by the
        number.

    Raises:
        Error: If an internal operation fails.
    """
    return substitute(expression, variable, Expression.number(value))


# ===----------------------------------------------------------------------=== #
# Numeric evaluation
# ===----------------------------------------------------------------------=== #


def evaluate(
    expression: Expression, precision: Int = _DEFAULT_PRECISION
) raises -> BigDecimal:
    """Evaluates an expression to a `BigDecimal` at a requested precision.

    Every free symbol must have been substituted away with `substitute` first;
    a surviving symbol raises, since it has no numeric value. Elementary
    functions are dispatched to their Decimo implementations at `precision`
    significant digits.

    Args:
        expression: The expression to evaluate. It must contain no free symbols.
        precision: The number of significant digits to compute with. Defaults
            to Decimo's own default context precision.

    Returns:
        The numeric value.

    Raises:
        Error: If the expression contains a free symbol, an unknown function,
            or an internal numeric operation fails.
    """
    var k = expression.kind()
    if k == ExpressionKind.NUMBER:
        return expression.value()
    if k == ExpressionKind.SYMBOL:
        raise Error(
            String("evaluate: cannot evaluate free symbol '")
            + expression.name()
            + "'; substitute it with a value first"
        )
    if k == ExpressionKind.ADD:
        var total = BigDecimal()
        for i in range(expression.num_arguments()):
            total = total + evaluate(expression.argument(i), precision)
        return total^
    if k == ExpressionKind.MULTIPLY:
        var product = BigDecimal(1)
        for i in range(expression.num_arguments()):
            product = product * evaluate(expression.argument(i), precision)
        return product^
    if k == ExpressionKind.POWER:
        var base = evaluate(expression.argument(0), precision)
        var exponent = evaluate(expression.argument(1), precision)
        return power(base, exponent, precision)
    if k == ExpressionKind.FUNCTION:
        return _evaluate_function(expression, precision)
    raise Error("evaluate: unsupported expression kind")


def _evaluate_function(
    expression: Expression, precision: Int
) raises -> BigDecimal:
    """Evaluates an elementary `Function` node numerically.

    Dispatches `sin`, `cos`, `exp`, `log` (natural logarithm), and `sqrt` to
    their Decimo implementations, matching the functions differentiation
    understands.

    Args:
        expression: The `Function` expression (single argument).
        precision: The number of significant digits to compute with.

    Returns:
        The numeric value.

    Raises:
        Error: If the function is not unary or has no numeric implementation.
    """
    if expression.num_arguments() != 1:
        raise Error(
            String("evaluate: only unary functions are supported, got '")
            + expression.name()
            + "'"
        )
    var name = expression.name()
    var argument = evaluate(expression.argument(0), precision)
    if name == "sin":
        return sin(argument, precision)
    if name == "cos":
        return cos(argument, precision)
    if name == "exp":
        return exp(argument, precision)
    if name == "log":
        return ln(argument, precision)
    if name == "sqrt":
        return sqrt(argument, precision)
    raise Error(
        String("evaluate: no numeric implementation for function '")
        + name
        + "'"
    )
