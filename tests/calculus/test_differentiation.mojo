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

"""Tests for rule-based symbolic differentiation."""

from std.testing import assert_equal

from symo.calculus.differentiation import differentiate
from symo.core.expression import Expression


def _unary(name: String, argument: Expression) -> Expression:
    var arguments = List[Expression]()
    arguments.append(argument.copy())
    return Expression.function(name, arguments^)


def test_constant_and_symbol() raises:
    """Constants differentiate to 0; the variable to 1, others to 0."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    assert_equal(String(differentiate(Expression.number(7), "x")), "0")
    assert_equal(String(differentiate(x, "x")), "1")
    assert_equal(String(differentiate(y, "x")), "0")


def test_power_rule() raises:
    """The power rule with a constant exponent."""
    var x = Expression.symbol("x")
    assert_equal(String(differentiate(x**2, "x")), "2*x")
    assert_equal(String(differentiate(x**3, "x")), "3*x**2")


def test_sum_rule() raises:
    """Differentiation distributes over sums."""
    var x = Expression.symbol("x")
    assert_equal(String(differentiate(x**3 + 3 * x - 1, "x")), "3*x**2 + 3")


def test_product_rule() raises:
    """The product rule, with unrelated factors treated as constants."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    assert_equal(String(differentiate(x * y, "x")), "y")
    assert_equal(String(differentiate(x**2 * y, "x")), "2*x*y")


def test_chain_rule_functions() raises:
    """The chain rule for elementary functions."""
    var x = Expression.symbol("x")
    assert_equal(String(differentiate(_unary("sin", x), "x")), "cos(x)")
    assert_equal(String(differentiate(_unary("log", x), "x")), "1/x")


def test_reciprocal() raises:
    """The derivative of `1/x` is `-1/x**2`."""
    var x = Expression.symbol("x")
    assert_equal(String(differentiate(1 / x, "x")), "-1/x**2")


def test_string_overload() raises:
    """The string overloads parse their input, then differentiate it."""
    assert_equal(String(differentiate("a**2 + 3 * a - 1", "a")), "2*a + 3")
    var derivation = differentiate("a**2 + 3 * a - 1", "a", detail=3)
    assert_equal(String(derivation.result), "2*a + 3")


def main() raises:
    test_constant_and_symbol()
    test_power_rule()
    test_sum_rule()
    test_product_rule()
    test_chain_rule_functions()
    test_reciprocal()
    test_string_overload()
    print("differentiation: all tests passed")
