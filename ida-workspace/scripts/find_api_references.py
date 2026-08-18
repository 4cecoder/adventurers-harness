#!/usr/bin/env python3
"""
IDA Pro script: Find OpenAI API endpoint references in Codex binary.
Run via: File → Script File → find_api_references.py
"""

import idautils
import idc
import ida_search
import ida_name


def find_string_refs(search_str):
    """Find all xrefs to strings containing the search term."""
    refs = []
    for seg_ea in idautils.Segments():
        seg_name = idc.get_segm_name(seg_ea)
        if "__cstring" not in seg_name and "__cfstring" not in seg_name:
            continue
        ea = idc.get_segm_start(seg_ea)
        end = idc.get_segm_end(seg_ea)
        while ea < end:
            s = idc.get_strlit_contents(ea)
            if s:
                decoded = s.decode("utf-8", errors="ignore")
                if search_str.lower() in decoded.lower():
                    # Find xrefs to this string
                    for xref in idautils.XrefsTo(ea):
                        refs.append((xref.frm, decoded))
            ea = idc.next_head(ea, end)
    return refs


def find_function_containing(ea):
    """Get function name containing an address."""
    func = idaapi.get_func(ea)
    if func:
        return idc.get_func_name(func.start_ea)
    return "unknown"


def main():
    print("=" * 60)
    print("Codex Binary — API Reference Finder")
    print("=" * 60)

    search_terms = [
        "api.openai.com",
        "chatgpt.com",
        "/v1/responses",
        "/v1/chat/completions",
        "Authorization",
        "Bearer",
        "Content-Type",
        "application/json",
    ]

    for term in search_terms:
        refs = find_string_refs(term)
        if refs:
            print(f"\n[{term}] — {len(refs)} references:")
            for ea, s in refs[:10]:
                func = find_function_containing(ea)
                print(f"  0x{ea:x} in {func}: {s[:80]}")

    print("\n" + "=" * 60)
    print("Done. Use IDA's cross-references (X) to navigate.")


if __name__ == "__main__":
    main()
