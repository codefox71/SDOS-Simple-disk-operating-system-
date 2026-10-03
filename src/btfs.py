"""Persistent BTfs block-tree volume used by the SDOS Python monitor."""

from __future__ import annotations

import math
import os
import struct
import tempfile
from dataclasses import dataclass
from pathlib import Path


MAGIC = b"BTFS"
VERSION = 1
SUPERBLOCK_ID = 0xB7F5
BLOCK_SIZE = 256
TREE_CAPACITY = 64
DATA_BLOCK_COUNT = 256
DATA_PAYLOAD_SIZE = BLOCK_SIZE - 2
HEADER_SIZE = 32
TREE_RECORD_SIZE = 64
NO_BLOCK = 0xFFFF
ROOT_ID = 0
DIRECTORY = 1
FILE = 2

HEADER = struct.Struct("<4sHHHHHH")
RECORD = struct.Struct("<HHBB40sHHI10x")
VOLUME_SIZE = HEADER_SIZE + TREE_CAPACITY * TREE_RECORD_SIZE + DATA_BLOCK_COUNT * BLOCK_SIZE


@dataclass(frozen=True)
class Node:
    node_id: int
    parent_id: int
    kind: int
    name: str
    first_block: int = NO_BLOCK
    block_count: int = 0
    size: int = 0

    @property
    def is_directory(self) -> bool:
        return self.kind == DIRECTORY


class BTFS:
    """Small persistent filesystem with a fixed tree zone and linked data zone."""

    def __init__(self, image_path: str | os.PathLike[str]):
        self.image_path = Path(image_path)
        self.nodes: dict[int, Node] = {}
        self.data_blocks = [bytearray(BLOCK_SIZE) for _ in range(DATA_BLOCK_COUNT)]
        self.image_path.parent.mkdir(parents=True, exist_ok=True)
        if self.image_path.exists():
            self._read_volume()
        else:
            self._format()
            self._write_volume()

    def _format(self) -> None:
        self.superblock_id = SUPERBLOCK_ID
        self.nodes = {
            ROOT_ID: Node(ROOT_ID, NO_BLOCK, DIRECTORY, ""),
        }
        self.data_blocks = [bytearray(BLOCK_SIZE) for _ in range(DATA_BLOCK_COUNT)]

    def _read_volume(self) -> None:
        raw = self.image_path.read_bytes()
        if len(raw) != VOLUME_SIZE:
            raise ValueError(f"invalid BTfs volume size: {len(raw)} bytes")
        magic, version, super_id, block_size, tree_count, data_count, record_size = HEADER.unpack_from(raw)
        if magic != MAGIC or version != VERSION:
            raise ValueError("invalid or unsupported BTfs volume")
        if (block_size, tree_count, data_count, record_size) != (
            BLOCK_SIZE,
            TREE_CAPACITY,
            DATA_BLOCK_COUNT,
            TREE_RECORD_SIZE,
        ):
            raise ValueError("BTfs volume layout does not match this implementation")
        self.superblock_id = super_id
        self.nodes = {}
        tree_start = HEADER_SIZE
        for slot in range(TREE_CAPACITY):
            offset = tree_start + slot * TREE_RECORD_SIZE
            values = RECORD.unpack_from(raw, offset)
            node_id, parent_id, kind, name_length, name_field, first_block, block_count, size = values
            if node_id == NO_BLOCK:
                continue
            if node_id >= TREE_CAPACITY or node_id in self.nodes:
                raise ValueError("invalid BTfs tree node ID")
            try:
                name = name_field[:name_length].decode("utf-8")
            except UnicodeDecodeError as exc:
                raise ValueError("invalid BTfs filename encoding") from exc
            if kind not in (DIRECTORY, FILE) or name_length > 40:
                raise ValueError("invalid BTfs tree node")
            self.nodes[node_id] = Node(node_id, parent_id, kind, name, first_block, block_count, size)

        if ROOT_ID not in self.nodes or not self.nodes[ROOT_ID].is_directory:
            raise ValueError("BTfs root node is missing or invalid")

        data_start = HEADER_SIZE + TREE_CAPACITY * TREE_RECORD_SIZE
        self.data_blocks = [
            bytearray(raw[offset : offset + BLOCK_SIZE])
            for offset in range(data_start, len(raw), BLOCK_SIZE)
        ]
        for node in self.nodes.values():
            if node.node_id == ROOT_ID:
                continue
            if node.parent_id not in self.nodes or not self.nodes[node.parent_id].is_directory:
                raise ValueError("BTfs node refers to an invalid parent")
            if node.kind == FILE:
                self._file_chain(node)

    def _write_volume(self) -> None:
        image = bytearray(VOLUME_SIZE)
        HEADER.pack_into(
            image,
            0,
            MAGIC,
            VERSION,
            getattr(self, "superblock_id", SUPERBLOCK_ID),
            BLOCK_SIZE,
            TREE_CAPACITY,
            DATA_BLOCK_COUNT,
            TREE_RECORD_SIZE,
        )
        for slot in range(TREE_CAPACITY):
            node = self.nodes.get(slot)
            if node is None:
                RECORD.pack_into(image, HEADER_SIZE + slot * TREE_RECORD_SIZE, NO_BLOCK, 0, 0, 0, b"", NO_BLOCK, 0, 0)
                continue
            encoded_name = node.name.encode("utf-8")
            if len(encoded_name) > 40:
                raise ValueError("BTfs names are limited to 40 UTF-8 bytes")
            RECORD.pack_into(
                image,
                HEADER_SIZE + slot * TREE_RECORD_SIZE,
                node.node_id,
                node.parent_id,
                node.kind,
                len(encoded_name),
                encoded_name,
                node.first_block,
                node.block_count,
                node.size,
            )

        data_start = HEADER_SIZE + TREE_CAPACITY * TREE_RECORD_SIZE
        for index, block in enumerate(self.data_blocks):
            start = data_start + index * BLOCK_SIZE
            image[start : start + BLOCK_SIZE] = block

        with tempfile.NamedTemporaryFile(dir=self.image_path.parent, delete=False) as temporary:
            temporary.write(image)
            temporary.flush()
            os.fsync(temporary.fileno())
            temporary_path = Path(temporary.name)
        os.replace(temporary_path, self.image_path)

    def _children(self, parent_id: int) -> dict[str, Node]:
        return {
            node.name: node
            for node in self.nodes.values()
            if node.parent_id == parent_id and node.node_id != ROOT_ID
        }

    def _resolve(self, path: str, cwd: str = "/") -> Node:
        if not path:
            raise ValueError("path cannot be empty")
        current = self.nodes[ROOT_ID] if path.startswith("/") else self.resolve_directory(cwd)
        for part in path.split("/"):
            if part in ("", "."):
                continue
            if part == "..":
                current = self.nodes.get(current.parent_id, self.nodes[ROOT_ID])
                continue
            if not current.is_directory:
                raise ValueError(f"not a directory: {current.name}")
            child = self._children(current.node_id).get(part)
            if child is None:
                raise ValueError(f"BTfs path not found: {path}")
            current = child
        return current

    def resolve_directory(self, path: str, cwd: str = "/") -> Node:
        node = self._resolve(path, cwd)
        if not node.is_directory:
            raise ValueError(f"not a directory: {path}")
        return node

    def node_path(self, node: Node) -> str:
        if node.node_id == ROOT_ID:
            return "/"
        parts = []
        current = node
        while current.node_id != ROOT_ID:
            parts.append(current.name)
            current = self.nodes[current.parent_id]
        return "/" + "/".join(reversed(parts))

    def list_directory(self, path: str = ".", cwd: str = "/") -> list[Node]:
        directory = self.resolve_directory(path, cwd)
        return sorted(
            self._children(directory.node_id).values(),
            key=lambda node: (not node.is_directory, node.name.casefold()),
        )

    def _new_node_id(self) -> int:
        for node_id in range(1, TREE_CAPACITY):
            if node_id not in self.nodes:
                return node_id
        raise ValueError("BTfs tree zone is full")

    @staticmethod
    def _validate_name(name: str) -> None:
        encoded_name = name.encode("utf-8")
        if not name or name in (".", "..") or "/" in name or "\0" in name:
            raise ValueError(f"invalid BTfs name: {name!r}")
        if len(encoded_name) > 40:
            raise ValueError("BTfs names are limited to 40 UTF-8 bytes")

    def _parent_and_name(self, path: str, cwd: str) -> tuple[Node, str]:
        stripped = path.rstrip("/")
        if not stripped:
            raise ValueError("cannot create a node at the BTfs root")
        parent_text, separator, name = stripped.rpartition("/")
        if path.startswith("/"):
            parent_path = parent_text or "/"
        else:
            parent_path = parent_text or "."
        self._validate_name(name)
        return self.resolve_directory(parent_path, cwd), name

    def make_directory(self, path: str, cwd: str = "/") -> str:
        parent, name = self._parent_and_name(path, cwd)
        if name in self._children(parent.node_id):
            raise ValueError(f"BTfs path already exists: {path}")
        node = Node(self._new_node_id(), parent.node_id, DIRECTORY, name)
        self.nodes[node.node_id] = node
        self._write_volume()
        return self.node_path(node)

    def remove_file(self, path: str, cwd: str = "/") -> None:
        node = self._resolve(path, cwd)
        if node.kind != FILE:
            raise ValueError(f"not a file: {path}")
        del self.nodes[node.node_id]
        self._write_volume()

    def remove_directory(self, path: str, cwd: str = "/") -> None:
        node = self.resolve_directory(path, cwd)
        if node.node_id == ROOT_ID:
            raise ValueError("cannot remove the BTfs root")
        if self._children(node.node_id):
            raise ValueError(f"directory is not empty: {path}")
        del self.nodes[node.node_id]
        self._write_volume()

    def copy_file(self, source: str, destination: str, cwd: str = "/") -> int:
        contents = self.read_file(source, cwd)
        return self.write_file(destination, contents, cwd)

    def move_node(self, source: str, destination: str, cwd: str = "/") -> str:
        node = self._resolve(source, cwd)
        if node.node_id == ROOT_ID:
            raise ValueError("cannot move the BTfs root")
        new_parent, new_name = self._parent_and_name(destination, cwd)
        existing = self._children(new_parent.node_id).get(new_name)
        if existing is not None and existing.node_id != node.node_id:
            raise ValueError(f"BTfs destination already exists: {destination}")
        ancestor = new_parent
        while ancestor.node_id != ROOT_ID:
            if ancestor.node_id == node.node_id:
                raise ValueError("cannot move a directory into itself")
            ancestor = self.nodes[ancestor.parent_id]
        moved = Node(
            node.node_id,
            new_parent.node_id,
            node.kind,
            new_name,
            node.first_block,
            node.block_count,
            node.size,
        )
        self.nodes[node.node_id] = moved
        self._write_volume()
        return self.node_path(moved)

    def _file_chain(self, node: Node) -> list[int]:
        if node.block_count == 0:
            if node.size != 0 or node.first_block != NO_BLOCK:
                raise ValueError("invalid empty file metadata in BTfs tree")
            return []
        if node.first_block >= DATA_BLOCK_COUNT:
            raise ValueError("BTfs file starts outside the data zone")
        chain = []
        current = node.first_block
        while current != NO_BLOCK:
            if current >= DATA_BLOCK_COUNT or current in chain:
                raise ValueError("invalid or cyclic BTfs data block chain")
            chain.append(current)
            following = struct.unpack_from("<H", self.data_blocks[current])[0]
            current = following
            if len(chain) > node.block_count:
                raise ValueError("BTfs file block chain is longer than its metadata")
        if len(chain) != node.block_count:
            raise ValueError("BTfs file block chain length does not match its metadata")
        if node.size > len(chain) * DATA_PAYLOAD_SIZE:
            raise ValueError("BTfs file size exceeds its data blocks")
        return chain

    def read_file(self, path: str, cwd: str = "/") -> bytes:
        node = self._resolve(path, cwd)
        if node.kind != FILE:
            raise ValueError(f"not a file: {path}")
        contents = bytearray()
        for block_id in self._file_chain(node):
            contents.extend(self.data_blocks[block_id][2:])
        return bytes(contents[: node.size])

    def write_file(self, path: str, contents: bytes, cwd: str = "/") -> int:
        parent, name = self._parent_and_name(path, cwd)
        existing = self._children(parent.node_id).get(name)
        if existing is not None and existing.kind != FILE:
            raise ValueError(f"cannot replace directory with a file: {path}")
        if len(contents) > DATA_BLOCK_COUNT * DATA_PAYLOAD_SIZE:
            raise ValueError("file is too large for the BTfs data zone")

        needed = math.ceil(len(contents) / DATA_PAYLOAD_SIZE)
        reusable = set(self._file_chain(existing)) if existing is not None else set()
        used = set()
        for node in self.nodes.values():
            if node.kind == FILE and node.node_id != (existing.node_id if existing else -1):
                used.update(self._file_chain(node))
        available = [block for block in range(DATA_BLOCK_COUNT) if block not in used]
        if len(available) < needed:
            raise ValueError("BTfs data zone is full")
        allocated = available[:needed]
        blocks = [bytearray(block) for block in self.data_blocks]
        for index, block_id in enumerate(allocated):
            next_id = allocated[index + 1] if index + 1 < len(allocated) else NO_BLOCK
            start = index * DATA_PAYLOAD_SIZE
            chunk = contents[start : start + DATA_PAYLOAD_SIZE]
            struct.pack_into("<H", blocks[block_id], 0, next_id)
            blocks[block_id][2:] = chunk.ljust(DATA_PAYLOAD_SIZE, b"\0")

        node_id = existing.node_id if existing is not None else self._new_node_id()
        node = Node(
            node_id,
            parent.node_id,
            FILE,
            name,
            allocated[0] if allocated else NO_BLOCK,
            len(allocated),
            len(contents),
        )
        self.data_blocks = blocks
        self.nodes[node_id] = node
        self._write_volume()
        return len(contents)