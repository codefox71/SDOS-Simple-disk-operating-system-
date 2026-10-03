"""Simple Disk Operating System (SDOS) simulator.

This kernel implements the commands described in the project README using the
low-level memory shims in lib.py.
"""

from __future__ import annotations

import re
import shlex
from pathlib import Path
from typing import Optional
from typing import Dict, Iterable, List, Sequence, Tuple

from btfs import BTFS
from lib import list_memory_free, read_value_from_memory, start_excute_at, write_value_to_memory


def _to_int(value: str, name: str = "value") -> int:
    text = str(value).strip()
    if not text:
        raise ValueError(f"{name} cannot be empty")
    try:
        if text.lower().startswith("0x"):
            return int(text, 16)
        return int(text, 0)
    except ValueError as exc:
        raise ValueError(f"{name} is not a valid integer: {value!r}") from exc


class Kernel:
    """Simple in-memory OS kernel that imitates the README commands."""

    def __init__(self, memory_size: int = 4096, fs_path: Optional[str] = None):
        self.memory_size = memory_size
        self.memory: Dict[int, int] = {address: 0 for address in range(memory_size)}
        default_fs_path = Path(__file__).resolve().parent.parent / "build" / "btfs.img"
        self.filesystem = BTFS(fs_path or default_fs_path)
        self.cwd = "/"
        self._allocated_ranges: List[Tuple[int, int]] = []

    def _validate_range(self, start: object, end: object) -> Tuple[int, int]:
        start_addr = _to_int(start, "start")
        end_addr = _to_int(end, "end")

        if start_addr < 0 or end_addr < 0:
            raise ValueError("memory addresses must be non-negative")
        if end_addr < start_addr:
            raise ValueError("end address must be greater than or equal to start address")
        if end_addr >= self.memory_size:
            raise ValueError(
                f"end address {end_addr} exceeds the memory bounds of {self.memory_size - 1}"
            )
        return start_addr, end_addr

    def read_memory(self, address: object) -> int:
        addr = _to_int(address, "address")
        if addr < 0 or addr >= self.memory_size:
            raise ValueError(f"memory address {addr} is outside the valid range")
        value = self.memory.get(addr, 0)
        read_value_from_memory(addr)
        return value

    def write_memory(self, address: object, value: object) -> int:
        addr = _to_int(address, "address")
        numeric_value = _to_int(value, "value")
        if addr < 0 or addr >= self.memory_size:
            raise ValueError(f"memory address {addr} is outside the valid range")
        if numeric_value < 0 or numeric_value > 255:
            raise ValueError("memory values are limited to 8-bit unsigned integers (0-255)")

        self.memory[addr] = numeric_value
        write_value_to_memory(addr, numeric_value)
        return numeric_value

    def dir(self, start: object, end: object) -> List[Tuple[int, int]]:
        start_addr, end_addr = self._validate_range(start, end)
        values = []
        for addr in range(start_addr, end_addr + 1):
            values.append((addr, self.read_memory(addr)))
        return values

    def load(self, raw_hex: str, start: object, end: object) -> List[int]:
        start_addr, end_addr = self._validate_range(start, end)
        normalized = re.sub(r"[^0-9A-Fa-f]", "", str(raw_hex))

        if not normalized:
            raise ValueError("no raw hex data was supplied")
        if len(normalized) % 2 != 0:
            raise ValueError("hex payload must contain complete bytes (even number of digits)")

        payload = [int(normalized[i : i + 2], 16) for i in range(0, len(normalized), 2)]
        width = end_addr - start_addr + 1
        if len(payload) > width:
            raise ValueError(
                f"payload size {len(payload)} exceeds the requested memory width {width}"
            )

        for offset, byte_value in enumerate(payload):
            self.write_memory(start_addr + offset, byte_value)
        self._reserve_range(start_addr, start_addr + len(payload) - 1)
        return payload

    def run(self, start: object, end: object) -> List[int]:
        start_addr, end_addr = self._validate_range(start, end)
        start_excute_at(start_addr, end_addr)
        return [self.read_memory(addr) for addr in range(start_addr, end_addr + 1)]

    def mem(self) -> Dict[str, int]:
        free_memory = list_memory_free()
        zero_addresses = sum(1 for value in self.memory.values() if value == 0)
        return {
            "zero_addresses": zero_addresses,
            "free_memory": free_memory,
        }

    def _reserve_range(self, start: int, end: int) -> None:
        self._allocated_ranges.append((start, end))
        self._allocated_ranges.sort()
        merged: List[Tuple[int, int]] = []
        for range_start, range_end in self._allocated_ranges:
            if merged and range_start <= merged[-1][1] + 1:
                merged[-1] = (merged[-1][0], max(merged[-1][1], range_end))
            else:
                merged.append((range_start, range_end))
        self._allocated_ranges = merged

    def _find_free_range(self, size: int) -> Tuple[int, int]:
        if size <= 0:
            raise ValueError("cannot load an empty BTfs file")
        if size > self.memory_size:
            raise ValueError(f"file size {size} exceeds memory capacity {self.memory_size}")
        candidate = 0
        for start, end in self._allocated_ranges:
            if candidate + size - 1 < start:
                break
            candidate = max(candidate, end + 1)
        end = candidate + size - 1
        if end >= self.memory_size:
            raise ValueError("not enough contiguous memory for BTfs file")
        return candidate, end

    def _load_payload(self, payload: bytes, start: int) -> Tuple[int, int]:
        end = start + len(payload) - 1
        self._validate_range(start, end)
        for offset, byte_value in enumerate(payload):
            self.write_memory(start + offset, byte_value)
        self._reserve_range(start, end)
        return start, end

    def load_file(self, path: str) -> Tuple[int, int, bytes]:
        payload = self.filesystem.read_file(path, self.cwd)
        start, end = self._find_free_range(len(payload))
        self._load_payload(payload, start)
        return start, end, payload

    def run_files(self, paths: Sequence[str]) -> Tuple[int, int, List[int]]:
        if not paths:
            raise ValueError("run requires at least one BTfs file")
        payloads = [self.filesystem.read_file(path, self.cwd) for path in paths]
        if any(not payload for payload in payloads):
            raise ValueError("cannot run an empty BTfs file")
        program = b"".join(payloads)
        start, end = self._find_free_range(len(program))
        self._load_payload(program, start)
        result = self.run(start, end)
        return start, end, result

    def _list_files(self, path: str = ".") -> List[Tuple[str, str, int]]:
        entries = self.filesystem.list_directory(path, self.cwd)
        return [
            (entry.name, "dir" if entry.is_directory else "file", entry.size)
            for entry in entries
        ]

    def execute(self, command_line: str):
        if not command_line or not command_line.strip():
            return None

        try:
            tokens = shlex.split(command_line)
        except ValueError as exc:
            raise ValueError(f"unable to parse command: {command_line!r}") from exc

        if not tokens:
            return None

        command = tokens[0].lower()

        if command == "dir":
            if len(tokens) != 3:
                raise ValueError("usage: dir [start] [end]")
            result = self.dir(tokens[1], tokens[2])
            print(result)
            return result

        if command == "load":
            if len(tokens) == 3:
                normalized = re.sub(r"[^0-9A-Fa-f]", "", tokens[2])
                if not normalized or len(normalized) % 2:
                    raise ValueError("file contents must be non-empty complete hex bytes")
                payload = bytes.fromhex(normalized)
                count = self.filesystem.write_file(tokens[1], payload, self.cwd)
                print(f"Wrote {count} bytes to {tokens[1]}")
                return payload
            if len(tokens) != 4:
                raise ValueError("usage: load [path] [raw_hex] | load [raw_hex] [start] [end]")
            result = self.load(tokens[1], tokens[2], tokens[3])
            print(f"Loaded {len(result)} bytes to memory")
            return result

        if command == "run":
            if len(tokens) >= 3 and tokens[1].startswith("-f"):
                if (len(tokens) - 1) % 2 != 0:
                    raise ValueError("usage: run -f1 [file1] -f2 [file2] ...")
                paths = []
                expected_index = 1
                for index in range(1, len(tokens), 2):
                    match = re.fullmatch(r"-f([0-9]+)", tokens[index])
                    if match is None or int(match.group(1)) != expected_index:
                        raise ValueError("file flags must be ordered -f1, -f2, and so on")
                    paths.append(tokens[index + 1])
                    expected_index += 1
                start, end, result = self.run_files(paths)
                print(f"Executed {len(paths)} BTfs files in order at memory range {start}-{end}")
                return result
            if len(tokens) != 3:
                raise ValueError("usage: run [start] [end] | run -f1 [file1] -f2 [file2] ...")
            result = self.run(tokens[1], tokens[2])
            print(f"Executed memory range {tokens[1]} to {tokens[2]}")
            return result

        if command in {"chdir", "cd"}:
            if len(tokens) != 2:
                raise ValueError("usage: chdir [path]")
            directory = self.filesystem.resolve_directory(tokens[1], self.cwd)
            self.cwd = self.filesystem.node_path(directory)
            print(self.cwd)
            return self.cwd

        if command in {"rmf", "rm"}:
            if len(tokens) != 2:
                raise ValueError("usage: RMF [file]")
            self.filesystem.remove_file(tokens[1], self.cwd)
            print(f"Removed {tokens[1]}")
            return None

        if command in {"cpy", "cp"}:
            if len(tokens) != 3:
                raise ValueError("usage: cpy [source] [destination]")
            count = self.filesystem.copy_file(tokens[1], tokens[2], self.cwd)
            print(f"Copied {count} bytes")
            return count

        if command in {"move", "mv"}:
            if len(tokens) != 3:
                raise ValueError("usage: move [source] [destination]")
            destination = self.filesystem.move_node(tokens[1], tokens[2], self.cwd)
            print(f"Moved to {destination}")
            return destination

        if command == "pwd":
            print(self.cwd)
            return self.cwd

        if command in {"mkdir", "makedir"}:
            if len(tokens) != 2:
                raise ValueError("usage: mkdir [path]")
            path = self.filesystem.make_directory(tokens[1], self.cwd)
            print(f"Created directory {path}")
            return path

        if command in {"remdir", "rmdir"}:
            if len(tokens) != 2:
                raise ValueError("usage: remdir [path]")
            self.filesystem.remove_directory(tokens[1], self.cwd)
            print(f"Removed directory {tokens[1]}")
            return None

        if command == "write":
            if len(tokens) != 3:
                raise ValueError("usage: write [path] [raw_hex]")
            normalized = re.sub(r"[^0-9A-Fa-f]", "", tokens[2])
            if not normalized or len(normalized) % 2:
                raise ValueError("file contents must be non-empty complete hex bytes")
            payload = bytes.fromhex(normalized)
            count = self.filesystem.write_file(tokens[1], payload, self.cwd)
            print(f"Wrote {count} bytes to {tokens[1]}")
            return payload

        if command == "touch":
            if len(tokens) != 2:
                raise ValueError("usage: touch [path]")
            self.filesystem.write_file(tokens[1], b"", self.cwd)
            print(f"Created {tokens[1]}")
            return None

        if command == "cat":
            if len(tokens) != 2:
                raise ValueError("usage: cat [file]")
            contents = self.filesystem.read_file(tokens[1], self.cwd)
            text = "".join(
                chr(value) if value in (9, 10, 13) or 0x20 <= value <= 0x7E else "."
                for value in contents
            )
            print(text, end="")
            return contents

        if command == "echo":
            text = " ".join(tokens[1:])
            print(text)
            return text

        if command == "clear":
            if len(tokens) != 1:
                raise ValueError("usage: clear")
            print("\033[2J\033[H", end="")
            return None

        if command == "ls":
            if len(tokens) > 2:
                raise ValueError("usage: ls [path]")
            entries = self._list_files(tokens[1] if len(tokens) == 2 else ".")
            for name, kind, size in entries:
                suffix = "/" if kind == "dir" else f" ({size} bytes)"
                print(f"{name}{suffix}")
            return entries

        if command == "mem":
            result = self.mem()
            print(f"Zero addresses: {result['zero_addresses']}")
            return result

        if command in {"help", "--help", "-h"}:
            help_text = (
                "Available commands:\n"
                "  dir [start] [end]        list values inside a memory range\n"
                "  load [path] [raw_hex]    create or replace a BTfs file\n"
                "  load [raw_hex] [start] [end]  write raw bytes to memory\n"
                "  run [start] [end]        execute a memory range\n"
                "  run -f1 [file] ...       load and run BTfs files in order\n"
                "  chdir [path]             change BTfs working directory\n"
                "  cd [path]                alias for chdir\n"
                "  pwd                      print the current path\n"
                "  cat [file]               display file contents\n"
                "  echo [text]              print text\n"
                "  clear                    clear the terminal\n"
                "  touch [path]             create an empty file\n"
                "  makedir [path]           create a BTfs directory\n"
                "  remdir [path]            remove an empty BTfs directory\n"
                "  rm [path]                remove a BTfs file\n"
                "  cp [source] [dest]       copy a BTfs file\n"
                "  mv [source] [dest]       move or rename a BTfs node\n"
                "  ls [path]                list BTfs tree nodes\n"
                "  /bin/<program>           execute a BTfs program (shim in Python)\n"
                "  mem                     show zero-filled memory addresses\n"
            )
            print(help_text)
            return help_text

        bin_path = f"/bin/{command}"
        try:
            self.filesystem.read_file(bin_path)
        except ValueError:
            raise ValueError(f"unknown command: {command}")
        _, _, result = self.run_files([bin_path])
        print(f"Executed {bin_path} through the Python execution shim")
        return result


def main() -> None:
    kernel = Kernel()
    print("SDOS ready. Type 'help' for a list of commands.")
    while True:
        try:
            command_line = input("SDOS> ")
        except EOFError:
            print()
            break
        if not command_line.strip():
            continue
        try:
            kernel.execute(command_line)
        except ValueError as exc:
            print(f"Error: {exc}")


kernel = Kernel()


def command(command_line: str):
    return kernel.execute(command_line)


if __name__ == "__main__":
    main()
