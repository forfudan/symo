# Symo development plan

Status: scaffolding. This document sketches the architecture, module
responsibilities, and build order for Symo — a symbolic computation library for
Mojo built on top of [Decimo](https://github.com/forfudan/decimo).

## Guiding idea

Decimo already gives us arbitrary-precision integers and decimals. Symo sits on
top as the *symbolic* layer: an immutable expression tree (`Expression`) whose
`Number` leaves hold Decimo values. Anything that needs an exact number —
constant folding, `evaluate`, evaluating an elementary function — hands the work
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

## Naming convention

Public functions and types carry the **full descriptive name**, in snake_case
for functions: `substitute` and `evaluate`, not `subs` and `evalf`. The same
rule applies to everything added later (`integrate`, not `integ`;
`differentiate`, not `diff`).

**One name per operation.** We do not ship short aliases alongside the full
names, following the Zen of Python: "There should be one — and preferably only
one — obvious way to do it." Two spellings for one function split the
documentation, the examples, and the users' habits for no gain.

Terse names inherited from other systems are also often wrong for us. Maple's
`evalf` means "evaluate in **f**loating-point", one of a family (`evalb`,
`evalc`, `evalm`, `evalhf`) where the suffix picked the evaluation domain.
SymPy borrowed only `evalf`, so the `f` no longer contrasts with anything —
and for Symo it would be actively misleading, since `evaluate` returns an
exact Decimo `BigDecimal` with no binary floating point involved.

A short alias is only worth considering for a name typed constantly in
interactive use (as Decimo does with `BDec` for `BigDecimal`), and even then
the full name stays canonical in signatures, documentation, and tests.

The same rule applies to **parameter names**: the expression argument is
called `expression`, not `e`. In a computer-algebra library `e` is especially
bad, since it also reads as Euler's number (and as a caught `Error`). Single
letters stay reserved for genuine mathematical conventions where they aid
reading — loop indices `i`/`j`, and `x`/`y` for symbols in tests and examples.

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

- `substitute`: replace symbols with expressions or Decimo `BigDecimal` values.
- `evaluate`: high-precision numeric evaluation of any expression tree via
  Decimo.

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

**The `detail` parameter.** The public API takes a parameter `detail: Int`
that controls how much is shown ("detail" rather than "level", since it names
what the number is about):

- `0`: show the result only. No recording. The engine is free to take fast
  paths and to normalize aggressively.
- `1`: show the non-trivial steps and the result.
- `2`: show more steps, at the granularity a textbook would present.
- `3`: show all steps, including trivial rewrites.

**Tagging.** To make the detail values work, every recorded step carries a tag that
says how important it is: `core` (the main moves of the derivation, e.g.
"apply the product rule"), `pedagogical` (smaller but still instructive moves,
e.g. "collect like terms"), and `trivial` (bookkeeping rewrites, e.g.
`x*1 -> x`, flattening). The mapping is cumulative: a `core` step is shown at
detail >= 1, a `pedagogical` step at detail >= 2, a `trivial` step at
detail >= 3. Detail 0 records nothing. The tag is assigned at the place where
the rule is applied, since only the rule itself knows how important it is.
Tagging will be a enum in the future when Mojo support enums. For now,
it can be a struct of an `UInt8` field that mimics an enum.

**Data model.** Two small types, living in their own `steps` module:

- `Step`: the tag, the rule name (e.g. `"product-rule"`), the expression
  before, and the expression after. A position (path) of the rewritten
  subexpression in the whole tree is deferred: the `before` expression itself
  identifies the rewritten subexpression well enough for text rendering, and
  threading a path through every engine can wait until a renderer needs it.
- `Trace`: the requested `detail` plus a `List[Step]`. Its `record(...)`
  method checks the tag against the detail and returns immediately when the
  step is filtered out, so the detail-0 path pays almost nothing. Note that a
  `Trace` is deliberately not just a `List[Expression]`: a bare sequence of
  intermediate forms shows *what* the forms were but not *why* each follows
  from the previous one. The rule name is the pedagogical content, and the
  tag is what makes filtering by detail possible.

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
- The public API is a pair of overloads with different return types.
  `differentiate(e, "x")` behaves as today and returns a plain `Expression`,
  which matches SymPy's model. `differentiate(e, "x", detail=n)` resolves to
  the second overload and returns a `Derivation`, a small wrapper holding the
  answer and the trace:

  ```mojo
  struct Derivation:
      var input: Expression   # the problem statement, e.g. d/dx(x**2)
      var result: Expression  # the answer
      var trace: Trace        # the recorded steps
  ```

  The `input` field stores the expression the computation started from
  (differentiation stores the marker form `d/dvar(e)`), so that `print(d)`
  opens with the problem, then the steps, then the result — a complete worked
  exercise. Note that it is the `Expression` itself, not its source text, so
  rendering is always canonical.

  The two overloads differ in arity (`detail` has no default value, otherwise
  the two-argument call would be ambiguous), so resolution is unambiguous and
  fully type safe; the user sees from the signature and the LSP which one they
  get. `print(d.result)` prints the expression per se; `print(d.trace)`
  renders the steps down to and including the final result.

**Decision: the trace does not live on `Expression`.** It is tempting to add
`steps` and `detail` fields to `Expression` itself, so that `differentiate`
could keep a single return type. We considered and rejected this. `Expression`
is the recursive tree node, so every node in every tree would carry the fields
while only the root of a traced computation ever uses them — and the cost is
recursive, since the `before`/`after` expressions inside a step are themselves
`Expression`s carrying their own dead fields. Worse, the fields would poison
structural equality and hashing: two structurally identical expressions with
different traces must still compare equal, so every builder and every engine
would have to decide how to propagate the fields on each construction and
copy. SymPy faced the same choice and also keeps `Expr` free of step data.
The `Derivation` wrapper gives the same ergonomics without touching `core`.

**Interaction with the rest of the design.**

- Step traces require the intermediate forms to actually exist. This settles
  the open question below about eager normalization: `core` builders stay
  lazy, and normalization lives in `simplify` where it can be recorded. Only
  at detail 0 may the engine normalize aggressively or switch to fast
  algorithms, because nobody is watching.
- For differentiation and `simplify`, the human steps and the algorithm steps
  coincide, so one implementation serves both. For integration and factoring
  (M7+) they diverge: fast algorithms (Risch-style integration, modern
  factoring) do not correspond to human steps. When we optimize those, we keep
  the rule-based traceable path alongside the fast one — the `detail`
  parameter then also selects which path runs. This is the same reason SymPy keeps
  `manualintegrate` next to `risch`; we just plan for it up front.
- The trace is also our best debugging tool: when `simplify` produces a wrong
  form or a rule fails to fire, running at detail 3 shows exactly which
  rewrite did it. So the feature pays off internally before any end user sees it.

### `linear_algebra` (stretch goal)

- Symbolic vectors/matrices whose elements are `Expression`.

## Build order

1. `core` — the foundation everything depends on.
2. `printer` — built early so progress can be inspected visually.
3. `simplify` — needed before algebra/calculus produce readable results.
4. `functions` and `algebra` — can proceed in parallel once simplify exists.
5. `calculus` — depends on `core`, `simplify`, and `functions`.
6. `steps` — moved up from a late slot: the recording plumbing goes in while
   `simplify` and `calculus` are still small, since the retrofitting cost only
   grows as rules accumulate. Every rule written after this point records its
   step from birth. Fancy rendering (LaTeX) can trail behind.
7. `numeric` — substitution + Decimo-backed evaluation, ties symbolic to exact.
8. `parser` string DSL — convenience layer once the tree API is stable.
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
- **M4 (done):** `steps` — the `StepTag`/`Step`/`Trace`/`Derivation` types,
  tagging in `simplify` and `calculus.differentiation`, the `detail` overloads
  on the public API, and plain-text rendering (the types render themselves via
  `Writable`, mirroring how `Expression` prints; `printer.to_string` has
  matching overloads). Differentiation records steps top-down like a textbook,
  using an inert `d/dvar(...)` function node for a derivative that a later
  step resolves; `simplify` records bottom-up, since a rewrite is only known
  once computed. Covered by `tests/steps/test_steps.mojo`.
- **M5 (done):** `numeric.substitute` / `evaluate` against Decimo at
  configurable precision. `substitute` is purely structural (no simplification);
  `evaluate` collapses a symbol-free tree to a `BigDecimal`, dispatching
  `sin`/`cos`/`exp`/`log` (natural)/`sqrt` to Decimo at a requested precision
  and raising on a surviving free symbol. Covered by
  `tests/numeric/test_numeric.mojo`.
- **M6:** string DSL parser; `algebra` expand/collect, with rules tagged as
  they are written.
- **M7+:** factoring, integration, limits, `linear_algebra`. Fast algorithms
  introduced here keep the rule-based traceable path alongside, selected by
  `detail`.

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
  acceptable when `detail == 0`.
- How to make the detail-0 path truly zero-cost. Passing a `Trace` and
  checking the detail at runtime is cheap but not free. Mojo's compile-time
  parameters
  offer an alternative — e.g. `differentiate[recording: Bool]` — so the
  non-recording version compiles with no trace code at all. Worth trying once
  the runtime version works; the risk is doubling the compiled code.
- Whether three tags (`core` / `pedagogical` / `trivial`) are enough, and how
  to keep tagging consistent across engines. A written guideline with examples
  for each tag is probably needed once more rules exist, otherwise every
  contributor draws the lines differently.
