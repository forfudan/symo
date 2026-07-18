"""Expression tree definitions.

Planned contents:

- `ExprKind`: enum tag distinguishing node kinds
  (`Symbol`, `Number`, `Add`, `Mul`, `Pow`, `Function`).
- `Expr`: an immutable, hashable, structurally-comparable expression node.
  `Number` nodes wrap a Decimo `BigInt`/`BigDecimal` for exact arithmetic; an
  exact-fraction case backed by Decimo's `Rational` is planned for later.
- Constructors / smart builders that keep the tree in a lightly-normalized
  form (e.g. flattening nested `Add`/`Mul`).
- Tree traversal / visitor helpers used by `simplify`, `calculus`, etc.

TODO: implement `Expr`. This is a placeholder.
"""

# from decimo import BigDecimal, BigInt
