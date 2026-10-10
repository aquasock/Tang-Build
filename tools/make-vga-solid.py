#!/usr/bin/env python3
"""Override the desktop RGB registers in an already routed nextpnr netlist.

Only LUT INIT values change: every connection, BEL and routed wire is preserved.
The fifteen RGB input LUTs become constants and their shared synchronous clear
is disabled. Raster timing, VGA blanking, socket control and UART are untouched.
This is a temporary diagnostic, not a replacement desktop image.

    tools/make-vga-solid.py routed.json white.json --rgb ffffff

SPDX-License-Identifier: MIT
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path


def override(doc, rgb):
    result = copy.deepcopy(doc)
    modules = result["modules"]
    if len(modules) != 1:
        raise ValueError("expected one flattened module")
    module = next(iter(modules.values()))
    cells = module["cells"]
    drivers, users = {}, {}
    for name, cell in cells.items():
        for pin, bits in cell["connections"].items():
            for bit in bits:
                if cell["port_directions"][pin] == "output":
                    if bit in drivers:
                        raise ValueError(f"multiple drivers on net bit {bit}")
                    drivers[bit] = (name, pin)
                else:
                    users.setdefault(bit, set()).add((name, pin))

    changes, resets, registers = [], set(), set()

    def constant_lut(name, value):
        cell = cells[name]
        if not cell["type"].startswith("LUT") or "INIT" not in cell["parameters"]:
            raise ValueError(f"{name}: expected a LUT with INIT")
        old = cell["parameters"]["INIT"]
        width = 1 << int(cell["type"][3:])
        if len(old) < width or set(old) - {"0", "1"}:
            raise ValueError(f"{name}: unsupported INIT encoding")
        # nextpnr writes some LUT4 values as 32 bits; keep unused high bits zero.
        new = "0" * (len(old) - width) + str(value) * width
        cell["parameters"]["INIT"] = new
        changes.append({"cell": name, "bel": cell["attributes"]["NEXTPNR_BEL"],
                        "old_init": old, "new_init": new})

    for index in range(24):
        # BGR5 is widened to RGB8 with three zero low bits per channel.
        if index % 8 < 3:
            continue
        net = module["netnames"][f"desktop_rgb[{index}]"]
        if len(net["bits"]) != 1:
            raise ValueError("expected scalar RGB aliases")
        register, pin = drivers[net["bits"][0]]
        ff = cells[register]
        if pin != "Q" or ff["type"] != "DFFRE":
            raise ValueError(f"RGB bit {index}: expected a DFFRE Q")
        registers.add(register)
        resets.add(ff["connections"]["RESET"][0])
        data = ff["connections"]["D"][0]
        lut, pin = drivers[data]
        if pin != "F" or users[data] != {(register, "D")}:
            raise ValueError(f"RGB bit {index}: input LUT is shared or unexpected")
        constant_lut(lut, (rgb >> index) & 1)

    if len(registers) != 15 or len(resets) != 1:
        raise ValueError("expected fifteen RGB registers with one shared clear")
    reset = resets.pop()
    if users[reset] != {(name, "RESET") for name in registers}:
        raise ValueError("RGB clear also drives other logic; refusing override")
    lut, pin = drivers[reset]
    if pin != "F":
        raise ValueError("RGB clear is not LUT driven")
    constant_lut(lut, 0)

    # Prove that only the sixteen intended INIT properties changed.
    restored = copy.deepcopy(result)
    restored_cells = next(iter(restored["modules"].values()))["cells"]
    for change in changes:
        restored_cells[change["cell"]]["parameters"]["INIT"] = change["old_init"]
    if restored != doc or len(changes) != 16:
        raise ValueError("override altered more than the sixteen LUT INIT values")
    return result, changes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--rgb", default="ffffff", help="six hexadecimal RGB digits")
    args = parser.parse_args()
    if len(args.rgb) != 6:
        parser.error("--rgb must have six hexadecimal digits")
    try:
        rgb = int(args.rgb, 16)
        if not 0 <= rgb <= 0xFFFFFF:
            raise ValueError("RGB out of range")
        raw = args.input.read_bytes()
        result, changes = override(json.loads(raw), rgb)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        manifest = {"source_sha256": hashlib.sha256(raw).hexdigest(),
                    "output_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
                    "rgb": args.rgb.lower(), "changes": changes,
                    "placement_and_routing_unchanged": True}
        args.output.with_suffix(".manifest.json").write_text(
            json.dumps(manifest, indent=2) + "\n")
        print(f"{args.output}: RGB {args.rgb}, 16 LUT INIT overrides; routing unchanged")
    except (ValueError, KeyError, OSError) as exc:
        parser.exit(1, f"refusing diagnostic: {exc}\n")


if __name__ == "__main__":
    main()
