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

"""Tokenizer for the Symo string-DSL parser.

`tokenize(text)` converts an expression string into a flat list of `Token`s
for the parser to consume. It recognizes numeric literals, identifiers,
the operators `+ - * / ** ^`, parentheses, and commas, recording the source
column of every token for diagnostics.

Two deliberate differences from Decimo's tokenizer, both suited to Symo's
symbolic use case:

- **Identifiers are not classified here.** Decimo's tokenizer must decide at
  lex time whether an identifier is a known function, a known constant, or a
  pre-declared variable, because its evaluator needs a value for every name.
  Symo has no such need: any identifier can become a free `Symbol`, and
  whether it is instead a function call depends only on whether a `(` follows
  — a decision the parser makes. So the tokenizer emits a single `IDENTIFIER`
  kind and leaves classification to the parser.
- **Minus is not disambiguated here.** Whether `-` is unary or binary is
  decided by the parser from its position, not guessed by the lexer.

Both `**` and `^` tokenize to the same `CARET` (power) kind, so either
spelling is accepted on input; the printer always renders `**`.
"""

from symo.errors import ParseError


struct TokenKind:
    """The tag identifying which kind of token a `Token` is."""

    comptime NUMBER: Int = 0
    """A numeric literal such as `42` or `1.5`."""
    comptime IDENTIFIER: Int = 1
    """A name: becomes a `Symbol`, or a function call when followed by `(`."""
    comptime PLUS: Int = 2
    """The `+` operator."""
    comptime MINUS: Int = 3
    """The `-` operator (unary or binary; the parser decides)."""
    comptime STAR: Int = 4
    """The `*` operator."""
    comptime SLASH: Int = 5
    """The `/` operator."""
    comptime CARET: Int = 6
    """The power operator, spelled `**` or `^`."""
    comptime LPAREN: Int = 7
    """An opening parenthesis `(`."""
    comptime RPAREN: Int = 8
    """A closing parenthesis `)`."""
    comptime COMMA: Int = 9
    """An argument separator `,`."""
    comptime END: Int = 10
    """A sentinel marking the end of input (simplifies the parser)."""


struct Token(Copyable, ImplicitlyCopyable, Movable):
    """A single lexical token with its source position."""

    var kind: Int
    """The token kind (a `TokenKind` constant)."""
    var text: String
    """The token's source text (e.g. `"1.5"`, `"x"`, `"+"`)."""
    var position: Int
    """The 0-based column where the token starts, for diagnostics."""

    def __init__(out self, kind: Int, text: String, position: Int):
        """Initializes a token.

        Args:
            kind: The token kind.
            text: The token's source text.
            position: The 0-based starting column.
        """
        self.kind = kind
        self.text = text
        self.position = position


def _is_digit(c: Int) -> Bool:
    """Returns whether a byte value is an ASCII digit `0`-`9`.

    Args:
        c: The byte value to test.

    Returns:
        `True` if `c` is a digit.
    """
    return c >= ord("0") and c <= ord("9")


def _is_identifier_start(c: Int) -> Bool:
    """Returns whether a byte value may start an identifier (a letter or `_`).

    Args:
        c: The byte value to test.

    Returns:
        `True` if `c` is an ASCII letter or underscore.
    """
    return (
        (c >= ord("a") and c <= ord("z"))
        or (c >= ord("A") and c <= ord("Z"))
        or c == ord("_")
    )


def _is_identifier_continue(c: Int) -> Bool:
    """Returns whether a byte value may continue an identifier (a letter,
    digit, or `_`).

    Args:
        c: The byte value to test.

    Returns:
        `True` if `c` is an ASCII letter, digit, or underscore.
    """
    return _is_identifier_start(c) or _is_digit(c)


def tokenize(text: String) raises -> List[Token]:
    """Converts an expression string into a list of tokens.

    The returned list always ends with a single `TokenKind.END` sentinel, so
    the parser can look ahead without bounds-checking.

    Args:
        text: The expression string, e.g. `"x**2 + 3*x - 1"`.

    Returns:
        The tokens, terminated by an `END` token.

    Raises:
        ParseError: On an unexpected character, with its column position.
    """
    var tokens = List[Token]()
    var bytes = text.as_bytes()
    var n = len(bytes)
    var i = 0

    while i < n:
        var c = Int(bytes[i])

        # Skip ASCII whitespace: space, tab, newline, carriage return.
        if c == ord(" ") or c == ord("\t") or c == ord("\n") or c == ord("\r"):
            i += 1
            continue

        # Number literal: digits with at most one decimal point.
        if _is_digit(c) or c == ord("."):
            var start = i
            var has_dot = c == ord(".")
            i += 1
            while i < n:
                if _is_digit(Int(bytes[i])):
                    i += 1
                elif Int(bytes[i]) == ord(".") and not has_dot:
                    has_dot = True
                    i += 1
                else:
                    break
            tokens.append(
                Token(TokenKind.NUMBER, String(text[byte=start:i]), start)
            )
            continue

        # Identifier: letter/underscore followed by letters/digits/underscores.
        if _is_identifier_start(c):
            var start = i
            i += 1
            while i < n and _is_identifier_continue(Int(bytes[i])):
                i += 1
            tokens.append(
                Token(TokenKind.IDENTIFIER, String(text[byte=start:i]), start)
            )
            continue

        # Operators and punctuation.
        if c == ord("+"):
            tokens.append(Token(TokenKind.PLUS, "+", i))
            i += 1
            continue
        if c == ord("-"):
            tokens.append(Token(TokenKind.MINUS, "-", i))
            i += 1
            continue
        if c == ord("*"):
            # `**` is power; a single `*` is multiplication.
            if i + 1 < n and Int(bytes[i + 1]) == ord("*"):
                tokens.append(Token(TokenKind.CARET, "**", i))
                i += 2
            else:
                tokens.append(Token(TokenKind.STAR, "*", i))
                i += 1
            continue
        if c == ord("/"):
            tokens.append(Token(TokenKind.SLASH, "/", i))
            i += 1
            continue
        if c == ord("^"):
            tokens.append(Token(TokenKind.CARET, "^", i))
            i += 1
            continue
        if c == ord("("):
            tokens.append(Token(TokenKind.LPAREN, "(", i))
            i += 1
            continue
        if c == ord(")"):
            tokens.append(Token(TokenKind.RPAREN, ")", i))
            i += 1
            continue
        if c == ord(","):
            tokens.append(Token(TokenKind.COMMA, ",", i))
            i += 1
            continue

        raise ParseError(
            message=String("unexpected character '")
            + String(text[byte = i : i + 1])
            + "' at position "
            + String(i),
            function="tokenize()",
        )

    tokens.append(Token(TokenKind.END, "", n))
    return tokens^
