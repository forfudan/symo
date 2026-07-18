"""Placeholder test for the core module.

Replace with real tests once `symo.core.Expr` is implemented.
"""


def test_placeholder() raises:
    # Sanity check so the test runner has something to execute.
    assert_true = 1 + 1 == 2
    if not assert_true:
        raise Error("arithmetic is broken")


def main() raises:
    test_placeholder()
    print("core: placeholder test passed")
