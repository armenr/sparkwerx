#!/usr/bin/env python3
"""Correct GB10 unified-memory accounting in the pinned upstream collector."""

import ast
import sys
from pathlib import Path

OLD = "        is_unified_memory = False\n"
NEW = """        for gpu in status.gpu_devices or []:
            if gpu.name == "NVIDIA GB10" and status.memory and status.memory.total:
                gpu.memory.is_unified_memory = True
                gpu.memory.total = status.memory.total
        is_unified_memory = False
"""


def patched(source):
    if source.count(OLD) != 1:
        raise ValueError("Upstream collector changed; review the GB10 adapter")
    result = source.replace(OLD, NEW)
    ast.parse(result)
    return result


if __name__ == "__main__":
    Path(sys.argv[2]).write_text(patched(Path(sys.argv[1]).read_text()))
