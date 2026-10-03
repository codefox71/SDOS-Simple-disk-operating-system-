#!/usr/bin/env python3
"""Merge a host directory tree into a persistent BTfs volume."""

from __future__ import annotations

import argparse
import os
from pathlib import Path

from btfs import BTFS


def merge_tree(source: Path, volume: Path) -> None:
    filesystem = BTFS(volume)
    if not source.is_dir():
        return

    for current, directory_names, file_names in os.walk(source):
        current_path = Path(current)
        directory_names.sort()
        file_names.sort()
        relative = current_path.relative_to(source)
        parent_path = "/" if relative == Path(".") else "/" + relative.as_posix()

        for directory_name in directory_names:
            directory_path = f"{parent_path.rstrip('/')}/{directory_name}"
            siblings = {node.name: node for node in filesystem.list_directory(parent_path)}
            existing = siblings.get(directory_name)
            if existing is None:
                filesystem.make_directory(directory_path)
            elif not existing.is_directory:
                raise ValueError(f"BTfs file conflicts with host directory: {directory_path}")

        for file_name in file_names:
            file_path = current_path / file_name
            btfs_path = f"{parent_path.rstrip('/')}/{file_name}"
            if file_path.suffix.lower() == ".hex":
                contents = bytes.fromhex(file_path.read_text(encoding="ascii"))
            else:
                contents = file_path.read_bytes()
            filesystem.write_file(btfs_path, contents)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="host tree to merge; missing folders seed an empty volume")
    parser.add_argument("volume", type=Path, help="BTfs image to create or update")
    arguments = parser.parse_args()
    try:
        merge_tree(arguments.source, arguments.volume)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"Updated BTfs volume: {arguments.volume}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())