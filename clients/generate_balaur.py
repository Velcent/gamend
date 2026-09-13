#!/usr/bin/env python3
"""Write the Balaur SDK from the OpenAPI document and the realtime table.

The Godot client goes through openapi-generator, which has no Rune target;
adding one is a Java generator plus a template set, and the ninety lines of
`perl -i` that repair the GDScript output say what a near-fit generator
costs. This is that generator for Rune, in one script with no Docker.

It writes three files. `api.rn` is one function per operation, named as
`GamendApi.gd` names it so a game ported from Godot calls the same thing.
`events.rn` is one constant per realtime signal and a decoder, from
`clients/events.json`. `README.md` is the reference, by tag. Everything
else in the addon is the hand-written `clients/balaur_template/`, copied
over the top the way `gamend_template` is for Godot.
"""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SPEC = HERE / "godot" / "openapi.json"
EVENTS = HERE / "events.json"
NAMES = HERE / "balaur_names.json"
TEMPLATE = HERE / "balaur_template"
OUT = ROOT / "balaur_addons" / "addons" / "gamend"

BANNER = (
    "// Written by clients/generate_balaur.py from the OpenAPI document.\n"
    "// Do not edit; edit the generator or the spec and run\n"
    "// clients/generate_balaur.sh.\n"
)

METHODS = ("get", "post", "put", "patch", "delete")

# Rune's keywords, which a path parameter or a body field could otherwise
# collide with when it becomes an argument name.
RESERVED = {
    "as", "async", "await", "break", "const", "continue", "crate", "default",
    "else", "enum", "false", "fn", "for", "if", "impl", "in", "is", "let",
    "loop", "match", "mod", "move", "mut", "not", "pub", "return", "select",
    "self", "static", "struct", "super", "true", "typeof", "use", "while",
    "yield",
}


def snake(text: str) -> str:
    """A tag as the prefix its functions carry: `Admin – KV` is `admin_kv`."""
    return re.sub(r"[^a-z0-9]+", "_", text.lower()).strip("_")


def safe(name: str) -> str:
    return f"{name}_" if name in RESERVED else name


def operations(spec: dict) -> list[dict]:
    """Every operation, with what a call needs to make it."""
    out = []
    for path, item in spec["paths"].items():
        for method, op in item.items():
            if method not in METHODS:
                continue
            params = op.get("parameters", [])
            body = {}
            for kind, content in op.get("requestBody", {}).get("content", {}).items():
                body = {"type": kind, "schema": content.get("schema", {})}
                break
            out.append(
                {
                    "id": op["operationId"],
                    "tag": op.get("tags", ["Other"])[0],
                    "method": method.upper(),
                    "path": path,
                    "summary": op.get("summary", "").strip(),
                    "path_params": [p["name"] for p in params if p.get("in") == "path"],
                    "query": [
                        (p["name"], bool(p.get("required")))
                        for p in params
                        if p.get("in") == "query"
                    ],
                    "body": body,
                }
            )
    out.sort(key=lambda o: (snake(o["tag"]), o["id"]))
    return out


def function_name(op: dict, aliases: dict[str, str]) -> str:
    """`<tag>_<operationId>`, unless the Godot façade chose another name."""
    return aliases.get(op["id"], f"{snake(op['tag'])}_{op['id']}")


def path_expression(op: dict, with_query: bool) -> str:
    """The path as a Rune string.

    A path with no holes and no query is a plain literal; anything else is a
    template, because the parameters and the query are interpolated into it.
    """
    filled = re.sub(r"\{([^}]+)\}", lambda m: "${" + safe(m.group(1)) + "}", op["path"])
    if not op["path_params"] and not with_query:
        return json.dumps(op["path"])
    tail = "${query}" if with_query else ""
    return f"`{filled}{tail}`"


def wrap(text: str, width: int, prefix: str) -> list[str]:
    """`text` as comment lines, so a long summary does not run off the page."""
    words, lines, line = text.split(), [], prefix
    for word in words:
        candidate = f"{line} {word}" if line != prefix else f"{prefix} {word}"
        if len(candidate) > width and line != prefix:
            lines.append(line)
            line = f"{prefix} {word}"
        else:
            line = candidate
    if line != prefix:
        lines.append(line)
    return lines or [prefix]


def emit_function(op: dict, name: str) -> str:
    """One operation as a Rune function over `gamend::rest`."""
    args = ["node"] + [safe(p) for p in op["path_params"]]
    required_body: list[str] = []
    if op["body"]:
        args.append("params")
        required_body = list(op["body"]["schema"].get("required", []))
    if op["query"]:
        args.append("options")
    # The trampoline behind `script::require` carries five arguments; the
    # document's worst case is a node, two path parameters, a body and a
    # query, which is exactly five.
    if len(args) > 5:
        raise SystemExit(f"{name}: {len(args)} arguments, more than require carries")

    out = wrap(op["summary"], 76, "///")
    out.append(f"/// `{op['method']} {op['path']}`")
    out.append(f"pub fn {name}({', '.join(args)}) {{")
    if required_body or op["query"]:
        out.append("    let core = script::require(CORE);")
    for field in required_body:
        out.append(f'    if !(core.given)(params, {json.dumps(field)}) {{')
        out.append(f'        return (core.missing)({json.dumps(name)}, {json.dumps(field)});')
        out.append("    }")
    if op["query"]:
        for field in [q for q, needed in op["query"] if needed]:
            out.append(f'    if !(core.given)(options, {json.dumps(field)}) {{')
            out.append(
                f'        return (core.missing)({json.dumps(name)}, {json.dumps(field)});'
            )
            out.append("    }")
        allowed = ", ".join(json.dumps(q) for q, _ in op["query"])
        out.append(f"    let query = (core.query)(options, [{allowed}]);")
    path = path_expression(op, bool(op["query"]))
    call = f'gamend::rest(node, "{op["method"]}", {path}'
    call += ", params)" if op["body"] else ")"
    out.append(f"    {call}")
    out.append("}")
    return "\n".join(out)


def write_api(ops: list[dict], aliases: dict[str, str]) -> str:
    seen: dict[str, str] = {}
    chunks = [
        BANNER,
        "//! Every Gamend operation, one function each.\n"
        "//!\n"
        "//! A call takes the node its result should reach, then the path's own\n"
        "//! parameters, then `params` for the request body and `options` for the\n"
        "//! query where the operation has them. It answers the id `gamend::rest`\n"
        "//! answers, so a caller awaits it the same way:\n"
        "//!\n"
        "//!     let api = script::require(\"addons/gamend/api.rn\");\n"
        "//!     let reply = task::wait((api.lobbies_quick_join)(this.node, #{\n"
        "//!         \"title\": \"duel\", \"max_users\": 2,\n"
        "//!     })).await;\n",
        'const CORE = "addons/gamend/core.rn";\n',
    ]
    for op in ops:
        name = function_name(op, aliases)
        if name in seen:
            raise SystemExit(f"{name}: {op['id']} and {seen[name]} want the same name")
        seen[name] = op["id"]
        chunks.append(emit_function(op, name))
    return "\n\n".join(chunks) + "\n"


def write_events(table: list[dict]) -> str:
    signals = sorted({row["signal"] for row in table})
    lines = [
        BANNER,
        "//! The realtime events, one constant each, and the decoder that names\n"
        "//! a raw socket message.\n"
        "//!\n"
        "//! OpenAPI does not describe the socket, so this comes from\n"
        "//! `clients/events.json`, which the Godot client's dispatch seeded. An\n"
        "//! event the table does not name still arrives, as `message`.\n",
    ]
    for signal in signals:
        lines.append(f'pub const {signal.upper()} = "{signal}";')
    rows = ",\n".join(
        f'    ["{row["channel"]}", "{row["event"]}", "{row["signal"]}"]' for row in table
    )
    lines.append(
        "/// Every row of the table: the channel a topic belongs to, the event the\n"
        "/// server sends, and what this client calls it.\n"
        f"pub fn table() {{\n    [\n{rows},\n    ]\n}}"
    )
    lines.append(
        '/// The channel a topic names: `lobby:12` is `lobby`, `lobbies` is itself.\n'
        "pub fn channel_of(topic) {\n"
        '    let parts = topic.split(":").collect::<Vec>();\n'
        "    parts[0]\n"
        "}"
    )
    lines.append(
        "/// A socket message as this client names it. The payload is carried\n"
        "/// through under `kind`; an event no row names comes back as `message`.\n"
        "pub fn decode(topic, event, payload) {\n"
        "    let channel = channel_of(topic);\n"
        "    let named = \"message\";\n"
        "    for row in table() {\n"
        "        if row[0] == channel && row[1] == event {\n"
        "            named = row[2];\n"
        "            break;\n"
        "        }\n"
        "    }\n"
        "    let out = #{};\n"
        "    if payload is Object {\n"
        "        for key in payload.keys() {\n"
        "            out[key] = payload[key];\n"
        "        }\n"
        "    }\n"
        '    out["kind"] = named;\n'
        '    out["topic"] = topic;\n'
        '    out["event"] = event;\n'
        "    out\n"
        "}"
    )
    return "\n\n".join(lines) + "\n"


def write_readme(ops: list[dict], aliases: dict[str, str], table: list[dict]) -> str:
    lines = [
        "# The Gamend SDK for Balaur",
        "",
        "Written by `clients/generate_balaur.py`. Copy this directory into a",
        "project as `addons/gamend/` and require what you need:",
        "",
        "```rune",
        'let api = script::require("addons/gamend/api.rn");',
        'let client = script::require("addons/gamend/client.rn");',
        "```",
        "",
        f"{len(ops)} operations and {len({r['signal'] for r in table})} realtime events.",
        "",
    ]
    by_tag: dict[str, list[dict]] = {}
    for op in ops:
        by_tag.setdefault(op["tag"], []).append(op)
    for tag in sorted(by_tag):
        lines += [f"## {tag}", "", "| Function | Call | What it does |", "| --- | --- | --- |"]
        for op in by_tag[tag]:
            name = function_name(op, aliases)
            args = ["node"] + [p for p in op["path_params"]]
            if op["body"]:
                args.append("params")
            if op["query"]:
                args.append("options")
            summary = op["summary"].replace("|", "\\|")
            lines.append(f"| `{name}({', '.join(args)})` | `{op['method']} {op['path']}` | {summary} |")
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=OUT)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when the written files are not what this would write",
    )
    args = parser.parse_args()

    spec = json.loads(SPEC.read_text())
    table = json.loads(EVENTS.read_text())
    aliases = json.loads(NAMES.read_text())
    ops = operations(spec)

    files = {
        "api.rn": write_api(ops, aliases),
        "events.rn": write_events(table),
        "README.md": write_readme(ops, aliases, table),
    }

    if args.check:
        stale = [
            name
            for name, text in files.items()
            if not (args.out / name).is_file() or (args.out / name).read_text() != text
        ]
        for name in TEMPLATE.rglob("*"):
            if name.is_file():
                target = args.out / name.relative_to(TEMPLATE)
                if not target.is_file() or target.read_bytes() != name.read_bytes():
                    stale.append(str(name.relative_to(TEMPLATE)))
        if stale:
            print("stale: " + ", ".join(stale), file=sys.stderr)
            print("run clients/generate_balaur.sh", file=sys.stderr)
            return 1
        print(f"{args.out.relative_to(ROOT)} is current")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (args.out / name).write_text(text)
    # The hand-written half goes over the top, as gamend_template does for
    # Godot: this script owns three files and never the rest.
    for name in TEMPLATE.rglob("*"):
        if name.is_file():
            target = args.out / name.relative_to(TEMPLATE)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(name, target)
    print(
        f"wrote {len(ops)} operations and {len({r['signal'] for r in table})} events "
        f"to {args.out.relative_to(ROOT)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
