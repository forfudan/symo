"""Core simplification passes.

Planned rules:

- constant folding, using Decimo arithmetic for exactness
- flattening nested `Add`/`Mul`
- like-term collection and canonical term ordering
- basic identities: `x*1 -> x`, `x+0 -> x`, `x**0 -> 1`, `x**1 -> x`, ...

TODO: implement. This is a placeholder.
"""
