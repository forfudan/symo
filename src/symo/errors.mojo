# ===----------------------------------------------------------------------=== #
#
# Copyright 2026 Yuhao Zhu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# ===----------------------------------------------------------------------=== #

"""Typed errors for Symo, built on Decimo's error machinery.

Decimo already provides `DecimoError`, a `Writable` error type that captures
the source file and line at the raise site (via `call_location`) and renders a
Python-style traceback. Rather than reimplement that, Symo reuses it and
declares its own error types as parametrizations of `DecimoError`. The
`error_type` parameter is the label shown in the rendered traceback, so a
`ParseError` prints as `ParseError: ...` with no trace of the underlying
Decimo type.

Every error carries a `function=` argument naming the raising function, since
Mojo cannot yet introspect the current function name at runtime. Raise them
with keyword arguments:

```mojo
raise ParseError(
    message="unexpected ')' at position 4",
    function="parse()",
)
```

The general-purpose Decimo error types (`ValueError`, `IndexError`, ...) are
re-exported here so that the rest of Symo imports every error from a single
module.
"""

from decimo.errors import (
    ConversionError,
    DecimoError,
    IndexError,
    KeyError,
    OverflowError,
    RuntimeError,
    ValueError,
    ZeroDivisionError,
)

comptime ParseError = DecimoError[error_type="ParseError"]
"""Raised when the string-DSL parser cannot make sense of its input: an
unexpected character, an unknown token, unbalanced parentheses, or a
malformed expression. The message carries the 0-based column position."""
