"""Symo: a symbolic computation library for Mojo, built on top of Decimo.

Symo provides an immutable symbolic expression tree (`Expression`) and the algorithms
that operate on it: construction, simplification, algebra, calculus, elementary
functions, numeric evaluation, and printing.

The concrete number type inside `Number` nodes is backed by Decimo's
arbitrary-precision types, so numeric evaluation is exact by default.

This is an early scaffold; the public API is not yet stable.
"""

from symo.core import Expression, ExpressionKind
from symo.printer import to_string
from symo.simplify import simplify
from symo.calculus import differentiate
