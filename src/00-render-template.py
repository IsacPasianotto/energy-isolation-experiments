#!/usr/bin/env python3
"""Render the jinja2 templates of the project with a given set of values.

Every ``*.j2`` file found in the template directory is rendered with the
settings declared in the values file (a flat TOML) and written to the output
directory without the ``.j2`` suffix, e.g.::

    config/templates/telegraf-config.toml.j2
        -> last_applied_configuration/telegraf-config.toml

Usually invoked through ``runme.sh``, but it is standalone:

    ./src/render-template.py --templates config/templates \
                             --values config/telegraf/template-values.toml \
                             --out last_applied_configuration
"""

import argparse
import sys
from pathlib import Path

try:
    from jinja2 import Environment, FileSystemLoader, StrictUndefined
except ModuleNotFoundError:
    sys.exit(
        "error: the jinja2 python module is not available; install it with "
        "'python3 -m pip install jinja2' (or the distro package python3-jinja2)."
    )


def die(message):
    sys.exit(f"error: {message}")

#
# Values file (TOML)
#
def load_values(path):
    """Parse the values file, preferring a real TOML parser when there is one."""
    try:
        import tomllib
    except ModuleNotFoundError:
        try:
            import tomli as tomllib
        except ModuleNotFoundError:
            tomllib = None

    if tomllib is not None:
        with path.open("rb") as fh:
            return tomllib.load(fh)

    # python < 3.11 without tomli: the values file is a flat list of
    # "key = value" pairs, so a minimal parser is enough.
    return parse_flat_toml(path)


def strip_comment(line):
    """Drop everything after a '#', unless it sits inside a quoted string."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
        elif ch == "#":
            return line[:i]
    return line


def parse_flat_toml(path):
    values = {}
    for lineno, raw in enumerate(path.read_text().splitlines(), start=1):
        line = strip_comment(raw).strip()
        if not line:
            continue
        if line.startswith("["):
            die(
                f"{path}:{lineno}: this python ({sys.version.split()[0]}) has no TOML "
                "parser and the fallback one does not support tables; install tomli "
                "('python3 -m pip install tomli') or use python >= 3.11."
            )
        if "=" not in line:
            die(f"{path}:{lineno}: cannot parse {raw!r}")
        key, _, value = line.partition("=")
        values[key.strip()] = parse_value(value.strip(), path, lineno)
    return values


def parse_value(value, path, lineno):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    if value in ("true", "false"):
        return value == "true"
    for cast in (int, float):
        try:
            return cast(value)
        except ValueError:
            pass
    die(f"{path}:{lineno}: unsupported value {value!r}")


# 
# Rendering
# --------------------------------------------------------------------------

def render(template_dir, values, out_dir):
    env = Environment(
        loader=FileSystemLoader(str(template_dir)),
        undefined=StrictUndefined,   # fail loudly on a setting missing from the values file
        keep_trailing_newline=True,
        trim_blocks=True,
        lstrip_blocks=True,
    )

    templates = sorted(p for p in template_dir.iterdir() if p.suffix == ".j2")
    if not templates:
        die(f"no *.j2 template found in {template_dir}")

    for template in templates:
        rendered = env.get_template(template.name).render(**values)
        target = out_dir / template.stem          # drops the .j2 suffix
        target.write_text(rendered)
        print(f"  {template.name} -> {target}")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--templates", required=True, type=Path,
                        help="directory holding the *.j2 templates")
    parser.add_argument("--values", required=True, type=Path,
                        help="TOML file holding the values to render with")
    parser.add_argument("--out", required=True, type=Path,
                        help="directory where the rendered files are written")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)

    if not args.templates.is_dir():
        die(f"template directory not found: {args.templates}")
    if not args.values.is_file():
        die(f"values file not found: {args.values}")

    args.out.mkdir(parents=True, exist_ok=True)

    values = load_values(args.values)
    render(args.templates, values, args.out)

    print("\nvalues used:")
    for key in sorted(values):
        print(f"  {key} = {values[key]!r}")


if __name__ == "__main__":
    main()
