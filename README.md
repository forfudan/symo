# Symo

A symbolic computation library for [Mojo](https://www.modular.com/mojo), built
on top of [Decimo](https://github.com/forfudan/decimo).

> **Status:** Early scaffolding. The API is under active design and is not yet
> usable. See [docs/plans/development.md](docs/plans/development.md) for the
> roadmap.

## Overview

Symo provides a symbolic ("computer algebra") layer for Mojo. Where Decimo
delivers *exact numeric* types (`BigInt`, `BigDecimal`), Symo delivers an
*exact symbolic* type: an immutable expression tree (`Expr`) representing
symbols, numbers, sums, products, powers, and functions.

Decimo slots in as the concrete number type inside `Number` nodes and powers
high-precision numeric evaluation, so symbolic results can be evaluated exactly
whenever numbers are involved.

The name **Symo** combines "SYMbolic" and "mOjo", following the naming pattern
of Decimo ("Decimal" + "Mojo").

## Planned features

- **Expression trees** — `Symbol`, `Number` (backed by Decimo), `Add`, `Mul`,
  `Pow`, `Function`, with structural equality, hashing, and immutability.
  `Number` starts on Decimo's `BigInt`/`BigDecimal`; exact fractions arrive
  later via Decimo's `Rational`.
- **Construction** — operator overloading (`+ - * / **`) and an optional
  string DSL (`"x**2 + 3*x - 1"`).
- **Simplification** — constant folding, like-term collection, canonical
  ordering, identity rules.
- **Algebra** — polynomial expand/collect/factor, rational simplification,
  equation solving.
- **Calculus** — differentiation, basic integration, limit stubs.
- **Elementary functions** — `sin`, `cos`, `exp`, `log`, `sqrt`, ...
- **Numeric** — `subs` and high-precision evaluation via Decimo.
- **Printing** — infix pretty-printer, LaTeX output (later).
- **Linear algebra** (stretch) — symbolic vectors/matrices.

## Project structure

```txt
symo/
├── src/
│   └── symo/                 # Core library (Mojo package)
│       ├── core/             #   Expression tree (Expr, Symbol, Number, ...)
│       ├── parser/           #   Operator overloading + string DSL → Expr
│       ├── simplify/         #   Constant folding, canonicalization, identities
│       ├── algebra/          #   Polynomials, rationals, equation solving
│       ├── calculus/         #   Differentiation, integration, limits
│       ├── functions/        #   Elementary functions as Expr nodes
│       ├── numeric/          #   Substitution + numeric evaluation (Decimo)
│       ├── printer/          #   Infix / LaTeX printing
│       └── linalg/           #   Symbolic vectors/matrices (stretch goal)
├── examples/                 # Runnable usage examples
├── tests/                    # Unit tests (one subfolder per module)
├── docs/                     # Documentation and design notes
│   └── plans/                #   Development plans
└── pixi.toml                 # Project configuration and tasks
```

## Getting started

Symo uses [pixi](https://prefix.dev/) for environment and task management.

```bash
pixi install          # set up the environment (installs Mojo + Decimo)
pixi run test         # run the test suite
pixi run package      # format, precompile the package, and check docs
pixi run ex examples/hello.mojo   # run an example
```

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) and
[NOTICE](NOTICE). Symo depends on Decimo, which is also Apache-2.0 licensed.
