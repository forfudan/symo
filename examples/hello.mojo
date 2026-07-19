"""A first taste of Symo's expression tree.

Run with:

    pixi run ex examples/hello.mojo

Builds a few expressions with ordinary Mojo operators and prints them. Later
milestones will add simplification, differentiation, and numeric evaluation.
"""

from symo.prelude import *


def main() raises:
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")

    print(x**2 + 3 * x - 1)  # x**2 + 3*x - 1
    print((x + y) ** 2)  # (x + y)**2
    print(x / (x + 1))  # x/(x + 1)
    print(x - y - 1)  # x - y - 1
