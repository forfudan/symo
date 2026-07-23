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

"""Tests for step-by-step traces (`symo.steps`) and the traced engines."""

from std.testing import assert_equal, assert_true

from symo.calculus.differentiation import differentiate
from symo.core.expression import Expression
from symo.simplify.simplify import simplify
from symo.steps.steps import StepTag, Trace


def _unary(name: String, argument: Expression) -> Expression:
    var arguments = List[Expression]()
    arguments.append(argument.copy())
    return Expression.function(name, arguments^)


# ===----------------------------------------------------------------------=== #
# Trace filtering
# ===----------------------------------------------------------------------=== #


def test_detail_zero_records_nothing() raises:
    """A detail-0 trace drops every step."""
    var x = Expression.symbol("x")
    var trace = Trace(0)
    trace.record(StepTag.CORE, "product-rule", x, x)
    trace.record(StepTag.TRIVIAL, "sum-identities", x, x)
    assert_equal(trace.num_steps(), 0)


def test_detail_filtering_is_cumulative() raises:
    """Detail `n` keeps exactly the tags with `min_detail <= n`."""
    var x = Expression.symbol("x")

    var trace1 = Trace(1)
    trace1.record(StepTag.CORE, "a", x, x)
    trace1.record(StepTag.PEDAGOGICAL, "b", x, x)
    trace1.record(StepTag.TRIVIAL, "c", x, x)
    assert_equal(trace1.num_steps(), 1)
    assert_equal(trace1.step(0).rule(), "a")

    var trace2 = Trace(2)
    trace2.record(StepTag.CORE, "a", x, x)
    trace2.record(StepTag.PEDAGOGICAL, "b", x, x)
    trace2.record(StepTag.TRIVIAL, "c", x, x)
    assert_equal(trace2.num_steps(), 2)

    var trace3 = Trace(3)
    trace3.record(StepTag.CORE, "a", x, x)
    trace3.record(StepTag.PEDAGOGICAL, "b", x, x)
    trace3.record(StepTag.TRIVIAL, "c", x, x)
    assert_equal(trace3.num_steps(), 3)
    assert_true(trace3.step(2).tag() == StepTag.TRIVIAL)


# ===----------------------------------------------------------------------=== #
# Traced differentiation
# ===----------------------------------------------------------------------=== #


def test_traced_result_matches_untraced() raises:
    """The `detail` overload returns the same result as the plain one."""
    var x = Expression.symbol("x")
    var expression = x**3 + 3 * x - 1
    var d = differentiate(expression, "x", detail=3)
    assert_equal(String(d.result), String(differentiate(expression, "x")))
    assert_true(d.trace.num_steps() > 0)


def test_power_rule_step() raises:
    """At detail 1 only the core power-rule step is recorded."""
    var x = Expression.symbol("x")
    var d = differentiate(x**2, "x", detail=1)
    assert_equal(String(d.result), "2*x")
    assert_equal(d.trace.num_steps(), 1)
    assert_equal(d.trace.step(0).rule(), "power-rule")
    assert_equal(String(d.trace.step(0).before()), "d/dx(x**2)")
    assert_equal(String(d.trace.step(0).after()), "2*x**1*d/dx(x)")


def test_product_rule_step() raises:
    """The product rule records a textbook-style pending derivative."""
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")
    var d = differentiate(x * y, "x", detail=1)
    assert_equal(String(d.result), "y")
    assert_equal(d.trace.num_steps(), 1)
    assert_equal(d.trace.step(0).rule(), "product-rule")
    assert_equal(String(d.trace.step(0).before()), "d/dx(x*y)")
    assert_equal(String(d.trace.step(0).after()), "d/dx(x)*y + x*d/dx(y)")


def test_chain_rule_before_inner_step() raises:
    """Steps are recorded top-down: chain rule first, inner rule after."""
    var x = Expression.symbol("x")
    var d = differentiate(_unary("sin", x**2), "x", detail=1)
    assert_equal(d.trace.num_steps(), 2)
    assert_equal(d.trace.step(0).rule(), "chain-rule")
    assert_equal(d.trace.step(1).rule(), "power-rule")
    assert_equal(String(d.trace.step(1).before()), "d/dx(x**2)")


def test_sum_rule_step_at_detail_two() raises:
    """The pedagogical sum rule appears from detail 2."""
    var x = Expression.symbol("x")
    var d1 = differentiate(x + 7, "x", detail=1)
    assert_equal(d1.trace.num_steps(), 0)
    var d2 = differentiate(x + 7, "x", detail=2)
    assert_equal(d2.trace.num_steps(), 2)
    assert_equal(d2.trace.step(0).rule(), "sum-rule")
    assert_equal(String(d2.trace.step(0).after()), "d/dx(x) + d/dx(7)")
    assert_equal(d2.trace.step(1).rule(), "collect-like-terms")


# ===----------------------------------------------------------------------=== #
# Traced simplification
# ===----------------------------------------------------------------------=== #


def test_simplify_collect_like_terms() raises:
    """Like-term collection is recorded as a pedagogical step."""
    var x = Expression.symbol("x")
    var d = simplify(x + x, detail=2)
    assert_equal(String(d.result), "2*x")
    assert_equal(d.trace.num_steps(), 1)
    assert_equal(d.trace.step(0).rule(), "collect-like-terms")
    assert_equal(String(d.trace.step(0).before()), "x + x")


def test_simplify_identities_are_trivial() raises:
    """`x + 0 -> x` is recorded only at detail 3."""
    var x = Expression.symbol("x")
    var d1 = simplify(x + 0, detail=1)
    assert_equal(String(d1.result), "x")
    assert_equal(d1.trace.num_steps(), 0)
    var d3 = simplify(x + 0, detail=3)
    assert_equal(String(d3.result), "x")
    assert_equal(d3.trace.num_steps(), 1)
    assert_equal(d3.trace.step(0).rule(), "sum-identities")
    assert_true(d3.trace.step(0).tag() == StepTag.TRIVIAL)


def test_simplify_evaluate_power() raises:
    """Folding a numeric power is recorded as a pedagogical step."""
    var two = Expression.number(2)
    var d = simplify(two**3, detail=2)
    assert_equal(String(d.result), "8")
    assert_equal(d.trace.num_steps(), 1)
    assert_equal(d.trace.step(0).rule(), "evaluate-power")


def test_simplify_no_rewrite_records_nothing() raises:
    """An already-simplified expression produces an empty trace."""
    var x = Expression.symbol("x")
    var d = simplify(x, detail=3)
    assert_equal(String(d.result), "x")
    assert_equal(d.trace.num_steps(), 0)


# ===----------------------------------------------------------------------=== #
# Rendering
# ===----------------------------------------------------------------------=== #


def test_render_trace_and_derivation() raises:
    """`String(trace)` gives numbered lines; `String(d)` opens with the
    problem statement and closes with the result."""
    var x = Expression.symbol("x")
    var d = differentiate(x**2, "x", detail=1)
    assert_equal(String(d.input), "d/dx(x**2)")
    assert_equal(
        String(d.trace),
        "1. [core] power-rule: d/dx(x**2) -> 2*x**1*d/dx(x)\n",
    )
    assert_equal(
        String(d),
        (
            "d/dx(x**2)\n1. [core] power-rule: d/dx(x**2) -> 2*x**1*d/dx(x)\n=>"
            " 2*x"
        ),
    )


def test_render_empty_trace() raises:
    """An empty trace renders as a placeholder line."""
    var trace = Trace(0)
    assert_equal(String(trace), "(no steps recorded)")


def main() raises:
    test_detail_zero_records_nothing()
    test_detail_filtering_is_cumulative()
    test_traced_result_matches_untraced()
    test_power_rule_step()
    test_product_rule_step()
    test_chain_rule_before_inner_step()
    test_sum_rule_step_at_detail_two()
    test_simplify_collect_like_terms()
    test_simplify_identities_are_trivial()
    test_simplify_evaluate_power()
    test_simplify_no_rewrite_records_nothing()
    test_render_trace_and_derivation()
    test_render_empty_trace()
    print("steps: all tests passed")
