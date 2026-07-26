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

"""Tests for the simplification pass: constant folding, identities, and
like-term / like-base collection.
"""

from std.testing import assert_equal, assert_true

from symo.core.expression import Expression
from symo.simplify.simplify import simplify


def test_constant_folding() raises:
    """Numeric sub-expressions fold to a single number."""
    assert_equal(
        String(simplify(Expression.number(2) + Expression.number(3))), "5"
    )
    assert_equal(
        String(simplify(Expression.number(2) * Expression.number(3))), "6"
    )
    assert_equal(String(simplify(Expression.number(2) ** 3)), "8")


def test_additive_identities() raises:
    """`x + 0` collapses to `x`."""
    var x = Expression.symbol("x")
    assert_equal(String(simplify(x + 0)), "x")
    assert_equal(String(simplify((x + 1) - 1)), "x")


def test_multiplicative_identities() raises:
    """`x * 1`, `x * 0`, and power identities collapse as expected."""
    var x = Expression.symbol("x")
    assert_equal(String(simplify(x * 1)), "x")
    assert_equal(String(simplify(x * 0)), "0")
    assert_equal(String(simplify(x**0)), "1")
    assert_equal(String(simplify(x**1)), "x")


def test_like_term_collection() raises:
    """Repeated terms combine into a numeric coefficient."""
    var x = Expression.symbol("x")
    assert_equal(String(simplify(x + x)), "2*x")
    assert_equal(String(simplify(2 * x + 3 * x)), "5*x")


def test_like_base_collection() raises:
    """Repeated factors combine by summing exponents."""
    var x = Expression.symbol("x")
    assert_equal(String(simplify(x * x)), "x**2")
    assert_equal(String(simplify(x**2 * x**3)), "x**5")


def test_mixed_expression() raises:
    """A mix of like and unlike terms folds partially."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    assert_equal(String(simplify(x + y + x)), "2*x + y")


def test_result_equals_expected_tree() raises:
    """The simplified result is structurally equal to the expected tree."""
    var x = Expression.symbol("x")
    assert_true(simplify(x + x) == Expression.number(2) * x)


def test_string_overload() raises:
    """The string overloads parse their input, then simplify it."""
    assert_equal(String(simplify("2 * x + 3 * x + 1")), "5*x + 1")
    var derivation = simplify("x + x", detail=1)
    assert_equal(String(derivation.result), "2*x")


def main() raises:
    test_constant_folding()
    test_additive_identities()
    test_multiplicative_identities()
    test_like_term_collection()
    test_like_base_collection()
    test_mixed_expression()
    test_result_equals_expected_tree()
    test_string_overload()
    print("simplify: all tests passed")
