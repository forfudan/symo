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

"""Implements step-by-step traces for Symo's rule-based engines.

The engines (`simplify`, `differentiate`, later integration) can record every
rewrite they perform so that a human can follow the derivation. This module
provides the data model:

- `StepTag`: how important a step is (`CORE`, `PEDAGOGICAL`, `TRIVIAL`).
- `Step`: one recorded rewrite (tag, rule name, expression before and after).
- `Trace`: the requested `detail` plus the list of recorded steps.
- `Derivation`: the return type of a traced computation — the final answer
  together with its trace.

The `detail` value controls how much is recorded, cumulatively: `0` records
nothing, `1` keeps `CORE` steps, `2` also keeps `PEDAGOGICAL` steps, and `3`
keeps everything including `TRIVIAL` rewrites.

Engines record and the printer renders; the types here carry a minimal
plain-text rendering (via `Writable`) so that `print(trace)` works, in the
same way `Expression` renders itself in `core`.
"""

from symo.core.expression import Expression


struct StepTag(Copyable, ImplicitlyCopyable, Movable, Writable):
    """The importance tag attached to a recorded step.

    Mimics an enum with a `UInt8` code until Mojo supports enums natively.
    The code doubles as the minimum `detail` at which the step is shown:
    `CORE` steps appear from detail 1, `PEDAGOGICAL` steps from detail 2, and
    `TRIVIAL` steps from detail 3.
    """

    var _value: UInt8
    """The tag code (doubles as the minimum detail that shows the step)."""

    comptime CORE: StepTag = StepTag(1)
    """A main move of the derivation, e.g. applying the product rule."""
    comptime PEDAGOGICAL: StepTag = StepTag(2)
    """A smaller but still instructive move, e.g. collecting like terms."""
    comptime TRIVIAL: StepTag = StepTag(3)
    """A bookkeeping rewrite, e.g. `x*1 -> x`."""

    def __init__(out self, value: UInt8):
        """Initializes a tag from its raw code.

        Prefer the named constants (`StepTag.CORE`, ...) over this
        constructor.

        Args:
            value: The tag code.
        """
        self._value = value

    def __eq__(self, other: StepTag) -> Bool:
        """Compares two tags for equality.

        Args:
            other: The tag to compare against.

        Returns:
            `True` if the tags carry the same code.
        """
        return self._value == other._value

    def __ne__(self, other: StepTag) -> Bool:
        """Compares two tags for inequality.

        Args:
            other: The tag to compare against.

        Returns:
            `True` if the tags carry different codes.
        """
        return self._value != other._value

    def min_detail(self) -> Int:
        """Returns the minimum `detail` at which this tag is shown.

        Returns:
            The detail threshold (`1` for `CORE`, `2` for `PEDAGOGICAL`, `3`
            for `TRIVIAL`).
        """
        return Int(self._value)

    def write_to[W: Writer](self, mut writer: W):
        """Writes the tag's name (`core`, `pedagogical`, or `trivial`).

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        if self._value == 1:
            writer.write("core")
        elif self._value == 2:
            writer.write("pedagogical")
        else:
            writer.write("trivial")


struct Step(Copyable, Movable, Writable):
    """A single recorded rewrite: `before -> after` justified by a rule.

    Notes:

    The position of the rewritten subexpression within the whole tree is not
    recorded yet; the `before` expression itself identifies the subexpression
    that was rewritten. A path-based position can be added when a renderer
    needs it.
    """

    var _tag: StepTag
    """The importance tag of this step."""
    var _rule: String
    """The rule that justifies the rewrite, e.g. `"product-rule"`."""
    var _before: Expression
    """The subexpression before the rewrite."""
    var _after: Expression
    """The subexpression after the rewrite."""

    def __init__(
        out self,
        tag: StepTag,
        rule: String,
        before: Expression,
        after: Expression,
    ):
        """Initializes a step from its parts.

        Args:
            tag: The importance tag.
            rule: The rule name that justifies the rewrite.
            before: The subexpression before the rewrite.
            after: The subexpression after the rewrite.
        """
        self._tag = tag.copy()
        self._rule = rule
        self._before = before.copy()
        self._after = after.copy()

    def tag(self) -> StepTag:
        """Returns the importance tag of this step.

        Returns:
            The tag.
        """
        return self._tag.copy()

    def rule(self) -> String:
        """Returns the name of the rule that justifies the rewrite.

        Returns:
            The rule name, e.g. `"product-rule"`.
        """
        return self._rule.copy()

    def before(self) -> Expression:
        """Returns the subexpression before the rewrite.

        Returns:
            A copy of the expression.
        """
        return self._before.copy()

    def after(self) -> Expression:
        """Returns the subexpression after the rewrite.

        Returns:
            A copy of the expression.
        """
        return self._after.copy()

    def __str__(self) -> String:
        """Returns the plain-text rendering of this step.

        Returns:
            A line like `"[core] product-rule: d/dx(x*y) -> d/dx(x)*y +
            x*d/dx(y)"`.
        """
        var out = String()
        self.write_to(out)
        return out^

    def write_to[W: Writer](self, mut writer: W):
        """Writes the plain-text rendering of this step.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write(
            "[",
            self._tag,
            "] ",
            self._rule,
            ": ",
            self._before,
            " -> ",
            self._after,
        )


struct Trace(Copyable, Movable, Writable):
    """The recorded steps of a traced computation.

    A `Trace` is created with the requested `detail` and passed (as a `mut`
    parameter) through the engines, whose only obligation is to call
    `record(...)` at each rewrite. Steps whose tag exceeds the detail are
    dropped at the recording site, so a detail-0 trace stays essentially
    free.
    """

    var _detail: Int
    """The requested detail; steps above this threshold are not recorded."""
    var _steps: List[Step]
    """The recorded steps, in the order the engine performed them."""

    def __init__(out self, detail: Int):
        """Initializes an empty trace at the given detail.

        Args:
            detail: The detail threshold (`0` records nothing, `3` records
                everything).
        """
        self._detail = detail
        self._steps = List[Step]()

    def detail(self) -> Int:
        """Returns the detail threshold of this trace.

        Returns:
            The detail value.
        """
        return self._detail

    def wants(self, tag: StepTag) -> Bool:
        """Returns whether a step with the given tag would be recorded.

        Engines use this to skip building the `before`/`after` expressions of
        a step that would be dropped anyway.

        Args:
            tag: The tag to test.

        Returns:
            `True` if `record` would keep a step with this tag.
        """
        return tag.min_detail() <= self._detail

    def record(
        mut self,
        tag: StepTag,
        rule: String,
        before: Expression,
        after: Expression,
    ):
        """Records one rewrite, unless its tag exceeds the detail.

        Args:
            tag: The importance tag of the step.
            rule: The rule name that justifies the rewrite.
            before: The subexpression before the rewrite.
            after: The subexpression after the rewrite.
        """
        if not self.wants(tag):
            return
        self._steps.append(Step(tag, rule, before, after))

    def num_steps(self) -> Int:
        """Returns the number of recorded steps.

        Returns:
            The step count.
        """
        return len(self._steps)

    def step(self, index: Int) -> Step:
        """Returns the recorded step at `index`.

        Args:
            index: The zero-based step position.

        Returns:
            A copy of the step.
        """
        return self._steps[index].copy()

    def __str__(self) -> String:
        """Returns the plain-text rendering of the trace.

        Returns:
            One numbered line per step, or `"(no steps recorded)"` when
            empty.
        """
        var out = String()
        self.write_to(out)
        return out^

    def write_to[W: Writer](self, mut writer: W):
        """Writes the trace as numbered lines, one per step.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        if len(self._steps) == 0:
            writer.write("(no steps recorded)")
            return
        for i in range(len(self._steps)):
            writer.write(i + 1, ". ", self._steps[i], "\n")


struct Derivation(Copyable, Movable, Writable):
    """The result of a traced computation: the problem, the answer, and the
    steps in between.

    Returned by the `detail` overloads of the engines, e.g.
    `differentiate(e, "x", detail=2)`. The fields are public: `d.input` is
    the problem statement, `d.result` is the final expression, and `d.trace`
    holds the recorded steps.
    """

    var input: Expression
    """The problem statement: the expression the computation started from.
    Differentiation stores the marker form `d/dvar(e)`; `simplify` stores the
    input expression itself."""
    var result: Expression
    """The final (simplified) expression."""
    var trace: Trace
    """The steps recorded while computing `result`."""

    def __init__(
        out self,
        var input: Expression,
        var result: Expression,
        var trace: Trace,
    ):
        """Initializes a derivation from its parts.

        Args:
            input: The problem statement (owned).
            result: The final expression (owned).
            trace: The recorded trace (owned).
        """
        self.input = input^
        self.result = result^
        self.trace = trace^

    def __str__(self) -> String:
        """Returns the plain-text rendering: the problem, the steps, then the
        result.

        Returns:
            The problem line, the numbered steps, and a final `"=> result"`
            line.
        """
        var out = String()
        self.write_to(out)
        return out^

    def write_to[W: Writer](self, mut writer: W):
        """Writes the problem, the numbered steps, and the final result.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        writer.write(self.input, "\n")
        if self.trace.num_steps() > 0:
            self.trace.write_to(writer)
        writer.write("=> ", self.result)
