"""A first taste of Symo's expression tree.

Run with:

    pixi run ex examples/hello.mojo

Builds a few expressions with ordinary Mojo operators and prints them. Later
milestones will add simplification, differentiation, and numeric evaluation.
"""

from symo import Expression, differentiate, simplify


def main() raises:
    var x = Expression.symbol("x")
    var y = Expression.symbol("y")

    print(x**2 + 3 * x - 1)  # x**2 + 3*x - 1
    print((x + y) ** 2)  # (x + y)**2
    print(x / (x + 1))  # x/(x + 1)
    print(x - y - 1)  # x - y - 1

    # Simplification: constant folding, identities, and collection.
    print(simplify(x + x))  # 2*x
    print(simplify(x**2 * x**3))  # x**5
    print(simplify(2 * x + 3 * x + 1))  # 5*x + 1

    # Differentiation (result is simplified).
    print(differentiate(x**3 + 3 * x - 1, "x"))  # 3*x**2 + 3
    print(differentiate(x * y, "x"))  # y

    print(
        differentiate(x**2 + 3 * x - 1, "x", detail=3)
    )  # Print all steps of the derivation.
