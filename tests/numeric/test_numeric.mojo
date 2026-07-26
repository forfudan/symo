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

"""Tests for substitution (`substitute`) and numeric evaluation (`evaluate`)."""

from std.testing import assert_equal, assert_raises

from symo.core.expression import Expression
from symo.numeric.evaluate import evaluate, substitute


def _unary(name: String, argument: Expression) -> Expression:
    var arguments = List[Expression]()
    arguments.append(argument.copy())
    return Expression.function(name, arguments^)


# ===----------------------------------------------------------------------=== #
# Substitution
# ===----------------------------------------------------------------------=== #


def test_substitute_symbol() raises:
    """A bare symbol is replaced; an unrelated symbol is left alone."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    assert_equal(String(substitute(x, "x", Expression.number(3))), "3")
    assert_equal(String(substitute(y, "x", Expression.number(3))), "y")


def test_substitute_is_structural_not_simplified() raises:
    """`substitute` does not simplify: `x*x` with `x=2` stays `2*2`."""
    var x = Expression.symbol("x")
    assert_equal(String(substitute(x * x, "x", 2)), "2*2")


def test_substitute_nested_and_functions() raises:
    """Substitution reaches into powers, sums, and function arguments."""
    var x = Expression.symbol("x")
    assert_equal(
        String(substitute(x**2 + 3 * x - 1, "x", 5)), "5**2 + 3*5 - 1"
    )
    assert_equal(String(substitute(_unary("sin", x), "x", 0)), "sin(0)")


def test_substitute_with_expression() raises:
    """A symbol can be replaced by another expression, not just a number."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    assert_equal(String(substitute(x**2, "x", y + 1)), "(y + 1)**2")


# ===----------------------------------------------------------------------=== #
# Numeric evaluation
# ===----------------------------------------------------------------------=== #


def test_evaluate_arithmetic() raises:
    """Constant folding through add, multiply, subtract, divide, power."""
    var two = Expression.number(2)
    var three = Expression.number(3)
    assert_equal(String(evaluate(two + three)), "5")
    assert_equal(String(evaluate(two * three)), "6")
    assert_equal(String(evaluate(three - two)), "1")
    assert_equal(String(evaluate(two**3)), "8")
    assert_equal(String(evaluate(three / two)), "1.5")


def test_evaluate_after_substitute() raises:
    """Substitute a value, then evaluate the resulting numeric tree."""
    var x = Expression.symbol("x")
    assert_equal(String(evaluate(substitute(x**2 + 3 * x - 1, "x", 5))), "39")
    assert_equal(String(evaluate(substitute(1 / x, "x", 4))), "0.25")


def test_evaluate_functions() raises:
    """Elementary functions dispatch to their Decimo implementations."""
    assert_equal(String(evaluate(_unary("sqrt", Expression.number(4)))), "2")
    assert_equal(String(evaluate(_unary("exp", Expression.number(0)))), "1")
    assert_equal(String(evaluate(_unary("cos", Expression.number(0)))), "1")
    assert_equal(String(evaluate(_unary("sin", Expression.number(0)))), "0")
    assert_equal(String(evaluate(_unary("log", Expression.number(1)))), "0")


def test_evaluate_precision() raises:
    """The precision argument controls the number of significant digits."""
    var two = Expression.number(2)
    assert_equal(String(evaluate(_unary("sqrt", two), 10)), "1.414213562")


def test_evaluate_free_symbol_raises() raises:
    """Evaluating a tree with a surviving free symbol is an error."""
    var x = Expression.symbol("x")
    with assert_raises():
        _ = evaluate(x + 1)


def test_evaluate_unknown_function_raises() raises:
    """A function with no numeric implementation is an error."""
    with assert_raises():
        _ = evaluate(_unary("erf", Expression.number(1)))


def test_string_overloads() raises:
    """The string overloads parse their input before substituting/evaluating."""
    assert_equal(String(substitute("x**2 + 1", "x", 5)), "5**2 + 1")
    assert_equal(String(evaluate("2 * 3 + 4")), "10")
    assert_equal(String(evaluate(substitute("x**2 + 3 * x - 1", "x", 5))), "39")


def main() raises:
    test_substitute_symbol()
    test_substitute_is_structural_not_simplified()
    test_substitute_nested_and_functions()
    test_substitute_with_expression()
    test_evaluate_arithmetic()
    test_evaluate_after_substitute()
    test_evaluate_functions()
    test_evaluate_precision()
    test_evaluate_free_symbol_raises()
    test_evaluate_unknown_function_raises()
    test_string_overloads()
    print("numeric: all tests passed")
