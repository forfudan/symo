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
- The string DSL is what removes the need to declare symbols up front: today we
  write `var x = Expression.symbol("x")` before building an expression, but once
  the parser lands, `parse("x + x")` will discover `x` on its own and hand back a
  ready expression. Identifiers become symbols, numeric literals become
  Decimo-backed numbers.
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

### `steps` — step-by-step traces

A feature that we want to make a signature of Symo: every rule-based engine
(`simplify`, differentiation, later integration) can show its intermediate
steps, so that a human can follow the derivation and take reference from it.
This is rare among open-source CAS libraries — SymPy has no first-class step
support (SymPy Gamma bolts it on as a separate web service), and in the Wolfram
world it is a paid feature. Since our engines are already rule-based in the
"manual" style (product rule, chain rule, identity rewrites), emitting a trace
is natural for us, while it is hard to retrofit into a library built around
fast algorithms. We should bake it in from the beginning.

**The `level` parameter.** The public API takes a parameter `level: Int` that
controls how much is shown:

- `0`: show the result only. No recording. The engine is free to take fast
  paths and to normalize aggressively.
- `1`: show the non-trivial steps and the result.
- `2`: show more steps, at the granularity a textbook would present.
- `3`: show all steps, including trivial rewrites.

**Tagging.** To make the levels work, every recorded step carries a tag that
says how important it is: `core` (the main moves of the derivation, e.g.
"apply the product rule"), `pedagogical` (smaller but still instructive moves,
e.g. "collect like terms"), and `trivial` (bookkeeping rewrites, e.g.
`x*1 -> x`, flattening). The mapping is cumulative: a `core` step is shown at
level >= 1, a `pedagogical` step at level >= 2, a `trivial` step at level >= 3.
Level 0 records nothing. The tag is assigned at the place where the rule is
applied, since only the rule itself knows how important it is.

**Data model.** Two small types, living in their own `steps` module:

- `Step`: the tag, the rule name (e.g. `"product-rule"`), the expression
  before, the expression after, and the position of the rewritten
  subexpression in the whole tree.
- `Trace`: the requested `level` plus a `List[Step]`. Its `record(...)` method
  checks the tag against the level and returns immediately when the step is
  filtered out, so the level-0 path pays almost nothing.

**Decoupling.** The design principle is that the engines record and the
printer renders; neither knows about the other's job:

- Each engine takes the trace as an explicit parameter (e.g.
  `mut trace: Trace`), and its only obligation is to call
  `trace.record(tag, rule, before, after)` at each rewrite. Passing the trace
  as a parameter keeps the coupling visible in the signature — no global
  state, and an engine that does not record simply does not take the
  parameter.
- The engines never format text. Rendering a `Trace` (plain text first, LaTeX
  later) belongs to `printer`.
- The public wrappers keep the simple signatures: `differentiate(e, "x")`
  behaves as today, and `differentiate(e, "x", level=2)` returns the result
  together with the trace.

**Interaction with the rest of the design.**

- Step traces require the intermediate forms to actually exist. This settles
  the open question below about eager normalization: `core` builders stay
  lazy, and normalization lives in `simplify` where it can be recorded. Only
  at level 0 may the engine normalize aggressively or switch to fast
  algorithms, because nobody is watching.
- For differentiation and `simplify`, the human steps and the algorithm steps
  coincide, so one implementation serves both. For integration and factoring
  (M7+) they diverge: fast algorithms (Risch-style integration, modern
  factoring) do not correspond to human steps. When we optimize those, we keep
  the rule-based traceable path alongside the fast one — the `level` parameter
  then also selects which path runs. This is the same reason SymPy keeps
  `manualintegrate` next to `risch`; we just plan for it up front.
- The trace is also our best debugging tool: when `simplify` produces a wrong
  form or a rule fails to fire, running at level 3 shows exactly which rewrite
  did it. So the feature pays off internally before any end user sees it.

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
8. `steps` — the trace types can land any time after `core`, but wiring them
   through `simplify` and `calculus` and rendering them is best done once the
   printer is solid, so it slots here.
9. `linear_algebra` — stretch goal, last.

Decimo slots in early: as the concrete number type inside `Number` nodes and as
the evaluation backend in `numeric`.

## Milestones

- **M0 (done):** repo scaffold, package layout, tasks, placeholders.
- **M1 (done):** `core.Expression` + operator overloading (`+ - * / **`, `Expression` and
  `Int` operands) + `printer.to_string`; a hand-built expression round-trips to
  text. Subtraction and division are reconstructed by the printer from the
  canonical `+ (-1)*` / `* **(-1)` forms. Covered by `tests/core/test_expression.mojo`.
- **M2 (done):** `simplify` with constant folding, the zero/one identities, and
  like-term (`x + x -> 2*x`) / like-base (`x * x -> x**2`) collection. Collection
  is structural and order-sensitive; canonical ordering is still pending.
  Covered by `tests/simplify/test_simplify.mojo`.
- **M3 (done):** `calculus.differentiation` \u2014 sum, product, power, and chain
  rules, with derivative rules for `sin`, `cos`, `exp`, `log`, `sqrt`. Results
  are passed through `simplify`. Covered by
  `tests/calculus/test_differentiation.mojo`.
- **M4:** `numeric.subs` / `evalf` against Decimo at configurable precision.
- **M5:** string DSL parser; `algebra` expand/collect.
- **M6:** `steps` — the `Step`/`Trace` types, tagging in `simplify` and
  `calculus.differentiation`, the `level` parameter on the public API, and
  plain-text rendering of a trace in `printer`.
- **M7+:** factoring, integration, limits, `linear_algebra`. Fast algorithms
  introduced here keep the rule-based traceable path alongside, selected by
  `level`.

## Open questions

- When exactly to introduce the `Rational` variant of `Number`. Leaning toward
  "once `algebra` needs exact coefficients", using Decimo's `Rational` rather
  than a home-grown `BigInt` pair. Not needed for the earlier milestones.
- What key to sort terms and factors by. This drives hashing and structural
  equality, so it needs pinning down before `simplify` gets serious.
- How much to normalize eagerly in the `core` builders versus leaving it to
  `simplify`. Too much eager work makes `core` heavy; too little makes every
  other module defensive. The `steps` design leans this toward "lazy": a step
  trace needs the intermediate forms to exist, so eager normalization is only
  acceptable when `level == 0`.
- How to make the level-0 path truly zero-cost. Passing a `Trace` and checking
  the level at runtime is cheap but not free. Mojo's compile-time parameters
  offer an alternative — e.g. `differentiate[recording: Bool]` — so the
  non-recording version compiles with no trace code at all. Worth trying once
  the runtime version works; the risk is doubling the compiled code.
- Whether three tags (`core` / `pedagogical` / `trivial`) are enough, and how
  to keep tagging consistent across engines. A written guideline with examples
  for each tag is probably needed once more rules exist, otherwise every
  contributor draws the lines differently.
