#!/usr/bin/env python3
"""Compile a small C subset into 16-bit SDOS load/run commands."""

from __future__ import annotations

import re
import sys
from pathlib import Path


TOKEN_PATTERN = re.compile(
    r"\s+|//[^\n]*|/\*.*?\*/|'(?:\\.|[^'\\])'|"
    r"0[xX][0-9A-Fa-f]+|[0-9]+|[A-Za-z_]\w*|==|!=|<=|>=|[{}();,+\-=]",
    re.S,
)
Node = tuple


class CompileError(ValueError):
    pass


def tokenize(source: str) -> list[str]:
    tokens = []
    offset = 0
    while offset < len(source):
        match = TOKEN_PATTERN.match(source, offset)
        if match is None:
            raise CompileError(f"unexpected character at offset {offset}: {source[offset]!r}")
        token = match.group()
        if not token.isspace() and not token.startswith("//") and not token.startswith("/*"):
            tokens.append(token)
        offset = match.end()
    return tokens


class Parser:
    def __init__(self, tokens: list[str]):
        self.tokens = tokens
        self.position = 0
        self.locals: dict[str, int] = {}

    def peek(self) -> str | None:
        if self.position >= len(self.tokens):
            return None
        return self.tokens[self.position]

    def take(self, expected: str | None = None) -> str:
        token = self.peek()
        if token is None:
            raise CompileError(f"expected {expected or 'a token'}, found end of input")
        if expected is not None and token != expected:
            raise CompileError(f"expected {expected!r}, found {token!r}")
        self.position += 1
        return token

    def parse(self) -> Node:
        self.take("int")
        self.take("main")
        self.take("(")
        self.take(")")
        body = self.parse_block()
        if self.peek() is not None:
            raise CompileError(f"unexpected token after main: {self.peek()!r}")
        return body

    def parse_block(self) -> Node:
        self.take("{")
        statements = []
        while self.peek() != "}":
            if self.peek() is None:
                raise CompileError("unterminated block")
            statements.append(self.parse_statement())
        self.take("}")
        return ("block", statements)

    def parse_statement(self) -> Node:
        token = self.peek()
        if token == "{":
            return self.parse_block()
        if token == "int":
            self.take()
            name = self.take()
            if not re.fullmatch(r"[A-Za-z_]\w*", name):
                raise CompileError(f"expected a variable name, found {name!r}")
            if name in self.locals:
                raise CompileError(f"duplicate local variable: {name}")
            self.locals[name] = 2 * (len(self.locals) + 1)
            initializer = None
            if self.peek() == "=":
                self.take("=")
                initializer = self.parse_expression()
            self.take(";")
            return ("declare", name, initializer)
        if token == "while":
            self.take()
            self.take("(")
            condition = self.parse_expression()
            self.take(")")
            return ("while", condition, self.parse_statement())
        if token == "putchar":
            self.take()
            self.take("(")
            value = self.parse_expression()
            self.take(")")
            self.take(";")
            return ("putchar", value)
        if token == "return":
            self.take()
            value = self.parse_expression()
            self.take(";")
            return ("return", value)
        if token is not None and re.fullmatch(r"[A-Za-z_]\w*", token):
            name = self.take()
            if name not in self.locals:
                raise CompileError(f"unknown local variable: {name}")
            self.take("=")
            value = self.parse_expression()
            self.take(";")
            return ("assign", name, value)
        raise CompileError(f"unsupported statement starting with {token!r}")

    def parse_expression(self) -> Node:
        expression = self.parse_unary()
        while self.peek() in ("+", "-"):
            operator = self.take()
            expression = ("binary", operator, expression, self.parse_unary())
        return expression

    def parse_unary(self) -> Node:
        if self.peek() == "-":
            self.take("-")
            return ("negate", self.parse_unary())
        if self.peek() == "+":
            self.take("+")
            return self.parse_unary()
        return self.parse_primary()

    def parse_primary(self) -> Node:
        token = self.take()
        if token == "(":
            expression = self.parse_expression()
            self.take(")")
            return expression
        if token.startswith("'"):
            value = token[1:-1]
            escapes = {"n": 10, "r": 13, "t": 9, "0": 0, "\\": 92, "'": 39}
            if value.startswith("\\"):
                if value[1:] not in escapes:
                    raise CompileError(f"unsupported character escape: {token}")
                number = escapes[value[1:]]
            else:
                number = ord(value)
            return ("number", number)
        if re.fullmatch(r"0[xX][0-9A-Fa-f]+|[0-9]+", token):
            number = int(token, 16) if token.lower().startswith("0x") else int(token)
            if number > 0xFFFF:
                raise CompileError(f"integer does not fit in 16 bits: {token}")
            return ("number", number)
        if re.fullmatch(r"[A-Za-z_]\w*", token):
            if token not in self.locals:
                raise CompileError(f"unknown local variable: {token}")
            return ("variable", token)
        raise CompileError(f"expected an expression, found {token!r}")


class CodeGenerator:
    def __init__(self, locals_: dict[str, int]):
        self.locals = locals_
        self.code = bytearray()

    def emit(self, *values: int) -> None:
        self.code.extend(value & 0xFF for value in values)

    def emit_word(self, value: int) -> None:
        self.emit(value, value >> 8)

    def emit_expression(self, expression: Node) -> None:
        kind = expression[0]
        if kind == "number":
            self.emit(0xB8)
            self.emit_word(expression[1])
        elif kind == "variable":
            self.emit(0x8B, 0x46, -self.locals[expression[1]])
        elif kind == "negate":
            self.emit_expression(expression[1])
            self.emit(0xF7, 0xD8)
        elif kind == "binary":
            _, operator, left, right = expression
            self.emit_expression(left)
            self.emit(0x50)
            self.emit_expression(right)
            self.emit(0x89, 0xC3, 0x58)
            self.emit(0x01, 0xD8) if operator == "+" else self.emit(0x29, 0xD8)
        else:
            raise CompileError(f"internal error: unsupported expression {kind!r}")

    def emit_store(self, name: str) -> None:
        self.emit(0x89, 0x46, -self.locals[name])

    def emit_epilogue(self) -> None:
        self.emit(0x89, 0xEC, 0x5D, 0xC3)

    def emit_jump(self, opcode: int, target: int) -> None:
        displacement = target - (len(self.code) + 3)
        if not -32768 <= displacement <= 32767:
            raise CompileError("generated jump is out of range")
        self.emit(opcode)
        self.emit_word(displacement)

    def emit_statement(self, statement: Node) -> None:
        kind = statement[0]
        if kind == "block":
            for child in statement[1]:
                self.emit_statement(child)
        elif kind == "declare":
            _, name, initializer = statement
            if initializer is None:
                self.emit(0xC7, 0x46, -self.locals[name], 0, 0)
            else:
                self.emit_expression(initializer)
                self.emit_store(name)
        elif kind == "assign":
            _, name, expression = statement
            self.emit_expression(expression)
            self.emit_store(name)
        elif kind == "putchar":
            self.emit_expression(statement[1])
            self.emit(0xCD, 0x80)
        elif kind == "return":
            self.emit_expression(statement[1])
            self.emit_epilogue()
        elif kind == "while":
            _, condition, body = statement
            loop_start = len(self.code)
            self.emit_expression(condition)
            self.emit(0x09, 0xC0)  # OR AX, AX sets the zero flag for while conditions.
            exit_jump = len(self.code)
            self.emit(0x0F, 0x84, 0, 0)  # JZ exit
            self.emit_statement(body)
            self.emit_jump(0xE9, loop_start)
            displacement = len(self.code) - (exit_jump + 4)
            self.code[exit_jump + 2 : exit_jump + 4] = bytes(
                (displacement & 0xFF, (displacement >> 8) & 0xFF)
            )
        else:
            raise CompileError(f"internal error: unsupported statement {kind!r}")

    def compile(self, body: Node) -> bytes:
        local_bytes = len(self.locals) * 2
        if local_bytes > 126:
            raise CompileError("at most 63 local int variables are supported")
        self.emit(0x55, 0x89, 0xE5)  # push bp; mov bp, sp
        if local_bytes:
            self.emit(0x83, 0xEC, local_bytes)  # sub sp, local_bytes
        self.emit_statement(body)
        self.emit_epilogue()
        if len(self.code) > 4096:
            raise CompileError("generated program exceeds SDOS's 4096-byte memory")
        return bytes(self.code)


def compile_c(source: str) -> bytes:
    parser = Parser(tokenize(source))
    body = parser.parse()
    return CodeGenerator(parser.locals).compile(body)


def load_commands(program: bytes, chunk_size: int = 16) -> list[str]:
    commands = []
    for start in range(0, len(program), chunk_size):
        chunk = program[start : start + chunk_size]
        end = start + len(chunk) - 1
        commands.append(f"load {chunk.hex().upper()} {start} {end}")
    commands.append(f"run 0 {len(program) - 1}")
    return commands


def assembly_listing(program: bytes) -> str:
    instructions: list[tuple[int, bytes, str, int | None]] = []
    branch_targets: set[int] = set()
    offset = 0

    def read_byte() -> int:
        nonlocal offset
        if offset >= len(program):
            raise CompileError("truncated machine instruction")
        value = program[offset]
        offset += 1
        return value

    def read_word(signed: bool = False) -> int:
        low = read_byte()
        high = read_byte()
        value = low | (high << 8)
        if signed and value & 0x8000:
            value -= 0x10000
        return value

    def bp_operand(displacement: int) -> str:
        if displacement < 0:
            return f"[bp - {abs(displacement)}]"
        return f"[bp + {displacement}]"

    while offset < len(program):
        start = offset
        opcode = read_byte()
        target = None

        if opcode == 0x55:
            text = "push bp"
        elif opcode == 0x50:
            text = "push ax"
        elif opcode == 0x58:
            text = "pop ax"
        elif opcode == 0x5D:
            text = "pop bp"
        elif opcode == 0xC3:
            text = "ret"
        elif opcode == 0xB8:
            text = f"mov ax, 0x{read_word():04X}"
        elif opcode in (0x89, 0x8B):
            modrm = read_byte()
            if opcode == 0x89 and modrm == 0xE5:
                text = "mov bp, sp"
            elif opcode == 0x89 and modrm == 0xEC:
                text = "mov sp, bp"
            elif opcode == 0x89 and modrm == 0xC3:
                text = "mov bx, ax"
            elif opcode == 0x89 and modrm == 0x46:
                displacement = read_byte()
                if displacement & 0x80:
                    displacement -= 0x100
                text = f"mov {bp_operand(displacement)}, ax"
            elif opcode == 0x8B and modrm == 0x46:
                displacement = read_byte()
                if displacement & 0x80:
                    displacement -= 0x100
                text = f"mov ax, {bp_operand(displacement)}"
            else:
                raise CompileError(f"unsupported instruction at offset {start}: {opcode:02X} {modrm:02X}")
        elif opcode == 0x83:
            modrm = read_byte()
            immediate = read_byte()
            if modrm == 0xEC:
                text = f"sub sp, {immediate}"
            else:
                raise CompileError(f"unsupported instruction at offset {start}: 83 {modrm:02X}")
        elif opcode == 0xC7:
            modrm = read_byte()
            if modrm != 0x46:
                raise CompileError(f"unsupported instruction at offset {start}: C7 {modrm:02X}")
            displacement = read_byte()
            if displacement & 0x80:
                displacement -= 0x100
            immediate = read_word()
            text = f"mov word {bp_operand(displacement)}, 0x{immediate:04X}"
        elif opcode in (0x01, 0x29, 0x09):
            modrm = read_byte()
            if modrm != 0xD8 and not (opcode == 0x09 and modrm == 0xC0):
                raise CompileError(f"unsupported instruction at offset {start}: {opcode:02X} {modrm:02X}")
            if opcode == 0x01:
                text = "add ax, bx"
            elif opcode == 0x29:
                text = "sub ax, bx"
            else:
                text = "or ax, ax"
        elif opcode == 0xF7:
            modrm = read_byte()
            if modrm != 0xD8:
                raise CompileError(f"unsupported instruction at offset {start}: F7 {modrm:02X}")
            text = "neg ax"
        elif opcode == 0xCD:
            text = f"int 0x{read_byte():02X}"
        elif opcode == 0x0F:
            second = read_byte()
            if second != 0x84:
                raise CompileError(f"unsupported instruction at offset {start}: 0F {second:02X}")
            target = offset + 2 + read_word(signed=True)
            text = f"jz near loc_{target:04X}"
        elif opcode == 0xE9:
            target = offset + 2 + read_word(signed=True)
            text = f"jmp near loc_{target:04X}"
        else:
            raise CompileError(f"unsupported instruction at offset {start}: {opcode:02X}")

        encoded = program[start:offset]
        instructions.append((start, encoded, text, target))
        if target is not None:
            if not 0 <= target <= len(program):
                raise CompileError(f"branch at offset {start} targets outside the program")
            branch_targets.add(target)

    instruction_offsets = {start for start, _, _, _ in instructions}
    if not branch_targets.issubset(instruction_offsets | {len(program)}):
        raise CompileError("branch target does not point to an instruction boundary")

    lines = ["bits 16", "org 0", ""]
    for start, encoded, text, _ in instructions:
        if start == 0:
            lines.append("start:")
        elif start in branch_targets:
            lines.append(f"loc_{start:04X}:")
        byte_text = " ".join(f"{value:02X}" for value in encoded)
        lines.append(f"    ; {start:04X}: {byte_text}")
        lines.append(f"    {text}")
    if len(program) in branch_targets:
        lines.append(f"loc_{len(program):04X}:")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    arguments = list(argv)
    show_assembly = False
    if "-S" in arguments or "--asm" in arguments:
        show_assembly = True
        arguments = [argument for argument in arguments if argument not in ("-S", "--asm")]
    if len(arguments) != 1:
        print(f"usage: {Path(sys.argv[0]).name} [-S|--asm] source.c", file=sys.stderr)
        return 2
    source_path = Path(arguments[0])
    try:
        program = compile_c(source_path.read_text(encoding="utf-8"))
    except (OSError, CompileError) as error:
        print(f"c2hex: {error}", file=sys.stderr)
        return 1
    if show_assembly:
        try:
            print(assembly_listing(program), end="")
        except CompileError as error:
            print(f"c2hex: {error}", file=sys.stderr)
            return 1
        return 0
    for command in load_commands(program):
        print(command)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())