from __future__ import annotations

import sys
from pathlib import Path

try:
    from lupa.lua54 import LuaRuntime
except ImportError:
    raise SystemExit(
        "Lua test runtime missing. Install it with: "
        "python -m pip install -r requirements-test.txt"
    )


RESOURCE_ROOT = Path(__file__).resolve().parent.parent
TEST_ROOT = RESOURCE_ROOT / "tests"


def main() -> int:
    specs = sorted(TEST_ROOT.glob("*_spec.lua"))
    if not specs:
        print("No Lua specs found.", file=sys.stderr)
        return 1

    for spec in specs:
        runtime = LuaRuntime(unpack_returned_tuples=True)
        try:
            runtime.globals().dofile(spec.as_posix())
        except Exception as exc:
            print(f"FAILED: {spec.relative_to(RESOURCE_ROOT)}", file=sys.stderr)
            print(exc, file=sys.stderr)
            return 1

    print(f"Passed {len(specs)} Lua specs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
