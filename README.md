# Symo

A symbolic computation library for [Mojo](https://www.modular.com/mojo), built
on top of [Decimo](https://github.com/forfudan/decimo).

> **Status:** Early scaffolding. The API is under active design and is not yet stable.

## Overview

Symo provides a symbolic ("computer algebra") layer for Mojo. Where
[Decimo](https://github.com/forfudan/decimo) delivers *exact numeric* types
(`BigInt`, `BigDecimal`), Symo delivers an *exact symbolic* type:
an immutable expression tree (`Expression`) representing
symbols, numbers, sums, products, powers, and functions.

Decimo slots in as the concrete number type inside `Number` nodes and powers
high-precision numeric evaluation, so symbolic results can be evaluated exactly
whenever numbers are involved.

The name **Symo** combines "SYMbolic" and "MOjo", following the naming pattern
of Decimo ("Decimal" + "Mojo"), showing both the purpose of the library and the
language it is built for.

I initialized the Symo project as a natural next step after Decimo,
not to reimplement the wheel that Sympy already provides in Python,
but instead to serve for an educational purpose:
(1) I want to use a language that is so similar to Python that the users can
read and understand the code easily.
(2) I want to focus on not the final result of the computation, but the
intermediate steps of it, so that students can learn how to solve problems
step by step. This pedagogical purpose is also a gift to my future children.
See the following example:

```mojo
from symo import Expression, differentiate

def main() raises:
    var x = Expression.symbol("x")
    print(
        differentiate(x**2 + 3 * x - 1, "x", detail=3)
    )  # Print all steps of the derivation.
```

This prints the following steps of the derivation:

```sh
d/dx(x**2 + 3*x - 1)
1. [pedagogical] sum-rule: d/dx(x**2 + 3*x - 1) -> d/dx(x**2) + d/dx(3*x) + d/dx(-1)
2. [core] power-rule: d/dx(x**2) -> 2*x**1*d/dx(x)
3. [trivial] variable-rule: d/dx(x) -> 1
4. [core] product-rule: d/dx(3*x) -> d/dx(3)*x + 3*d/dx(x)
5. [trivial] constant-rule: d/dx(3) -> 0
6. [trivial] variable-rule: d/dx(x) -> 1
7. [core] product-rule: d/dx(-1) -> d/dx(-1)*1 - d/dx(1)
8. [trivial] constant-rule: d/dx(-1) -> 0
9. [trivial] constant-rule: d/dx(1) -> 0
10. [trivial] power-identities: x**1 -> x
11. [pedagogical] collect-like-factors: 2*x*1 -> 2*x
12. [trivial] product-identities: 0*x -> 0
13. [pedagogical] collect-like-factors: 3*1 -> 3
14. [pedagogical] collect-like-factors: 0*1 -> 0
15. [pedagogical] collect-like-factors: -0 -> 0
16. [pedagogical] collect-like-terms: 2*x + 0 + 3 + 0 + 0 -> 2*x + 3
=> 2*x + 3
```

## Planned features

- **Expression trees** — `Symbol`, `Number` (backed by Decimo), `Add`, `Multiply`,
  `Power`, `Function`, with structural equality, hashing, and immutability.
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
- **Numeric** — `substitute` and high-precision evaluation via Decimo.
- **Printing** — infix pretty-printer, LaTeX output (later).
- **Linear algebra** (stretch) — symbolic vectors/matrices.

## Project structure

```txt
symo/
├── src/
│   └── symo/                 # Core library (Mojo package)
│       ├── core/             #   Expression tree (Expression, Symbol, Number, ...)
│       ├── parser/           #   Operator overloading + string DSL → Expression
│       ├── simplify/         #   Constant folding, canonicalization, identities
│       ├── algebra/          #   Polynomials, rationals, equation solving
│       ├── calculus/         #   Differentiation, integration, limits
│       ├── functions/        #   Elementary functions as Expression nodes
│       ├── numeric/          #   Substitution + numeric evaluation (Decimo)
│       ├── printer/          #   Infix / LaTeX printing
│       └── linear_algebra/           #   Symbolic vectors/matrices (stretch goal)
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
