#!/usr/bin/env python3
"""Copy transitive DLL dependencies into a Windows package."""

import argparse
import os
import shutil
import subprocess


def dependencies(path, objdump):
    output = subprocess.run([objdump, "-p", path], capture_output=True, text=True).stdout
    return [line.split(":", 1)[1].strip()
            for line in output.splitlines() if "DLL Name:" in line]


def deploy(package, binaries, plugin_dirs, search_dirs, objdump):
    todo = list(binaries)
    for root in plugin_dirs:
        for directory, _, files in os.walk(root):
            todo.extend(os.path.join(directory, name) for name in files)

    seen = set()
    while todo:
        current = todo.pop()
        for name in dependencies(current, objdump):
            key = name.lower()
            if key in seen:
                continue
            seen.add(key)
            for folder in search_dirs:
                source = os.path.join(folder, name)
                if not os.path.isfile(source):
                    continue
                target = os.path.join(package, name)
                if not os.path.isfile(target):
                    shutil.copy2(source, target)
                todo.append(target)
                break


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package-dir", required=True)
    parser.add_argument("--binary", action="append", required=True)
    parser.add_argument("--plugin-dir", action="append", default=[])
    parser.add_argument("--search-dir", action="append", required=True)
    parser.add_argument("--objdump", required=True)
    parser.add_argument("--label", default="deployed")
    args = parser.parse_args()

    deploy(args.package_dir, args.binary, args.plugin_dir, args.search_dir, args.objdump)
    dlls = sorted(name for name in os.listdir(args.package_dir) if name.endswith(".dll"))
    print(f"{args.label}: " + ", ".join(dlls))


if __name__ == "__main__":
    main()
