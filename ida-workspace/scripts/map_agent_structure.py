#!/usr/bin/env python3
"""
IDA Pro script: Map agent loop and tool dispatch patterns.
Run via: File → Script File → map_agent_structure.py
"""

import idautils
import idc
import idaapi


def find_rust_functions(keyword):
    """Find Rust functions by mangled name pattern."""
    results = []
    for func_ea in idautils.Functions():
        name = idc.get_func_name(func_ea)
        if keyword.lower() in name.lower():
            results.append((func_ea, name))
    return results


def find_panicking_functions():
    """Find panic handlers — useful for understanding error paths."""
    return find_rust_functions("panic")


def find_tool_names():
    """Search for tool names that might appear in dispatch logic."""
    tool_names = ["bash", "shell", "file", "grep", "glob", "edit", "write",
                   "patch", "read", "view", "ls", "fetch", "search"]
    found = {}
    for tool in tool_names:
        refs = []
        for seg_ea in idautils.Segments():
            seg_name = idc.get_segm_name(seg_ea)
            if "__cstring" not in seg_name:
                continue
            ea = idc.get_segm_start(seg_ea)
            end = idc.get_segm_end(seg_ea)
            while ea < end:
                s = idc.get_strlit_contents(ea)
                if s:
                    decoded = s.decode("utf-8", errors="ignore")
                    if decoded.strip() == tool:
                        for xref in idautils.XrefsTo(ea):
                            refs.append(xref.frm)
                ea = idc.next_head(ea, end)
        if refs:
            found[tool] = refs
    return found


def main():
    print("=" * 60)
    print("Codex Binary — Agent Structure Mapper")
    print("=" * 60)

    # Find tool dispatch
    print("\n[Tool Name References]")
    tool_refs = find_tool_names()
    for tool, addrs in tool_refs.items():
        print(f"  '{tool}': {len(addrs)} references")
        for addr in addrs[:3]:
            print(f"    0x{addr:x}")

    # Find panic handlers
    print("\n[Panic Handlers]")
    panics = find_panicking_functions()
    for ea, name in panics[:5]:
        print(f"  0x{ea:x}: {name[:80]}")

    # Find main entry point
    print("\n[Entry Points]")
    for func_ea in idautils.Functions():
        name = idc.get_func_name(func_ea)
        if "main" in name.lower() and "tls" not in name.lower():
            print(f"  0x{func_ea:x}: {name}")

    print("\n" + "=" * 60)
    print("Done.")


if __name__ == "__main__":
    main()
