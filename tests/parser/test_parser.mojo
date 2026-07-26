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

"""Tests for the string-DSL parser (`symo.parser`)."""

from std.testing import assert_equal, assert_raises

from symo.calculus.differentiation import differentiate
from symo.parser.parser import parse
from symo.simplify.simplify import simplify


# ===----------------------------------------------------------------------=== #
# Round-tripping through the printer
# ===----------------------------------------------------------------------=== #


def test_atoms() raises:
    """Single symbols and numbers parse and print back unchanged."""
    assert_equal(String(parse("x")), "x")
    assert_equal(String(parse("42")), "42")
    assert_equal(String(parse("3.14")), "3.14")


def test_basic_operators() raises:
    """The four operators and power round-trip to canonical text."""
    assert_equal(String(parse("x + y")), "x + y")
    assert_equal(String(parse("x - y")), "x - y")
    assert_equal(String(parse("x * y")), "x*y")
    assert_equal(String(parse("x / y")), "x/y")
    assert_equal(String(parse("x ** 2")), "x**2")


def test_polynomial_round_trip() raises:
    """A whole polynomial round-trips through parse and print."""
    assert_equal(String(parse("x**2 + 3*x - 1")), "x**2 + 3*x - 1")


def test_caret_is_power() raises:
    """`^` is accepted as a synonym for `**` and prints as `**`."""
    assert_equal(String(parse("x^2")), "x**2")
    assert_equal(String(parse("x^2")), String(parse("x**2")))


# ===----------------------------------------------------------------------=== #
# Precedence and associativity
# ===----------------------------------------------------------------------=== #


def test_precedence() raises:
    """Multiplication binds tighter than addition; power tighter still."""
    assert_equal(String(parse("x + y * z")), "x + y*z")
    assert_equal(String(parse("x * y + z")), "x*y + z")
    assert_equal(String(parse("2 * x ** 3")), "2*x**3")


def test_parentheses_override_precedence() raises:
    """Parentheses regroup as written."""
    assert_equal(String(parse("(x + y) * z")), "(x + y)*z")


def test_left_associativity() raises:
    """`-` and `/` associate to the left."""
    # a - b - c == (a - b) - c
    assert_equal(String(parse("a - b - c")), "a - b - c")
    # a / b / c == (a / b) / c == a / (b*c)
    assert_equal(String(parse("a / b / c")), "a/(b*c)")


def test_power_is_right_associative() raises:
    """`2 ** 3 ** 2` is `2 ** (3 ** 2)` = 512, not `(2 ** 3) ** 2` = 64."""
    assert_equal(String(simplify(parse("2 ** 3 ** 2"))), "512")


def test_unary_minus_precedence() raises:
    """`-x**2` is `-(x**2)`, while `-x*y` is `(-x)*y`."""
    assert_equal(String(parse("-x**2")), "-x**2")
    assert_equal(String(parse("-x*y")), "-x*y")
    assert_equal(String(parse("-x")), "-x")


# ===----------------------------------------------------------------------=== #
# Symbols and functions
# ===----------------------------------------------------------------------=== #


def test_symbols_are_discovered() raises:
    """Any bare identifier becomes a free symbol, no declaration needed."""
    assert_equal(String(parse("alpha + beta_1")), "alpha + beta_1")


def test_function_calls() raises:
    """An identifier followed by `(` is a function application."""
    assert_equal(String(parse("sin(x)")), "sin(x)")
    assert_equal(String(parse("sin(x) + cos(x)")), "sin(x) + cos(x)")


def test_open_function_names_and_arity() raises:
    """Function names are open, and calls may take several arguments."""
    assert_equal(String(parse("f(x, y, 2)")), "f(x, y, 2)")
    assert_equal(String(parse("g(sin(x))")), "g(sin(x))")


# ===----------------------------------------------------------------------=== #
# Integration with the engines
# ===----------------------------------------------------------------------=== #


def test_parse_then_simplify() raises:
    """A parsed expression feeds straight into `simplify`."""
    assert_equal(String(simplify(parse("2 + 3 * 4"))), "14")
    assert_equal(String(simplify(parse("x + x"))), "2*x")


def test_parse_then_differentiate() raises:
    """A parsed expression feeds straight into `differentiate`."""
    assert_equal(String(differentiate(parse("x**3"), "x")), "3*x**2")
    assert_equal(
        String(differentiate(parse("sin(x)"), "x")),
        "cos(x)",
    )


def test_exact_decimal_literals() raises:
    """Decimal literals stay exact through Decimo, no binary-float error."""
    assert_equal(String(simplify(parse("0.1 + 0.1 + 0.1"))), "0.3")


# ===----------------------------------------------------------------------=== #
# Error handling
# ===----------------------------------------------------------------------=== #


def test_empty_input_raises() raises:
    """Empty or whitespace-only input is an error."""
    with assert_raises():
        _ = parse("")
    with assert_raises():
        _ = parse("   ")


def test_unexpected_character_raises() raises:
    """A character the tokenizer does not recognize is an error."""
    with assert_raises():
        _ = parse("x @ y")


def test_unbalanced_parentheses_raise() raises:
    """Missing a closing parenthesis is an error."""
    with assert_raises():
        _ = parse("(x + y")
    with assert_raises():
        _ = parse("sin(x")


def test_trailing_tokens_raise() raises:
    """Extra input after a complete expression is an error."""
    with assert_raises():
        _ = parse("x y")
    with assert_raises():
        _ = parse("2 x")


def test_dangling_operator_raises() raises:
    """An operator with no right operand is an error."""
    with assert_raises():
        _ = parse("x +")
    with assert_raises():
        _ = parse("* x")


def main() raises:
    test_atoms()
    test_basic_operators()
    test_polynomial_round_trip()
    test_caret_is_power()
    test_precedence()
    test_parentheses_override_precedence()
    test_left_associativity()
    test_power_is_right_associative()
    test_unary_minus_precedence()
    test_symbols_are_discovered()
    test_function_calls()
    test_open_function_names_and_arity()
    test_parse_then_simplify()
    test_parse_then_differentiate()
    test_exact_decimal_literals()
    test_empty_input_raises()
    test_unexpected_character_raises()
    test_unbalanced_parentheses_raise()
    test_trailing_tokens_raise()
    test_dangling_operator_raises()
    print("parser: all tests passed")
