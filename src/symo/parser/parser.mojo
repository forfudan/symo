"""String DSL parser: text -> `Expression`.

Planned pipeline:

- tokenizer: source text -> tokens (numbers, identifiers, operators, parens)
- parser: tokens -> `Expression` tree (precedence-climbing / Pratt parsing)

Numeric literals are parsed into Decimo-backed `Number` nodes to preserve
exactness; identifiers become `Symbol` nodes.

TODO: implement. This is a placeholder.
"""
