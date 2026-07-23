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

The engine records its steps into a `Trace` (see `symo.steps`). The
`differentiate(e, variable, detail=n)` overload returns a `Derivation` holding
the answer together with the recorded steps. Steps are recorded *before*
recursing into subexpressions, so the trace reads top-down like a textbook
derivation; a not-yet-computed derivative appears in a step as an inert
function node `d/dvar(...)` that a later step resolves.
"""

from decimo import BigDecimal

from symo.core.expression import Expression, ExpressionKind
from symo.simplify.simplify import simplify
from symo.steps.steps import Derivation, StepTag, Trace


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
    var trace = Trace(0)
    return differentiate(e, variable, trace)


def differentiate(
    e: Expression, variable: String, mut trace: Trace
) raises -> Expression:
    """Differentiates an expression, recording steps into a caller's trace.

    This is the engine entry point for callers that thread their own `Trace`
    through several computations. Most users want the `detail` overload
    instead.

    Args:
        e: The expression to differentiate.
        variable: The name of the symbol to differentiate with respect to.
        trace: The trace that receives the recorded steps.

    Returns:
        The simplified derivative.

    Raises:
        Error: If the expression contains a function with no known derivative
            rule, or an internal numeric operation fails.
    """
    var raw = _differentiate(e, variable, trace)
    return simplify(raw, trace)


def differentiate(
    e: Expression, variable: String, detail: Int
) raises -> Derivation:
    """Differentiates an expression and returns the answer with its steps.

    Args:
        e: The expression to differentiate.
        variable: The name of the symbol to differentiate with respect to.
        detail: How much to record: `0` nothing, `1` core steps, `2` also
            pedagogical steps, `3` everything including trivial rewrites.

    Returns:
        A `Derivation` holding the problem statement (as `d/dvar(e)`), the
        simplified derivative, and the trace.

    Raises:
        Error: If the expression contains a function with no known derivative
            rule, or an internal numeric operation fails.
    """
    var trace = Trace(detail)
    var result = differentiate(e, variable, trace)
    return Derivation(_pending(variable, e), result^, trace^)


def _differentiate(
    e: Expression, variable: String, mut trace: Trace
) raises -> Expression:
    """Computes the raw (unsimplified) derivative of an expression.

    Args:
        e: The expression to differentiate.
        variable: The name of the differentiation variable.
        trace: The trace that receives the recorded steps.

    Returns:
        The unsimplified derivative.

    Raises:
        Error: If a function has no known derivative rule.
    """
    var k = e.kind()
    if k == ExpressionKind.NUMBER:
        if trace.wants(StepTag.TRIVIAL):
            trace.record(
                StepTag.TRIVIAL,
                "constant-rule",
                _pending(variable, e),
                Expression.number(0),
            )
        return Expression.number(0)
    if k == ExpressionKind.SYMBOL:
        if e.name() == variable:
            if trace.wants(StepTag.TRIVIAL):
                trace.record(
                    StepTag.TRIVIAL,
                    "variable-rule",
                    _pending(variable, e),
                    Expression.number(1),
                )
            return Expression.number(1)
        if trace.wants(StepTag.TRIVIAL):
            trace.record(
                StepTag.TRIVIAL,
                "constant-rule",
                _pending(variable, e),
                Expression.number(0),
            )
        return Expression.number(0)
    if k == ExpressionKind.ADD:
        return _differentiate_sum(e, variable, trace)
    if k == ExpressionKind.MULTIPLY:
        return _differentiate_product(e, variable, trace)
    if k == ExpressionKind.POWER:
        return _differentiate_power(e, variable, trace)
    if k == ExpressionKind.FUNCTION:
        return _differentiate_function(e, variable, trace)
    return Expression.number(0)


# ===----------------------------------------------------------------------=== #
# Sum and product rules
# ===----------------------------------------------------------------------=== #


def _differentiate_sum(
    e: Expression, variable: String, mut trace: Trace
) raises -> Expression:
    """Applies the sum rule: differentiate each term.

    Args:
        e: The `Add` expression.
        variable: The name of the differentiation variable.
        trace: The trace that receives the recorded steps.

    Returns:
        The derivative.

    Raises:
        Error: If a function has no known derivative rule.
    """
    if trace.wants(StepTag.PEDAGOGICAL):
        var pending_terms = List[Expression]()
        for i in range(e.num_arguments()):
            pending_terms.append(_pending(variable, e.argument(i)))
        trace.record(
            StepTag.PEDAGOGICAL,
            "sum-rule",
            _pending(variable, e),
            Expression.add(pending_terms^),
        )
    var terms = List[Expression]()
    for i in range(e.num_arguments()):
        terms.append(_differentiate(e.argument(i), variable, trace))
    return Expression.add(terms^)


def _differentiate_product(
    e: Expression, variable: String, mut trace: Trace
) raises -> Expression:
    """Applies the product rule to an n-ary product.

    For factors `f0 * f1 * ... * f_{n-1}`, the derivative is the sum over `i` of
    the product with `f_i` replaced by its derivative.

    Args:
        e: The `Multiply` expression.
        variable: The name of the differentiation variable.
        trace: The trace that receives the recorded steps.

    Returns:
        The derivative.

    Raises:
        Error: If a function has no known derivative rule.
    """
    var n = e.num_arguments()
    if trace.wants(StepTag.CORE):
        var pending_terms = List[Expression]()
        for i in range(n):
            var pending_factors = List[Expression]()
            for j in range(n):
                if j == i:
                    pending_factors.append(_pending(variable, e.argument(j)))
                else:
                    pending_factors.append(e.argument(j))
            pending_terms.append(Expression.multiply(pending_factors^))
        trace.record(
            StepTag.CORE,
            "product-rule",
            _pending(variable, e),
            Expression.add(pending_terms^),
        )
    var terms = List[Expression]()
    for i in range(n):
        var factors = List[Expression]()
        for j in range(n):
            if j == i:
                factors.append(_differentiate(e.argument(j), variable, trace))
            else:
                factors.append(e.argument(j))
        terms.append(Expression.multiply(factors^))
    return Expression.add(terms^)


# ===----------------------------------------------------------------------=== #
# Power and chain rules
# ===----------------------------------------------------------------------=== #


def _differentiate_power(
    e: Expression, variable: String, mut trace: Trace
) raises -> Expression:
    """Differentiates a `Power` node.

    For a constant exponent `c`, uses the power rule
    `d(u**c) = c * u**(c-1) * u'`. Otherwise uses the general rule
    `d(u**v) = u**v * (v' * log(u) + v * u' / u)`.

    Args:
        e: The `Power` expression.
        variable: The name of the differentiation variable.
        trace: The trace that receives the recorded steps.

    Returns:
        The derivative.

    Raises:
        Error: If a function has no known derivative rule.
    """
    var base = e.argument(0)
    var exponent = e.argument(1)

    if exponent.kind() == ExpressionKind.NUMBER:
        var c = exponent.value()
        var reduced = Expression.number(c - BigDecimal(1))
        if trace.wants(StepTag.CORE):
            var pending_factors = List[Expression]()
            pending_factors.append(Expression.number(c.copy()))
            pending_factors.append(Expression.power(base, reduced))
            pending_factors.append(_pending(variable, base))
            trace.record(
                StepTag.CORE,
                "power-rule",
                _pending(variable, e),
                Expression.multiply(pending_factors^),
            )
        var base_derivative = _differentiate(base, variable, trace)
        var factors = List[Expression]()
        factors.append(Expression.number(c.copy()))
        factors.append(Expression.power(base, reduced))
        factors.append(base_derivative^)
        return Expression.multiply(factors^)

    var log_base = _unary_function("log", base)
    if trace.wants(StepTag.CORE):
        var pending_bracket = (_pending(variable, exponent) * log_base) + (
            exponent * _pending(variable, base) / base
        )
        trace.record(
            StepTag.CORE,
            "general-power-rule",
            _pending(variable, e),
            Expression.power(base, exponent) * pending_bracket,
        )
    var base_derivative = _differentiate(base, variable, trace)
    var exponent_derivative = _differentiate(exponent, variable, trace)
    var bracket = (exponent_derivative * log_base) + (
        exponent * base_derivative / base
    )
    return Expression.power(base, exponent) * bracket


def _differentiate_function(
    e: Expression, variable: String, mut trace: Trace
) raises -> Expression:
    """Applies the chain rule to an elementary `Function` node.

    Args:
        e: The `Function` expression (single argument).
        variable: The name of the differentiation variable.
        trace: The trace that receives the recorded steps.

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
    if trace.wants(StepTag.CORE):
        trace.record(
            StepTag.CORE,
            "chain-rule",
            _pending(variable, e),
            outer * _pending(variable, u),
        )
    var inner_derivative = _differentiate(u, variable, trace)
    return outer * inner_derivative


# ===----------------------------------------------------------------------=== #
# Helpers
# ===----------------------------------------------------------------------=== #


def _pending(variable: String, e: Expression) -> Expression:
    """Builds the inert `d/dvar(e)` marker used only inside traces.

    The marker is an ordinary `Function` node named `d/dvar`, so it prints as
    `d/dx(e)` with no printer support needed. It stands for a derivative that
    a later step computes; it never appears in a returned result.

    Args:
        variable: The name of the differentiation variable.
        e: The expression whose derivative is pending.

    Returns:
        The marker expression.
    """
    var arguments = List[Expression]()
    arguments.append(e.copy())
    return Expression.function(String("d/d") + variable, arguments^)


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
