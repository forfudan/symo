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

"""Tests for the core `Expression` type: construction, operators, printing, and
structural equality.
"""

from std.testing import assert_equal, assert_false, assert_true

from symo.core.expression import Expression, ExpressionKind


def test_symbol_and_number_printing() raises:
    """Leaves render to their name or numeric value."""
    assert_equal(String(Expression.symbol("x")), "x")
    assert_equal(String(Expression.number(5)), "5")
    assert_equal(String(Expression.number(-3)), "-3")
    assert_equal(String(Expression.number("1.5")), "1.5")


def test_polynomial_printing() raises:
    """A small polynomial renders with reconstructed subtraction."""
    var x = Expression.symbol("x")
    assert_equal(String(x**2 + 3 * x - 1), "x**2 + 3*x - 1")


def test_negation_and_subtraction() raises:
    """Negation and subtraction print with a minus sign."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    assert_equal(String(-x), "-x")
    assert_equal(String(2 - x), "2 - x")
    assert_equal(String(x - y - 1), "x - y - 1")


def test_division_printing() raises:
    """Division is reconstructed from negative powers, with parentheses."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    assert_equal(String(1 / x), "1/x")
    assert_equal(String(x / (x + 1)), "x/(x + 1)")
    assert_equal(String(x * y / (x + y)), "x*y/(x + y)")


def test_power_parenthesization() raises:
    """Powers parenthesize compound bases and exponents."""
    var x = Expression.symbol("x")
    assert_equal(String((x + 1) ** 2), "(x + 1)**2")
    assert_equal(String(x ** (x + 1)), "x**(x + 1)")


def test_add_and_mul_flatten() raises:
    """`Add` and `Multiply` are associative in structure (flattened)."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    var z = Expression.symbol("z")
    assert_true((x + y) + z == x + (y + z))
    assert_true((x * y) * z == x * (y * z))


def test_structural_equality() raises:
    """Equality is structural and order-sensitive."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    assert_true(x == Expression.symbol("x"))
    assert_false(x == y)
    # Order-sensitive: canonical ordering is the job of `simplify`, not `core`.
    assert_false(x + y == y + x)
    assert_true(Expression.number(2) == Expression.number(2))
    assert_false(Expression.number(2) == Expression.number(3))


def test_builders_collapse_trivial() raises:
    """A one-term sum collapses to the term itself."""
    var x = Expression.symbol("x")
    var terms = List[Expression]()
    terms.append(x.copy())
    assert_true(Expression.add(terms^) == x)


def main() raises:
    test_symbol_and_number_printing()
    test_polynomial_printing()
    test_negation_and_subtraction()
    test_division_printing()
    test_power_parenthesization()
    test_add_and_mul_flatten()
    test_structural_equality()
    test_builders_collapse_trivial()
    print("core: all tests passed")
