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
"""

from decimo import BigDecimal

from symo.core.expression import Expression, ExpressionKind


def simplify(e: Expression) raises -> Expression:
    """Simplifies an expression by constant folding and basic identities.

    Args:
        e: The expression to simplify.

    Returns:
        A simplified, structurally-equivalent expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    var k = e.kind()
    if k == ExpressionKind.SYMBOL or k == ExpressionKind.NUMBER:
        return e.copy()
    if k == ExpressionKind.FUNCTION:
        var new_arguments = List[Expression]()
        for i in range(e.num_arguments()):
            new_arguments.append(simplify(e.argument(i)))
        return Expression.function(e.name(), new_arguments^)
    if k == ExpressionKind.ADD:
        return _simplify_add(e)
    if k == ExpressionKind.MULTIPLY:
        return _simplify_multiply(e)
    if k == ExpressionKind.POWER:
        return _simplify_power(e)
    return e.copy()


# ===----------------------------------------------------------------------=== #
# Sums
# ===----------------------------------------------------------------------=== #


def _simplify_add(e: Expression) raises -> Expression:
    """Simplifies an `Add` node: folds the numeric constant and collects like
    terms.

    Args:
        e: The `Add` expression.

    Returns:
        The simplified expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    # Simplify and flatten the operands into a single list of terms.
    var terms = List[Expression]()
    for i in range(e.num_arguments()):
        var s = simplify(e.argument(i))
        if s.kind() == ExpressionKind.ADD:
            for j in range(s.num_arguments()):
                terms.append(s.argument(j))
        else:
            terms.append(s^)

    # Accumulate a single numeric constant and coefficients for each distinct
    # non-numeric "rest" factor.
    var constant = BigDecimal()
    var bases = List[Expression]()
    var coefficients = List[BigDecimal]()
    for i in range(len(terms)):
        if terms[i].kind() == ExpressionKind.NUMBER:
            constant = constant + terms[i].value()
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

    if len(out_terms) == 0:
        return Expression.number(0)
    if len(out_terms) == 1:
        return out_terms[0].copy()
    return Expression.add(out_terms^)


# ===----------------------------------------------------------------------=== #
# Products
# ===----------------------------------------------------------------------=== #


def _simplify_multiply(e: Expression) raises -> Expression:
    """Simplifies a `Multiply` node: folds the numeric coefficient, collects
    like bases (summing exponents), and applies the zero/one identities.

    Args:
        e: The `Multiply` expression.

    Returns:
        The simplified expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    # Simplify and flatten the operands into a single list of factors.
    var factors = List[Expression]()
    for i in range(e.num_arguments()):
        var s = simplify(e.argument(i))
        if s.kind() == ExpressionKind.MULTIPLY:
            for j in range(s.num_arguments()):
                factors.append(s.argument(j))
        else:
            factors.append(s^)

    # Accumulate a single numeric coefficient and an exponent for each distinct
    # base.
    var coefficient = BigDecimal(1)
    var bases = List[Expression]()
    var exponents = List[Expression]()
    for i in range(len(factors)):
        if factors[i].kind() == ExpressionKind.NUMBER:
            coefficient = coefficient * factors[i].value()
            continue
        var base = _power_base(factors[i])
        var exponent = _power_exponent(factors[i])
        var found = -1
        for b in range(len(bases)):
            if bases[b] == base:
                found = b
                break
        if found >= 0:
            exponents[found] = simplify(exponents[found] + exponent)
        else:
            bases.append(base^)
            exponents.append(exponent^)

    # A single zero factor annihilates the whole product.
    if coefficient.is_zero():
        return Expression.number(0)

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
        return Expression.number(1)
    if len(out_factors) == 1:
        return out_factors[0].copy()
    return Expression.multiply(out_factors^)


# ===----------------------------------------------------------------------=== #
# Powers
# ===----------------------------------------------------------------------=== #


def _simplify_power(e: Expression) raises -> Expression:
    """Simplifies a `Power` node: applies the zero/one identities and folds a
    numeric base raised to a non-negative integer exponent.

    Args:
        e: The `Power` expression.

    Returns:
        The simplified expression.

    Raises:
        Error: If an internal numeric operation fails.
    """
    var base = simplify(e.argument(0))
    var exponent = simplify(e.argument(1))
    return _make_power(base, exponent)


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
