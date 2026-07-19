# Symo development plan

Status: scaffolding. This document sketches the architecture, module
responsibilities, and build order for Symo — a symbolic computation library for
Mojo built on top of [Decimo](https://github.com/forfudan/decimo).

## Guiding idea

Decimo already gives us arbitrary-precision integers and decimals. Symo sits on
top as the *symbolic* layer: an immutable expression tree (`Expression`) whose
`Number` leaves hold Decimo values. Anything that needs an exact number —
constant folding, `evalf`, evaluating an elementary function — hands the work
to Decimo. We don't reimplement arithmetic; we orchestrate it.

### What a `Number` holds

For now, a `Number` wraps a Decimo `BigInt` (exact integers) or `BigDecimal`
(exact decimals). That covers the whole early roadmap.

Exact fractions like `1/3` are a separate concern. Decimo already has a
`Rational` type (a `BigInt` numerator and denominator kept in lowest terms), so
when we want them we should use that rather than build our own on top of
`BigInt`. It isn't essential up front — `BigDecimal` is enough to get `core`,
`printer`, `simplify`, and differentiation working — so we defer it. It starts
to matter in `algebra`, where exact rational coefficients make cancellation and
factoring clean (`x/3 + x/6` should collapse to `x/2`, not a rounded decimal).
The plan: add a `Rational` variant to `Number` around the time `algebra` lands,
backed by Decimo's `Rational`, and lean on Decimo to mature that type as we go.

## Modules

### `core` — the expression tree

- `Expression` with node kinds: `Symbol`, `Number`, `Add`, `Multiply`, `Power`, `Function`.
- `Number` wraps a Decimo `BigInt` or `BigDecimal` at first, with a `Rational`
  variant (backed by Decimo's `Rational`) added later — see "What a `Number`
  holds" above.
- Structural equality, hashing, immutability.
- Basic tree traversal / visitor helpers.

### `parser` — construction

- Operator overloading (`+ - * / **`) on `Expression` for natural Mojo syntax.
- Optional string DSL (`"x**2 + 3*x - 1"` -> `Expression`).
- **Decision:** the symbolic parser lives in Symo, not Decimo. Decimo's parser
  is a numeric evaluator (shunting-yard -> value) and does not preserve unbound
  symbols or produce a tree. Symo can borrow tokenizer ideas but needs its own
  tree-producing parser.

### `simplify`

- Constant folding via Decimo arithmetic (exact).
- Flattening nested `Add`/`Multiply`, like-term collection, canonical ordering.
- Identity rules: `x*1`, `x+0`, `x**0`, `x**1`, etc.

### `algebra`

- Polynomial representation + `expand` / `collect` / `factor`.
- Rational-function simplification (common denominators, cancellation).
- Equation solving: linear first, then low-degree polynomial roots.

### `calculus`

- Differentiation: rule-based, recursive over the tree.
- Integration: pattern-matching common forms.
- Limits: start with a small rule table (stubs).

### `functions`

- Elementary functions as `Expression` nodes: `sin`, `cos`, `exp`, `log`, `sqrt`, ...
- Each carries its own derivative rule, simplification rules, and a Decimo-based
  numeric implementation.

### `numeric`

- `subs`: substitute symbols with expressions or Decimo `BigDecimal` values.
- `evalf`: high-precision numeric evaluation of any expression tree via Decimo.

### `printer`

- Infix string printer (correct precedence, minimal parentheses).
- LaTeX output (later).

### `linear_algebra` (stretch goal)

- Symbolic vectors/matrices whose elements are `Expression`.

## Build order

1. `core` — the foundation everything depends on.
2. `printer` — built early so progress can be inspected visually.
3. `simplify` — needed before algebra/calculus produce readable results.
4. `functions` and `algebra` — can proceed in parallel once simplify exists.
5. `calculus` — depends on `core`, `simplify`, and `functions`.
6. `numeric` — substitution + Decimo-backed evaluation, ties symbolic to exact.
7. `parser` string DSL — convenience layer once the tree API is stable.
8. `linear_algebra` — stretch goal, last.

Decimo slots in early: as the concrete number type inside `Number` nodes and as
the evaluation backend in `numeric`.

## Milestones

- **M0 (done):** repo scaffold, package layout, tasks, placeholders.
- **M1 (done):** `core.Expression` + operator overloading (`+ - * / **`, `Expression` and
  `Int` operands) + `printer.to_string`; a hand-built expression round-trips to
  text. Subtraction and division are reconstructed by the printer from the
  canonical `+ (-1)*` / `* **(-1)` forms. Covered by `tests/core/test_expression.mojo`.
- **M2:** `simplify` with constant folding and basic identities.
- **M3:** `calculus.differentiation` over polynomials and elementary functions.
- **M4:** `numeric.subs` / `evalf` against Decimo at configurable precision.
- **M5:** string DSL parser; `algebra` expand/collect.
- **M6+:** factoring, integration, limits, `linear_algebra`.

## Open questions

- When exactly to introduce the `Rational` variant of `Number`. Leaning toward
  "once `algebra` needs exact coefficients", using Decimo's `Rational` rather
  than a home-grown `BigInt` pair. Not needed for the earlier milestones.
- What key to sort terms and factors by. This drives hashing and structural
  equality, so it needs pinning down before `simplify` gets serious.
- How much to normalize eagerly in the `core` builders versus leaving it to
  `simplify`. Too much eager work makes `core` heavy; too little makes every
  other module defensive.
