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

"""Implements the core symbolic expression tree for Symo.

This module defines `ExpressionKind` (the tag identifying a node) and `Expression`, an
immutable symbolic expression built from six kinds of node: `Symbol`, `Number`,
`Add`, `Multiply`, `Power`, and `Function`. Every other module in Symo operates on
values of type `Expression`.

`Number` nodes wrap a Decimo `BigDecimal` so that constant arithmetic stays
exact. `Add` and `Multiply` are n-ary and are kept flat by their builders (a sum of
sums is spliced into a single sum). Subtraction and division are not separate
node kinds: `a - b` is `a + (-1)*b` and `a / b` is `a * b**(-1)`. The printer
reconstructs the familiar `-` and `/` notation from that canonical shape.
"""

from decimo import BigDecimal


struct ExpressionKind:
    """The tag identifying which kind of node an `Expression` is.

    These are plain integer codes; `Expression` stores one in its `_kind` field and
    compares it against these constants.
    """

    comptime SYMBOL: Int = 0
    """A named symbol such as `x` or `theta`."""
    comptime NUMBER: Int = 1
    """An exact numeric constant backed by a Decimo `BigDecimal`."""
    comptime ADD: Int = 2
    """An n-ary sum of its operands."""
    comptime MULTIPLY: Int = 3
    """An n-ary product of its operands."""
    comptime POWER: Int = 4
    """A power `base ** exponent` (exactly two operands)."""
    comptime FUNCTION: Int = 5
    """A named function application such as `sin(x)`."""


struct Expression(Copyable, Movable, Writable):
    """An immutable symbolic expression.

    An `Expression` is one of six kinds (see `ExpressionKind`). Leaves carry data directly:
    a `Symbol` uses `_name`, a `Number` uses `_value`. Internal nodes (`Add`,
    `Multiply`, `Power`, `Function`) carry their operands in `_args`; a `Function` also
    uses `_name` for its function name.

    Build expressions with the static constructors (`Expression.symbol`,
    `Expression.number`, ...) or with the arithmetic operators (`+`, `-`, `*`, `/`,
    `**`), which accept both `Expression` and `Int` operands.

    Notes:

    Equality is structural and order-sensitive: `x + y` does not compare equal
    to `y + x`. Canonical ordering is the responsibility of the `simplify`
    module and is not applied here.
    """

    # ===------------------------------------------------------------------=== #
    # Internal representation fields
    # ===------------------------------------------------------------------=== #

    var _kind: Int
    """The node kind (one of the `ExpressionKind` constants)."""
    var _name: String
    """The identifier for a `Symbol`, or the name of a `Function`."""
    var _value: BigDecimal
    """The numeric value for a `Number` node (unused otherwise)."""
    var _args: List[Expression]
    """The child operands (empty for `Symbol` and `Number` leaves)."""

    # ===------------------------------------------------------------------=== #
    # Precedence levels used by the printer
    # ===------------------------------------------------------------------=== #

    comptime _PREC_ADD: Int = 1
    """Binding strength of a sum (weakest)."""
    comptime _PREC_MULTIPLY: Int = 2
    """Binding strength of a product."""
    comptime _PREC_POWER: Int = 3
    """Binding strength of a power."""
    comptime _PREC_ATOM: Int = 4
    """Binding strength of an atom: symbol, number, or function (strongest)."""

    # ===------------------------------------------------------------------=== #
    # Constructors and life time methods
    # ===------------------------------------------------------------------=== #

    def __init__(
        out self,
        kind: Int,
        name: String,
        value: BigDecimal,
        var args: List[Expression],
    ):
        """Initializes an `Expression` from its raw fields.

        This is a low-level constructor; prefer the named static constructors
        (`Expression.symbol`, `Expression.number`, `Expression.add`, ...) which enforce the
        invariants of each node kind.

        Args:
            kind: The node kind (an `ExpressionKind` constant).
            name: The symbol/function name (empty for other kinds).
            value: The numeric value (`Number` nodes only).
            args: The child operands (owned).
        """
        self._kind = kind
        self._name = name
        self._value = value.copy()
        self._args = args^

    # ===------------------------------------------------------------------=== #
    # Constructing methods that are not dunders
    # ===------------------------------------------------------------------=== #

    @staticmethod
    def symbol(name: String) -> Expression:
        """Creates a `Symbol` node.

        Args:
            name: The symbol's name, e.g. `"x"`.

        Returns:
            A `Symbol` expression.
        """
        return Expression(
            ExpressionKind.SYMBOL, name, BigDecimal(), List[Expression]()
        )

    @staticmethod
    def number(value: BigDecimal) -> Expression:
        """Creates a `Number` node from a Decimo `BigDecimal`.

        Args:
            value: The exact numeric value.

        Returns:
            A `Number` expression.
        """
        return Expression(
            ExpressionKind.NUMBER, String(), value, List[Expression]()
        )

    @staticmethod
    def number(value: Int) -> Expression:
        """Creates a `Number` node from an integer.

        Args:
            value: The integer value.

        Returns:
            A `Number` expression.
        """
        return Expression.number(BigDecimal(value))

    @staticmethod
    def number(value: String) raises -> Expression:
        """Creates a `Number` node by parsing a decimal string.

        Args:
            value: A decimal string such as `"1.5"` or `"-42"`.

        Returns:
            A `Number` expression.

        Raises:
            Error: If `value` is not a valid decimal string.
        """
        return Expression.number(BigDecimal(value))

    @staticmethod
    def add(var terms: List[Expression]) -> Expression:
        """Creates a flattened n-ary `Add` node.

        Any operand that is itself an `Add` is spliced in, so the result never
        contains a sum directly inside a sum. A zero-length sum collapses to the
        number `0`; a one-term sum collapses to that term.

        Args:
            terms: The summands (owned).

        Returns:
            The resulting expression.
        """
        var flat = List[Expression]()
        for i in range(len(terms)):
            if terms[i]._kind == ExpressionKind.ADD:
                for j in range(len(terms[i]._args)):
                    flat.append(terms[i]._args[j].copy())
            else:
                flat.append(terms[i].copy())
        if len(flat) == 0:
            return Expression.number(0)
        if len(flat) == 1:
            return flat[0].copy()
        return Expression(ExpressionKind.ADD, String(), BigDecimal(), flat^)

    @staticmethod
    def multiply(var factors: List[Expression]) -> Expression:
        """Creates a flattened n-ary `Multiply` node.

        Any operand that is itself a `Multiply` is spliced in, so the result never
        contains a product directly inside a product. A zero-length product
        collapses to the number `1`; a one-factor product collapses to that
        factor.

        Args:
            factors: The factors (owned).

        Returns:
            The resulting expression.
        """
        var flat = List[Expression]()
        for i in range(len(factors)):
            if factors[i]._kind == ExpressionKind.MULTIPLY:
                for j in range(len(factors[i]._args)):
                    flat.append(factors[i]._args[j].copy())
            else:
                flat.append(factors[i].copy())
        if len(flat) == 0:
            return Expression.number(1)
        if len(flat) == 1:
            return flat[0].copy()
        return Expression(
            ExpressionKind.MULTIPLY, String(), BigDecimal(), flat^
        )

    @staticmethod
    def power(base: Expression, exponent: Expression) -> Expression:
        """Creates a `Power` node `base ** exponent`.

        Args:
            base: The base expression.
            exponent: The exponent expression.

        Returns:
            A `Power` expression.
        """
        var args = List[Expression]()
        args.append(base.copy())
        args.append(exponent.copy())
        return Expression(ExpressionKind.POWER, String(), BigDecimal(), args^)

    @staticmethod
    def function(name: String, var args: List[Expression]) -> Expression:
        """Creates a `Function` application node.

        Args:
            name: The function name, e.g. `"sin"`.
            args: The argument expressions (owned).

        Returns:
            A `Function` expression.
        """
        return Expression(ExpressionKind.FUNCTION, name, BigDecimal(), args^)

    # ===------------------------------------------------------------------=== #
    # Basic unary arithmetic operation dunders
    # ===------------------------------------------------------------------=== #

    def __neg__(self) -> Expression:
        """Returns the negation `-self`, encoded as `(-1) * self`.

        Returns:
            The negated expression.
        """
        var factors = List[Expression]()
        factors.append(Expression.number(-1))
        factors.append(self.copy())
        return Expression.multiply(factors^)

    # ===------------------------------------------------------------------=== #
    # Basic binary arithmetic operation dunders
    # ===------------------------------------------------------------------=== #

    def __add__(self, other: Expression) -> Expression:
        """Adds two expressions.

        Args:
            other: The right-hand operand.

        Returns:
            The sum `self + other`.
        """
        var terms = List[Expression]()
        terms.append(self.copy())
        terms.append(other.copy())
        return Expression.add(terms^)

    def __add__(self, other: Int) -> Expression:
        """Adds an integer to this expression.

        Args:
            other: The integer to add.

        Returns:
            The sum `self + other`.
        """
        return self + Expression.number(other)

    def __sub__(self, other: Expression) -> Expression:
        """Subtracts two expressions, encoded as `self + (-other)`.

        Args:
            other: The right-hand operand.

        Returns:
            The difference `self - other`.
        """
        return self + (-other)

    def __sub__(self, other: Int) -> Expression:
        """Subtracts an integer from this expression.

        Args:
            other: The integer to subtract.

        Returns:
            The difference `self - other`.
        """
        return self - Expression.number(other)

    def __mul__(self, other: Expression) -> Expression:
        """Multiplies two expressions.

        Args:
            other: The right-hand operand.

        Returns:
            The product `self * other`.
        """
        var factors = List[Expression]()
        factors.append(self.copy())
        factors.append(other.copy())
        return Expression.multiply(factors^)

    def __mul__(self, other: Int) -> Expression:
        """Multiplies this expression by an integer.

        Args:
            other: The integer factor.

        Returns:
            The product `self * other`.
        """
        return self * Expression.number(other)

    def __truediv__(self, other: Expression) -> Expression:
        """Divides two expressions, encoded as `self * other**(-1)`.

        Args:
            other: The divisor.

        Returns:
            The quotient `self / other`.
        """
        var factors = List[Expression]()
        factors.append(self.copy())
        factors.append(Expression.power(other, Expression.number(-1)))
        return Expression.multiply(factors^)

    def __truediv__(self, other: Int) -> Expression:
        """Divides this expression by an integer.

        Args:
            other: The integer divisor.

        Returns:
            The quotient `self / other`.
        """
        return self / Expression.number(other)

    def __pow__(self, other: Expression) -> Expression:
        """Raises this expression to an expression power.

        Args:
            other: The exponent.

        Returns:
            The power `self ** other`.
        """
        return Expression.power(self, other)

    def __pow__(self, other: Int) -> Expression:
        """Raises this expression to an integer power.

        Args:
            other: The integer exponent.

        Returns:
            The power `self ** other`.
        """
        return Expression.power(self, Expression.number(other))

    # ===------------------------------------------------------------------=== #
    # Basic binary arithmetic operation dunders with reflected operands
    # ===------------------------------------------------------------------=== #

    def __radd__(self, other: Int) -> Expression:
        """Adds this expression to an integer (reflected).

        Args:
            other: The left-hand integer operand.

        Returns:
            The sum `other + self`.
        """
        return Expression.number(other) + self

    def __rsub__(self, other: Int) -> Expression:
        """Subtracts this expression from an integer (reflected).

        Args:
            other: The left-hand integer operand.

        Returns:
            The difference `other - self`.
        """
        return Expression.number(other) - self

    def __rmul__(self, other: Int) -> Expression:
        """Multiplies an integer by this expression (reflected).

        Args:
            other: The left-hand integer operand.

        Returns:
            The product `other * self`.
        """
        return Expression.number(other) * self

    def __rtruediv__(self, other: Int) -> Expression:
        """Divides an integer by this expression (reflected).

        Args:
            other: The left-hand integer operand.

        Returns:
            The quotient `other / self`.
        """
        return Expression.number(other) / self

    # ===------------------------------------------------------------------=== #
    # Basic comparison operation dunders
    # ===------------------------------------------------------------------=== #

    def __eq__(self, other: Expression) -> Bool:
        """Compares two expressions for structural equality.

        Two expressions are equal when they have the same kind and the same
        data. For `Add` and `Multiply` the comparison is order-sensitive.

        Args:
            other: The expression to compare against.

        Returns:
            `True` if the expressions are structurally equal.
        """
        if self._kind != other._kind:
            return False
        if self._kind == ExpressionKind.SYMBOL:
            return self._name == other._name
        if self._kind == ExpressionKind.NUMBER:
            return self._value == other._value
        if self._kind == ExpressionKind.FUNCTION:
            if self._name != other._name:
                return False
        if len(self._args) != len(other._args):
            return False
        for i in range(len(self._args)):
            if not (self._args[i] == other._args[i]):
                return False
        return True

    def __ne__(self, other: Expression) -> Bool:
        """Compares two expressions for structural inequality.

        Args:
            other: The expression to compare against.

        Returns:
            `True` if the expressions are not structurally equal.
        """
        return not (self == other)

    # ===------------------------------------------------------------------=== #
    # Output dunders and type-transfer methods
    # ===------------------------------------------------------------------=== #

    def __str__(self) -> String:
        """Returns the infix string representation of this expression.

        Returns:
            The rendered expression, e.g. `"x**2 + 3*x - 1"`.
        """
        var out = String()
        self.write_to(out)
        return out^

    def write_to[W: Writer](self, mut writer: W):
        """Writes the infix representation of this expression to a writer.

        Implements the `Writable` trait so that `print(expr)` and
        `String(expr)` work.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        self._write(writer, 0)

    # ===------------------------------------------------------------------=== #
    # Internal printing helpers
    # ===------------------------------------------------------------------=== #

    def _prec(self) -> Int:
        """Returns the binding strength (precedence) of this node.

        Returns:
            One of the `_PREC_*` levels.
        """
        if self._kind == ExpressionKind.ADD:
            return Expression._PREC_ADD
        if self._kind == ExpressionKind.MULTIPLY:
            return Expression._PREC_MULTIPLY
        if self._kind == ExpressionKind.POWER:
            return Expression._PREC_POWER
        return Expression._PREC_ATOM

    def _write[W: Writer](self, mut writer: W, parent_prec: Int):
        """Writes this node, parenthesizing it when its precedence is lower
        than the surrounding context.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
            parent_prec: The precedence required by the enclosing context.
        """
        var need_paren = self._prec() < parent_prec
        if need_paren:
            writer.write("(")

        if self._kind == ExpressionKind.SYMBOL:
            writer.write(self._name)
        elif self._kind == ExpressionKind.NUMBER:
            writer.write(String(self._value))
        elif self._kind == ExpressionKind.FUNCTION:
            writer.write(self._name)
            writer.write("(")
            for i in range(len(self._args)):
                if i > 0:
                    writer.write(", ")
                self._args[i]._write(writer, 0)
            writer.write(")")
        elif self._kind == ExpressionKind.POWER:
            self._write_power(writer)
        elif self._kind == ExpressionKind.MULTIPLY:
            self._write_multiply(writer)
        elif self._kind == ExpressionKind.ADD:
            self._write_add(writer)

        if need_paren:
            writer.write(")")

    def _write_power[W: Writer](self, mut writer: W):
        """Writes a `Power` node as `base**exponent`.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        # Parenthesize a bare negative-number base so that `-2**3` (which reads
        # as `-(2**3)`) is not produced by accident.
        if (
            self._args[0]._kind == ExpressionKind.NUMBER
            and self._args[0]._value.is_negative()
        ):
            writer.write("(")
            writer.write(String(self._args[0]._value))
            writer.write(")")
        else:
            self._args[0]._write(writer, Expression._PREC_ATOM)
        writer.write("**")
        self._args[1]._write(writer, Expression._PREC_POWER)

    def _write_multiply[W: Writer](self, mut writer: W):
        """Writes a `Multiply` node, reconstructing `/` from negative powers.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        var numerators = List[Int]()
        var denominators = List[Int]()
        for i in range(len(self._args)):
            if self._args[i]._is_reciprocal():
                denominators.append(i)
            else:
                numerators.append(i)

        if len(numerators) == 0:
            writer.write("1")
        else:
            self._write_factor_list(writer, numerators, False)
        if len(denominators) > 0:
            self._write_denominator(writer, denominators)

    def _write_add[W: Writer](self, mut writer: W):
        """Writes an `Add` node, using `-` for negative terms.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        self._args[0]._write(writer, Expression._PREC_ADD)
        for i in range(1, len(self._args)):
            if self._args[i]._is_negative_term():
                writer.write(" - ")
                self._args[i]._write_negated(writer)
            else:
                writer.write(" + ")
                self._args[i]._write(writer, Expression._PREC_ADD)

    def _write_factor_list[
        W: Writer
    ](self, mut writer: W, indices: List[Int], negate: Bool):
        """Writes the numerator factors named by `indices`, joined by `*`.

        A leading numeric coefficient of magnitude `1` is dropped (its sign is
        emitted as a `-` prefix). When `negate` is `True`, the sign of that
        leading coefficient is flipped first; this is how negative sum terms are
        printed without their `-1` factor.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
            indices: Positions in `_args` of the numerator factors.
            negate: Whether to flip the leading coefficient's sign.
        """
        var wrote = False
        var start = 0
        var first = indices[0]
        if self._args[first]._kind == ExpressionKind.NUMBER:
            var coefficient = self._args[first]._value.copy()
            if negate:
                coefficient = -coefficient
            if coefficient == BigDecimal(1) and len(indices) > 1:
                start = 1
            elif coefficient == BigDecimal(-1) and len(indices) > 1:
                writer.write("-")
                start = 1
            else:
                writer.write(String(coefficient))
                wrote = True
                start = 1
        for k in range(start, len(indices)):
            if wrote:
                writer.write("*")
            self._args[indices[k]]._write(writer, Expression._PREC_MULTIPLY)
            wrote = True
        if not wrote:
            writer.write("1")

    def _write_denominator[W: Writer](self, mut writer: W, indices: List[Int]):
        """Writes `/` followed by the reciprocal factors named by `indices`.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
            indices: Positions in `_args` of the reciprocal (negative-power)
                factors.
        """
        writer.write("/")
        if len(indices) == 1:
            self._args[indices[0]]._write_reciprocal_base(
                writer, Expression._PREC_POWER
            )
        else:
            writer.write("(")
            for k in range(len(indices)):
                if k > 0:
                    writer.write("*")
                self._args[indices[k]]._write_reciprocal_base(
                    writer, Expression._PREC_MULTIPLY
                )
            writer.write(")")

    def _write_negated[W: Writer](self, mut writer: W):
        """Writes the positive magnitude of a negative term (for use after a
        `-` separator in a sum).

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        if self._kind == ExpressionKind.NUMBER:
            writer.write(String(-self._value))
            return
        var numerators = List[Int]()
        var denominators = List[Int]()
        for i in range(len(self._args)):
            if self._args[i]._is_reciprocal():
                denominators.append(i)
            else:
                numerators.append(i)
        if len(numerators) == 0:
            writer.write("1")
        else:
            self._write_factor_list(writer, numerators, True)
        if len(denominators) > 0:
            self._write_denominator(writer, denominators)

    def _write_reciprocal_base[
        W: Writer
    ](self, mut writer: W, parent_prec: Int):
        """Writes a reciprocal factor `base**(-n)` in denominator form: `base`
        when `n == 1`, otherwise `base**n`.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
            parent_prec: The precedence required by the enclosing context.
        """
        var positive_exponent = -self._args[1]._value
        if positive_exponent == BigDecimal(1):
            self._args[0]._write(writer, parent_prec)
        else:
            var need_paren = Expression._PREC_POWER < parent_prec
            if need_paren:
                writer.write("(")
            self._args[0]._write(writer, Expression._PREC_ATOM)
            writer.write("**")
            writer.write(String(positive_exponent))
            if need_paren:
                writer.write(")")

    def _is_reciprocal(self) -> Bool:
        """Returns whether this node is a power with a negative numeric
        exponent (i.e. a denominator factor).

        Returns:
            `True` if this is `base ** (negative number)`.
        """
        return (
            self._kind == ExpressionKind.POWER
            and self._args[1]._kind == ExpressionKind.NUMBER
            and self._args[1]._value.is_negative()
        )

    def _is_negative_term(self) -> Bool:
        """Returns whether this node prints with a leading minus sign as a sum
        term (a negative number, or a product with a negative leading
        coefficient).

        Returns:
            `True` if this term should be rendered after a `-` separator.
        """
        if self._kind == ExpressionKind.NUMBER:
            return self._value.is_negative()
        if self._kind == ExpressionKind.MULTIPLY and len(self._args) > 0:
            return (
                self._args[0]._kind == ExpressionKind.NUMBER
                and self._args[0]._value.is_negative()
            )
        return False
