"""Building `Expression` values.

Two construction paths:

1. Operator overloading (`+ - * / **`) on `Expression`, so users can write
   expressions in ordinary Mojo syntax.
2. An optional string DSL parser (e.g. `"x**2 + 3*x - 1"` -> `Expression`).

The string parser is symbolic: unbound identifiers become `Symbol` nodes and
numeric literals become Decimo-backed `Number` nodes. It is distinct from
Decimo's numeric expression evaluator, which produces a number rather than a
tree.
"""

from symo.parser.parser import parse
