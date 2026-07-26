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

"""String-DSL parser: text -> `Expression`.

`parse(text)` turns a string such as `"x**2 + 3*x - 1"` into an `Expression`
tree. It removes the need to declare symbols up front: any identifier that is
not immediately followed by `(` becomes a free `Symbol`, discovered on the
fly, while an identifier followed by `(` is a function call. Numeric literals
become Decimo-backed `Number` nodes, so they stay exact.

Design notes (improvements over Decimo's numeric parser, which this takes as a
reference):

- **It produces a tree, not a value.** Decimo's parser is a shunting-yard
  evaluator that folds the input to a single number and cannot represent an
  unbound symbol. Symo's parser is the whole point of the symbolic layer: it
  yields an `Expression` with free symbols preserved.
- **It is a Pratt (precedence-climbing) parser**, going straight from tokens
  to a tree in one pass, rather than tokens -> RPN -> value in two. Operator
  precedence and associativity live in one small table.
- **Function names are open.** Any `identifier(...)` is accepted as a
  `Function` node; the parser does not keep a fixed list of known functions.
  Whether a given function can be differentiated or evaluated is a separate
  concern handled by those engines.

The tree is built with the ordinary `Expression` operators, so the result is
already in canonical form: `a - b` is `a + (-1)*b`, `a / b` is `a * b**(-1)`,
and sums/products are flattened.

Precedence, from loosest to tightest binding:

| Operator      | Binding | Associativity |
|---------------|:-------:|:-------------:|
| `+` `-`       |   10    | left          |
| `*` `/`       |   20    | left          |
| unary `-`     |   30    | prefix        |
| `**` `^`      |   40    | right         |

Unary minus binding between `*`/`/` and `**` reproduces the familiar reading
where `-x**2` is `-(x**2)` but `-x*y` is `(-x)*y`.
"""

from symo.core.expression import Expression
from symo.errors import ParseError
from symo.parser.tokenizer import Token, TokenKind, tokenize


def parse(text: String) raises -> Expression:
    """Parses an expression string into an `Expression` tree.

    Args:
        text: The expression to parse, e.g. `"x**2 + 3*x - 1"`.

    Returns:
        The parsed expression, in canonical form.

    Raises:
        ParseError: On empty input, an unexpected character or token, or
            unbalanced parentheses. The message carries the column position.
    """
    var tokens = tokenize(text)
    var parser = _Parser(tokens^)
    return parser.parse()


struct _Parser:
    """A single-use Pratt parser over a token list.

    Holds the tokens and a cursor; each parse method advances the cursor and
    returns the subtree it consumed. Not meant to be reused: construct one per
    `parse` call.
    """

    var _tokens: List[Token]
    """The tokens to parse, terminated by a `TokenKind.END` sentinel."""
    var _position: Int
    """The cursor: the index of the next token to consume."""

    def __init__(out self, var tokens: List[Token]):
        """Initializes the parser over a token list.

        Args:
            tokens: The tokens to parse (owned); must end with `END`.
        """
        self._tokens = tokens^
        self._position = 0

    def _kind(self) -> Int:
        """Returns the kind of the current (next-to-consume) token.

        Returns:
            The `TokenKind` of the token under the cursor.
        """
        return self._tokens[self._position].kind

    def _advance(mut self) -> Token:
        """Consumes the current token and returns it.

        Returns:
            The token that was under the cursor before advancing.
        """
        var token = self._tokens[self._position].copy()
        self._position += 1
        return token^

    def parse(mut self) raises -> Expression:
        """Parses the whole token list into one expression.

        Returns:
            The parsed expression.

        Raises:
            ParseError: On malformed input, or trailing tokens after a
                complete expression.
        """
        if self._kind() == TokenKind.END:
            raise ParseError(message="empty expression", function="parse()")
        var result = self._parse_expression(0)
        if self._kind() != TokenKind.END:
            var token = self._tokens[self._position]
            raise ParseError(
                message=String("unexpected '")
                + token.text
                + "' at position "
                + String(token.position),
                function="parse()",
            )
        return result^

    def _parse_expression(mut self, minimum_binding: Int) raises -> Expression:
        """Parses an expression whose operators bind at least `minimum_binding`.

        This is the core of the precedence-climbing loop: it parses a prefix
        term, then keeps absorbing infix operators as long as their binding
        power is high enough.

        Args:
            minimum_binding: The lowest operator binding power this call may
                consume; operators looser than this are left to the caller.

        Returns:
            The parsed subexpression.

        Raises:
            ParseError: On malformed input.
        """
        var left = self._parse_prefix()

        while True:
            var kind = self._kind()
            var binding = _left_binding(kind)
            if binding == 0 or binding < minimum_binding:
                break
            _ = self._advance()
            var right = self._parse_expression(_right_binding(kind))
            left = _apply_binary(kind, left, right)

        return left^

    def _parse_prefix(mut self) raises -> Expression:
        """Parses a prefix term: an optional unary minus then a primary.

        Returns:
            The parsed subexpression.

        Raises:
            ParseError: On malformed input.
        """
        if self._kind() == TokenKind.MINUS:
            _ = self._advance()
            # Unary minus binds tighter than `*`/`/` but looser than `**`.
            var operand = self._parse_expression(30)
            return -operand
        return self._parse_primary()

    def _parse_primary(mut self) raises -> Expression:
        """Parses a primary: a number, a symbol, a function call, or a
        parenthesized subexpression.

        Returns:
            The parsed subexpression.

        Raises:
            ParseError: On an unexpected token or unbalanced parentheses.
        """
        var kind = self._kind()

        if kind == TokenKind.NUMBER:
            var token = self._advance()
            return Expression.number(token.text)

        if kind == TokenKind.IDENTIFIER:
            var token = self._advance()
            if self._kind() == TokenKind.LPAREN:
                _ = self._advance()  # consume '('
                var arguments = self._parse_arguments()
                self._expect(TokenKind.RPAREN, ")")
                return Expression.function(token.text, arguments^)
            return Expression.symbol(token.text)

        if kind == TokenKind.LPAREN:
            _ = self._advance()
            var inner = self._parse_expression(0)
            self._expect(TokenKind.RPAREN, ")")
            return inner^

        var token = self._tokens[self._position]
        var what: String
        if kind == TokenKind.END:
            what = "end of input"
        else:
            what = String("'") + token.text + "'"
        raise ParseError(
            message=String("expected a number, symbol, or '(' but found ")
            + what
            + " at position "
            + String(token.position),
            function="parse()",
        )

    def _parse_arguments(mut self) raises -> List[Expression]:
        """Parses a comma-separated function argument list (possibly empty),
        stopping at the closing parenthesis.

        Returns:
            The argument expressions.

        Raises:
            ParseError: On malformed input.
        """
        var arguments = List[Expression]()
        if self._kind() == TokenKind.RPAREN:
            return arguments^
        arguments.append(self._parse_expression(0))
        while self._kind() == TokenKind.COMMA:
            _ = self._advance()
            arguments.append(self._parse_expression(0))
        return arguments^

    def _expect(mut self, kind: Int, description: String) raises:
        """Consumes the current token, requiring it to be of a given kind.

        Args:
            kind: The `TokenKind` that must appear next.
            description: A human-readable spelling of the expected token, for
                the error message (e.g. `")"`).

        Raises:
            ParseError: If the current token is not of the required kind.
        """
        if self._kind() != kind:
            var token = self._tokens[self._position]
            var what: String
            if token.kind == TokenKind.END:
                what = "end of input"
            else:
                what = String("'") + token.text + "'"
            raise ParseError(
                message=String("expected '")
                + description
                + "' but found "
                + what
                + " at position "
                + String(token.position),
                function="parse()",
            )
        _ = self._advance()


# ===----------------------------------------------------------------------=== #
# Operator binding-power table
# ===----------------------------------------------------------------------=== #


def _left_binding(kind: Int) -> Int:
    """Returns the left binding power of an infix operator token.

    A return of `0` means the token is not an infix operator, which ends the
    precedence-climbing loop.

    Args:
        kind: The `TokenKind` to look up.

    Returns:
        The left binding power, or `0` for non-operators.
    """
    if kind == TokenKind.PLUS or kind == TokenKind.MINUS:
        return 10
    if kind == TokenKind.STAR or kind == TokenKind.SLASH:
        return 20
    if kind == TokenKind.CARET:
        return 40
    return 0


def _right_binding(kind: Int) -> Int:
    """Returns the right binding power of an infix operator token.

    Left-associative operators recurse with `left + 1` so an equal-precedence
    operator to the right is left to the caller; the right-associative `**`
    recurses with its own power so it groups to the right.

    Args:
        kind: The `TokenKind` to look up.

    Returns:
        The right binding power.
    """
    if kind == TokenKind.PLUS or kind == TokenKind.MINUS:
        return 11
    if kind == TokenKind.STAR or kind == TokenKind.SLASH:
        return 21
    if kind == TokenKind.CARET:
        return 40
    return 0


def _apply_binary(
    kind: Int, left: Expression, right: Expression
) raises -> Expression:
    """Builds the subtree for a binary operator, in canonical form.

    Args:
        kind: The operator `TokenKind`.
        left: The left operand.
        right: The right operand.

    Returns:
        The combined expression (`+`, `-`, `*`, `/`, or `**`).

    Raises:
        ParseError: If `kind` is not a known binary operator (a parser bug).
    """
    if kind == TokenKind.PLUS:
        return left + right
    if kind == TokenKind.MINUS:
        return left - right
    if kind == TokenKind.STAR:
        return left * right
    if kind == TokenKind.SLASH:
        return left / right
    if kind == TokenKind.CARET:
        return Expression.power(left, right)
    raise ParseError(
        message=String("internal parser error: not a binary operator (kind ")
        + String(kind)
        + ")",
        function="parse()",
    )
