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

"""Implements a first simplification pass over the expression tree.

`simplify` walks an expression bottom-up and applies:

- constant folding, using Decimo `BigDecimal` arithmetic for exactness
  (`2 + 3 -> 5`, `2 * 3 -> 6`, `2 ** 3 -> 8`);
- the basic identities `x + 0 -> x`, `x * 1 -> x`, `x * 0 -> 0`,
  `x ** 0 -> 1`, `x ** 1 -> x`, and `1 ** x -> 1`;
- like-term collection in sums (`x + x -> 2*x`) and like-base collection in
  products (`x * x -> x**2`), combining exact numeric coefficients/exponents.

Collection uses structural equality, which is order-sensitive, so `x*y` and
`y*x` are not yet recognised as equal. A canonical ordering pass will address
that in a later milestone.

The engine records its rewrites into a `Trace` (see `symo.steps`). The
`simplify(expression, detail=n)` overload returns a `Derivation` holding the answer
together with the recorded steps. Since a rewrite is only known once it has
been computed, simplification steps are recorded bottom-up (children before
parents), each with the subexpression before and after the rewrite.
"""

from decimo import BigDecimal

from symo.core.expression import Expression, ExpressionKind
from symo.steps.steps import Derivation, StepTag, Trace


def simplify(expression: Expression) raises -> Expression:
    """Simplifies an expression by constant folding and basic identities.

    Args:
        expression: The expression to simplify.

    Returns:
        A simplified, structurally-equivalent expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    var trace = Trace(0)
    return simplify(expression, trace)


def simplify(expression: Expression, mut trace: Trace) raises -> Expression:
    """Simplifies an expression, recording steps into a caller's trace.

    This is the engine entry point for callers that thread their own `Trace`
    through several computations. Most users want the `detail` overload
    instead.

    Args:
        expression: The expression to simplify.
        trace: The trace that receives the recorded steps.

    Returns:
        A simplified, structurally-equivalent expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    var k = expression.kind()
    if k == ExpressionKind.SYMBOL or k == ExpressionKind.NUMBER:
        return expression.copy()
    if k == ExpressionKind.FUNCTION:
        var new_arguments = List[Expression]()
        for i in range(expression.num_arguments()):
            new_arguments.append(simplify(expression.argument(i), trace))
        return Expression.function(expression.name(), new_arguments^)
    if k == ExpressionKind.ADD:
        return _simplify_add(expression, trace)
    if k == ExpressionKind.MULTIPLY:
        return _simplify_multiply(expression, trace)
    if k == ExpressionKind.POWER:
        return _simplify_power(expression, trace)
    return expression.copy()


def simplify(expression: Expression, detail: Int) raises -> Derivation:
    """Simplifies an expression and returns the answer with its steps.

    Args:
        expression: The expression to simplify.
        detail: How much to record: `0` nothing, `1` core steps, `2` also
            pedagogical steps, `3` everything including trivial rewrites.

    Returns:
        A `Derivation` holding the input expression, the simplified
        expression, and the trace.

    Raises:
        Error: If an internal numeric operation fails.
    """
    var trace = Trace(detail)
    var result = simplify(expression, trace)
    return Derivation(expression.copy(), result^, trace^)


# ===----------------------------------------------------------------------=== #
# Sums
# ===----------------------------------------------------------------------=== #


def _simplify_add(
    expression: Expression, mut trace: Trace
) raises -> Expression:
    """Simplifies an `Add` node: folds the numeric constant and collects like
    terms.

    Args:
        expression: The `Add` expression.
        trace: The trace that receives the recorded steps.

    Returns:
        The simplified expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    # Simplify and flatten the operands into a single list of terms.
    var terms = List[Expression]()
    for i in range(expression.num_arguments()):
        var s = simplify(expression.argument(i), trace)
        if s.kind() == ExpressionKind.ADD:
            for j in range(s.num_arguments()):
                terms.append(s.argument(j))
        else:
            terms.append(s^)

    # Accumulate a single numeric constant and coefficients for each distinct
    # non-numeric "rest" factor.
    var constant = BigDecimal()
    var numeric_terms = 0
    var merged_like = False
    var bases = List[Expression]()
    var coefficients = List[BigDecimal]()
    for i in range(len(terms)):
        if terms[i].kind() == ExpressionKind.NUMBER:
            constant = constant + terms[i].value()
            numeric_terms += 1
            continue
        var coefficient = _leading_coefficient(terms[i])
        var rest = _drop_leading_coefficient(terms[i])
        var found = -1
        for b in range(len(bases)):
            if bases[b] == rest:
                found = b
                break
        if found >= 0:
            coefficients[found] = coefficients[found] + coefficient
            merged_like = True
        else:
            bases.append(rest^)
            coefficients.append(coefficient^)

    # Rebuild the surviving terms.
    var out_terms = List[Expression]()
    for b in range(len(bases)):
        if coefficients[b].is_zero():
            continue
        if coefficients[b] == BigDecimal(1):
            out_terms.append(bases[b].copy())
        else:
            var factors = List[Expression]()
            factors.append(Expression.number(coefficients[b].copy()))
            factors.append(bases[b].copy())
            out_terms.append(Expression.multiply(factors^))
    if not constant.is_zero():
        out_terms.append(Expression.number(constant^))

    var result: Expression
    if len(out_terms) == 0:
        result = Expression.number(0)
    elif len(out_terms) == 1:
        result = out_terms[0].copy()
    else:
        result = Expression.add(out_terms^)

    # Record the rewrite. Folding constants or merging like terms is
    # pedagogical; merely dropping zeros / collapsing is trivial bookkeeping.
    var tag = StepTag.TRIVIAL
    var rule = String("sum-identities")
    if merged_like or numeric_terms > 1:
        tag = StepTag.PEDAGOGICAL
        rule = String("collect-like-terms")
    if trace.wants(tag):
        var before = Expression.add(terms.copy())
        if result != before:
            trace.record(tag, rule, before, result)
    return result^


# ===----------------------------------------------------------------------=== #
# Products
# ===----------------------------------------------------------------------=== #


def _simplify_multiply(
    expression: Expression, mut trace: Trace
) raises -> Expression:
    """Simplifies a `Multiply` node: folds the numeric coefficient, collects
    like bases (summing exponents), and applies the zero/one identities.

    Args:
        expression: The `Multiply` expression.
        trace: The trace that receives the recorded steps.

    Returns:
        The simplified expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    # Simplify and flatten the operands into a single list of factors.
    var factors = List[Expression]()
    for i in range(expression.num_arguments()):
        var s = simplify(expression.argument(i), trace)
        if s.kind() == ExpressionKind.MULTIPLY:
            for j in range(s.num_arguments()):
                factors.append(s.argument(j))
        else:
            factors.append(s^)

    # Accumulate a single numeric coefficient and an exponent for each distinct
    # base.
    var coefficient = BigDecimal(1)
    var numeric_factors = 0
    var merged_like = False
    var bases = List[Expression]()
    var exponents = List[Expression]()
    for i in range(len(factors)):
        if factors[i].kind() == ExpressionKind.NUMBER:
            coefficient = coefficient * factors[i].value()
            numeric_factors += 1
            continue
        var base = _power_base(factors[i])
        var exponent = _power_exponent(factors[i])
        var found = -1
        for b in range(len(bases)):
            if bases[b] == base:
                found = b
                break
        if found >= 0:
            exponents[found] = simplify(exponents[found] + exponent, trace)
            merged_like = True
        else:
            bases.append(base^)
            exponents.append(exponent^)

    var result: Expression
    if coefficient.is_zero():
        # A single zero factor annihilates the whole product.
        result = Expression.number(0)
    else:
        # Rebuild the surviving factors.
        var out_factors = List[Expression]()
        if not (coefficient == BigDecimal(1)):
            out_factors.append(Expression.number(coefficient^))
        for b in range(len(bases)):
            var factor = _make_power(bases[b], exponents[b])
            # Drop factors that simplified to 1.
            if (
                factor.kind() == ExpressionKind.NUMBER
                and factor.value() == BigDecimal(1)
            ):
                continue
            out_factors.append(factor^)

        if len(out_factors) == 0:
            result = Expression.number(1)
        elif len(out_factors) == 1:
            result = out_factors[0].copy()
        else:
            result = Expression.multiply(out_factors^)

    # Record the rewrite. Folding coefficients or merging like bases is
    # pedagogical; merely dropping ones / collapsing is trivial bookkeeping.
    var tag = StepTag.TRIVIAL
    var rule = String("product-identities")
    if merged_like or numeric_factors > 1:
        tag = StepTag.PEDAGOGICAL
        rule = String("collect-like-factors")
    if trace.wants(tag):
        var before = Expression.multiply(factors.copy())
        if result != before:
            trace.record(tag, rule, before, result)
    return result^


# ===----------------------------------------------------------------------=== #
# Powers
# ===----------------------------------------------------------------------=== #


def _simplify_power(
    expression: Expression, mut trace: Trace
) raises -> Expression:
    """Simplifies a `Power` node: applies the zero/one identities and folds a
    numeric base raised to a non-negative integer exponent.

    Args:
        expression: The `Power` expression.
        trace: The trace that receives the recorded steps.

    Returns:
        The simplified expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    var base = simplify(expression.argument(0), trace)
    var exponent = simplify(expression.argument(1), trace)
    var result = _make_power(base, exponent)

    # Record the rewrite. Evaluating a fully numeric power is pedagogical;
    # the zero/one identities are trivial bookkeeping.
    var tag = StepTag.TRIVIAL
    var rule = String("power-identities")
    if (
        base.kind() == ExpressionKind.NUMBER
        and exponent.kind() == ExpressionKind.NUMBER
    ):
        tag = StepTag.PEDAGOGICAL
        rule = String("evaluate-power")
    if trace.wants(tag):
        var before = Expression.power(base, exponent)
        if result != before:
            trace.record(tag, rule, before, result)
    return result^


def _make_power(base: Expression, exponent: Expression) raises -> Expression:
    """Builds `base ** exponent`, applying identities and numeric folding.

    Args:
        base: The (already simplified) base.
        exponent: The (already simplified) exponent.

    Returns:
        The simplified power.

    Raises:
        Error: If an internal numeric operation fails.
    """
    if exponent.kind() == ExpressionKind.NUMBER:
        if exponent.value().is_zero():
            return Expression.number(1)
        if exponent.value() == BigDecimal(1):
            return base.copy()
    if base.kind() == ExpressionKind.NUMBER:
        if base.value() == BigDecimal(1):
            return Expression.number(1)
        # Fold a numeric base raised to a non-negative integer exponent.
        if (
            exponent.kind() == ExpressionKind.NUMBER
            and exponent.value().is_integer()
        ):
            var n = Int(exponent.value())
            if n >= 0:
                return Expression.number(base.value().power(n))
    return Expression.power(base, exponent)


# ===----------------------------------------------------------------------=== #
# Term / factor decomposition helpers
# ===----------------------------------------------------------------------=== #


def _leading_coefficient(term: Expression) raises -> BigDecimal:
    """Returns the numeric coefficient of a sum term.

    Args:
        term: A non-numeric sum term.

    Returns:
        The leading numeric coefficient, or `1` when the term has none.

    Raises:
        Error: If an internal numeric operation fails.
    """
    if term.kind() == ExpressionKind.MULTIPLY and term.num_arguments() > 0:
        if term.argument(0).kind() == ExpressionKind.NUMBER:
            return term.argument(0).value()
    return BigDecimal(1)


def _drop_leading_coefficient(term: Expression) raises -> Expression:
    """Returns a sum term with its leading numeric coefficient removed.

    Args:
        term: A non-numeric sum term.

    Returns:
        The term's non-numeric part (the "rest").

    Raises:
        Error: If an internal numeric operation fails.
    """
    if term.kind() == ExpressionKind.MULTIPLY and term.num_arguments() > 0:
        if term.argument(0).kind() == ExpressionKind.NUMBER:
            var rest = List[Expression]()
            for i in range(1, term.num_arguments()):
                rest.append(term.argument(i))
            return Expression.multiply(rest^)
    return term.copy()


def _power_base(factor: Expression) raises -> Expression:
    """Returns the base of a product factor (the factor itself if it is not a
    power).

    Args:
        factor: A non-numeric product factor.

    Returns:
        The base expression.

    Raises:
        Error: If an internal operation fails.
    """
    if factor.kind() == ExpressionKind.POWER:
        return factor.argument(0)
    return factor.copy()


def _power_exponent(factor: Expression) raises -> Expression:
    """Returns the exponent of a product factor (`1` if it is not a power).

    Args:
        factor: A non-numeric product factor.

    Returns:
        The exponent expression.

    Raises:
        Error: If an internal operation fails.
    """
    if factor.kind() == ExpressionKind.POWER:
        return factor.argument(1)
    return Expression.number(1)
