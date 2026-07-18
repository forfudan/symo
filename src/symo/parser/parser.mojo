"""String DSL parser: text -> `Expr`.

Planned pipeline:

- tokenizer: source text -> tokens (numbers, identifiers, operators, parens)
- parser: tokens -> `Expr` tree (precedence-climbing / Pratt parsing)

Numeric literals are parsed into Decimo-backed `Number` nodes to preserve
exactness; identifiers become `Symbol` nodes.

TODO: implement. This is a placeholder.
"""
