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

"""Implements rule-based symbolic differentiation.

`differentiate(e, variable)` walks the expression tree and applies the standard
rules:

- constants differentiate to `0`; the differentiation variable to `1` and any
  other symbol to `0`;
- the sum rule for `Add`;
- the product rule for `Multiply`;
- the power rule for `Power` (with the general `u**v` case handled via `log`);
- the chain rule for elementary `Function` nodes (`sin`, `cos`, `exp`, `log`,
  `sqrt`).

The result is passed through `simplify`, so `d/dx (x**2)` comes back as `2*x`
rather than `2*x**1*1`.
"""

from decimo import BigDecimal

from symo.core.expression import Expression, ExpressionKind
from symo.simplify.simplify import simplify


def differentiate(e: Expression, variable: String) raises -> Expression:
    """Differentiates an expression with respect to a variable.

    Args:
        e: The expression to differentiate.
        variable: The name of the symbol to differentiate with respect to.

    Returns:
        The simplified derivative.

    Raises:
        Error: If the expression contains a function with no known derivative
            rule, or an internal numeric operation fails.
    """
    return simplify(_differentiate(e, variable))


def _differentiate(e: Expression, variable: String) raises -> Expression:
    """Computes the raw (unsimplified) derivative of an expression.

    Args:
        e: The expression to differentiate.
        variable: The name of the differentiation variable.

    Returns:
        The unsimplified derivative.

    Raises:
        Error: If a function has no known derivative rule.
    """
    var k = e.kind()
    if k == ExpressionKind.NUMBER:
        return Expression.number(0)
    if k == ExpressionKind.SYMBOL:
        if e.name() == variable:
            return Expression.number(1)
        return Expression.number(0)
    if k == ExpressionKind.ADD:
        return _differentiate_sum(e, variable)
    if k == ExpressionKind.MULTIPLY:
        return _differentiate_product(e, variable)
    if k == ExpressionKind.POWER:
        return _differentiate_power(e, variable)
    if k == ExpressionKind.FUNCTION:
        return _differentiate_function(e, variable)
    return Expression.number(0)


# ===----------------------------------------------------------------------=== #
# Sum and product rules
# ===----------------------------------------------------------------------=== #


def _differentiate_sum(e: Expression, variable: String) raises -> Expression:
    """Applies the sum rule: differentiate each term.

    Args:
        e: The `Add` expression.
        variable: The name of the differentiation variable.

    Returns:
        The derivative.

    Raises:
        Error: If a function has no known derivative rule.
    """
    var terms = List[Expression]()
    for i in range(e.num_arguments()):
        terms.append(_differentiate(e.argument(i), variable))
    return Expression.add(terms^)


def _differentiate_product(
    e: Expression, variable: String
) raises -> Expression:
    """Applies the product rule to an n-ary product.

    For factors `f0 * f1 * ... * f_{n-1}`, the derivative is the sum over `i` of
    the product with `f_i` replaced by its derivative.

    Args:
        e: The `Multiply` expression.
        variable: The name of the differentiation variable.

    Returns:
        The derivative.

    Raises:
        Error: If a function has no known derivative rule.
    """
    var n = e.num_arguments()
    var terms = List[Expression]()
    for i in range(n):
        var factors = List[Expression]()
        for j in range(n):
            if j == i:
                factors.append(_differentiate(e.argument(j), variable))
            else:
                factors.append(e.argument(j))
        terms.append(Expression.multiply(factors^))
    return Expression.add(terms^)


# ===----------------------------------------------------------------------=== #
# Power and chain rules
# ===----------------------------------------------------------------------=== #


def _differentiate_power(e: Expression, variable: String) raises -> Expression:
    """Differentiates a `Power` node.

    For a constant exponent `c`, uses the power rule
    `d(u**c) = c * u**(c-1) * u'`. Otherwise uses the general rule
    `d(u**v) = u**v * (v' * log(u) + v * u' / u)`.

    Args:
        e: The `Power` expression.
        variable: The name of the differentiation variable.

    Returns:
        The derivative.

    Raises:
        Error: If a function has no known derivative rule.
    """
    var base = e.argument(0)
    var exponent = e.argument(1)
    var base_derivative = _differentiate(base, variable)

    if exponent.kind() == ExpressionKind.NUMBER:
        var c = exponent.value()
        var reduced = Expression.number(c - BigDecimal(1))
        var factors = List[Expression]()
        factors.append(Expression.number(c.copy()))
        factors.append(Expression.power(base, reduced))
        factors.append(base_derivative^)
        return Expression.multiply(factors^)

    var exponent_derivative = _differentiate(exponent, variable)
    var log_base = _unary_function("log", base)
    var bracket = (exponent_derivative * log_base) + (
        exponent * base_derivative / base
    )
    return Expression.power(base, exponent) * bracket


def _differentiate_function(
    e: Expression, variable: String
) raises -> Expression:
    """Applies the chain rule to an elementary `Function` node.

    Args:
        e: The `Function` expression (single argument).
        variable: The name of the differentiation variable.

    Returns:
        The derivative.

    Raises:
        Error: If the function is not unary, or has no known derivative rule.
    """
    if e.num_arguments() != 1:
        raise Error(
            String("differentiate: only unary functions are supported, got '")
            + e.name()
            + "'"
        )
    var name = e.name()
    var u = e.argument(0)
    var inner_derivative = _differentiate(u, variable)

    var outer: Expression
    if name == "sin":
        outer = _unary_function("cos", u)
    elif name == "cos":
        outer = -_unary_function("sin", u)
    elif name == "exp":
        outer = _unary_function("exp", u)
    elif name == "log":
        outer = Expression.number(1) / u
    elif name == "sqrt":
        var two_sqrt = Expression.number(2) * _unary_function("sqrt", u)
        outer = Expression.number(1) / two_sqrt
    else:
        raise Error(
            String("differentiate: no derivative rule for function '")
            + name
            + "'"
        )
    return outer * inner_derivative


# ===----------------------------------------------------------------------=== #
# Helpers
# ===----------------------------------------------------------------------=== #


def _unary_function(name: String, argument: Expression) -> Expression:
    """Builds a single-argument function application.

    Args:
        name: The function name, e.g. `"cos"`.
        argument: The sole argument expression.

    Returns:
        The `Function` expression `name(argument)`.
    """
    var arguments = List[Expression]()
    arguments.append(argument.copy())
    return Expression.function(name, arguments^)
