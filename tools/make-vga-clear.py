#!/usr/bin/env python3
"""Disable only the desktop RGB synchronous clear in a routed netlist.

One LUT INIT becomes zero. Original pixel data, registers, clocks, VGA blanking,
socket control, connections, placement and routing remain intact. This is a
temporary diagnostic, not a replacement desktop image.

    tools/make-vga-clear.py routed.json clear-disabled.json

SPDX-License-Identifier: MIT
"""

import argparse
import copy
import hashlib
import json
from pathlib import Path


def override(doc):
    result = copy.deepcopy(doc)
    if len(result["modules"]) != 1:
        raise ValueError("expected one flattened routed module")
    module = next(iter(result["modules"].values()))
    cells = module["cells"]
    drivers, users = {}, {}
    for name, cell in cells.items():
        for pin, bits in cell["connections"].items():
            for bit in bits:
                if cell["port_directions"][pin] == "output":
                    if bit in drivers:
                        raise ValueError(f"multiple drivers on bit {bit}")
                    drivers[bit] = (name, pin)
                else:
                    users.setdefault(bit, set()).add((name, pin))

    registers, resets, clocks = set(), set(), set()
    for index in range(24):
        if index % 8 < 3:
            continue
        bits = module["netnames"][f"desktop_rgb[{index}]"]["bits"]
        if len(bits) != 1:
            raise ValueError("expected scalar RGB aliases")
        name, pin = drivers[bits[0]]
        ff = cells[name]
        if pin != "Q" or ff["type"] != "DFFRE":
            raise ValueError(f"RGB bit {index}: expected synchronous-clear DFFRE")
        registers.add(name)
        resets.add(ff["connections"]["RESET"][0])
        clocks.add(ff["connections"]["CLK"][0])
    if len(registers) != 15 or len(resets) != 1 or len(clocks) != 1:
        raise ValueError("expected fifteen RGB registers sharing clear and clock")
    reset = resets.pop()
    if users[reset] != {(name, "RESET") for name in registers}:
        raise ValueError("RGB clear also drives unrelated logic")
    name, pin = drivers[reset]
    lut = cells[name]
    if pin != "F" or lut["type"] != "LUT2":
        raise ValueError("expected LUT2-driven shared RGB clear")
    old = lut["parameters"]["INIT"]
    if len(old) < 4 or set(old) - {"0", "1"} or int(old, 2) != 7:
        raise ValueError("expected original NAND clear INIT 0111")
    new = "0" * len(old)
    lut["parameters"]["INIT"] = new

    restored = copy.deepcopy(result)
    next(iter(restored["modules"].values()))["cells"][name]["parameters"]["INIT"] = old
    if restored != doc:
        raise ValueError("more than the shared clear LUT INIT changed")
    change = {"cell": name, "bel": lut["attributes"]["NEXTPNR_BEL"],
              "old_init": old, "new_init": new}
    return result, [change]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        raw = args.input.read_bytes()
        result, changes = override(json.loads(raw))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
        manifest = {"source_sha256": hashlib.sha256(raw).hexdigest(),
                    "output_sha256": hashlib.sha256(args.output.read_bytes()).hexdigest(),
                    "changes": changes, "placement_and_routing_unchanged": True,
                    "pixel_data_unchanged": True}
        args.output.with_suffix(".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"{args.output}: 1 clear INIT override; pixel data and routing unchanged")
    except (ValueError, KeyError, OSError) as exc:
        parser.exit(1, f"refusing diagnostic: {exc}\n")


if __name__ == "__main__":
    main()
