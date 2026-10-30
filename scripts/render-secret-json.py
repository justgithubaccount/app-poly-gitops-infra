#!/usr/bin/env python3
"""Build a Kubernetes Secret JSON document from named environment variables."""

import argparse
import base64
import json
import os
import re
import sys


KEY_RE = re.compile(r"^[A-Za-z0-9._-]+$")
ENV_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(2)


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--name", required=True)
    parser.add_argument("--namespace", required=True)
    parser.add_argument("--repo", action="store_true")
    parser.add_argument("specs", nargs="+")
    args = parser.parse_args()

    data = {}
    for spec in args.specs:
        if "=" in spec:
            fail(f"invalid key mapping {spec.split('=', 1)[0]!r}; expected KEY[:ENV_VAR]")
        key, separator, env_name = spec.partition(":")
        if not separator:
            env_name = key
        if not KEY_RE.fullmatch(key) or not ENV_RE.fullmatch(env_name):
            fail(f"invalid key mapping {spec!r}; expected KEY[:ENV_VAR]")
        value = os.environ.get(env_name)
        if not value:
            fail(f"environment variable {env_name} is unset or empty")
        data[key] = base64.b64encode(value.encode()).decode()

    metadata = {"name": args.name, "namespace": args.namespace}
    if args.repo:
        metadata["labels"] = {"argocd.argoproj.io/secret-type": "repository"}
    json.dump(
        {"apiVersion": "v1", "kind": "Secret", "metadata": metadata, "data": data},
        sys.stdout,
        separators=(",", ":"),
    )
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
