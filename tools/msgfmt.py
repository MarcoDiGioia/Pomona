#!/usr/bin/python3 -I
"""msgfmt.py - compile a gettext .po file into a .mo file.

A small stand-in for GNU msgfmt, so building Pomona needs only Python.
Supports what Pomona's catalogs use: msgid/msgstr with continuation lines,
the usual C escapes, and the header entry. No plurals, no contexts.

    python3 tools/msgfmt.py INPUT.po OUTPUT.mo

SPDX-License-Identifier: GPL-3.0-or-later
"""
import ast
import struct
import sys


def unquote(token):
    # .po strings use C escapes, which a Python string literal reads the same way
    return ast.literal_eval(token)


def parse(text):
    """{msgid: msgstr} from .po text; entries with an empty msgstr are skipped."""
    catalog, msgid, msgstr, field = {}, None, None, None

    def flush():
        if msgid is not None and msgstr:
            catalog[msgid] = msgstr

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("msgid "):
            flush()
            msgid, msgstr, field = unquote(line[6:]), None, "id"
        elif line.startswith("msgstr "):
            msgstr, field = unquote(line[7:]), "str"
        elif line.startswith('"'):
            if field == "id":
                msgid += unquote(line)
            elif field == "str":
                msgstr += unquote(line)
            else:
                raise ValueError("continuation line outside an entry: %r" % raw)
        else:
            raise ValueError("unsupported line: %r" % raw)
    flush()
    return catalog


def build_mo(catalog):
    """GNU .mo bytes (little-endian, revision 0) for a {msgid: msgstr} catalog."""
    keys = sorted(catalog)
    ids = [k.encode("utf-8") for k in keys]
    strs = [catalog[k].encode("utf-8") for k in keys]
    n = len(keys)
    header_size = 7 * 4
    ids_table = header_size
    strs_table = ids_table + n * 8
    data_start = strs_table + n * 8
    data = b""
    id_entries, str_entries = [], []
    for blob in ids:
        id_entries.append((len(blob), data_start + len(data)))
        data += blob + b"\0"
    for blob in strs:
        str_entries.append((len(blob), data_start + len(data)))
        data += blob + b"\0"
    out = struct.pack("<7I", 0x950412DE, 0, n, ids_table, strs_table, 0, 0)
    out += b"".join(struct.pack("<2I", *e) for e in id_entries)
    out += b"".join(struct.pack("<2I", *e) for e in str_entries)
    return out + data


def main(argv):
    if len(argv) != 3:
        sys.exit("usage: msgfmt.py INPUT.po OUTPUT.mo")
    with open(argv[1], encoding="utf-8") as f:
        catalog = parse(f.read())
    with open(argv[2], "wb") as f:
        f.write(build_mo(catalog))


if __name__ == "__main__":
    main(sys.argv)
