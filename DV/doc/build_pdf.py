#!/usr/bin/env python3
"""Write a PDF of the DV spec and the traceability table.

No third-party PDF library. The page stream is plain Helvetica text.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
SOURCES = [ROOT / "dv-spec.md", ROOT / "traceability.md"]
OUTPUT = ROOT / "chi-dv-spec.pdf"

PAGE_W = 612
PAGE_H = 792
MARGIN = 54
FONT_SIZE = 9
LEADING = 12
CHARS = 84


def escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def wrap(text: str) -> list[str]:
    text = text.replace("\t", "    ")
    if text == "":
        return [""]
    lines = []
    while len(text) > CHARS:
        cut = text.rfind(" ", 0, CHARS)
        if cut < 1:
            cut = CHARS
        lines.append(text[:cut])
        text = text[cut:].lstrip()
    lines.append(text)
    return lines


def pages_of(lines: list[str]) -> list[list[str]]:
    capacity = int((PAGE_H - 2 * MARGIN) / LEADING)
    pages = []
    for start in range(0, len(lines), capacity):
        pages.append(lines[start:start + capacity])
    return pages or [[""]]


def page_stream(lines: list[str]) -> bytes:
    commands = [f"BT /F1 {FONT_SIZE} Tf {LEADING} TL {MARGIN} {PAGE_H - MARGIN} Td"]
    for index, line in enumerate(lines):
        if index:
            commands.append("T*")
        commands.append(f"({escape(line)}) Tj")
    commands.append("ET")
    return ("\n".join(commands) + "\n").encode("latin-1", "replace")


def build() -> None:
    lines = []
    for path in SOURCES:
        lines.append(path.name)
        lines.append("")
        for raw in path.read_text(encoding="utf-8").splitlines():
            lines.extend(wrap(raw))
        lines.append("")
    page_lines = pages_of(lines)
    streams = [page_stream(page) for page in page_lines]

    objects: list[bytes] = []
    objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
    kids = " ".join(f"{3 + 2 * i} 0 R" for i in range(len(streams)))
    objects.append(
        f"<< /Type /Pages /Count {len(streams)} /Kids [{kids}] >>".encode()
    )
    for index, stream in enumerate(streams):
        objects.append(
            (
                f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {PAGE_W} {PAGE_H}] "
                f"/Contents {4 + 2 * index} 0 R /Resources << /Font << /F1 "
                f"{3 + 2 * len(streams)} 0 R >> >> >>"
            ).encode()
        )
        objects.append(f"<< /Length {len(stream)} >>\nstream\n".encode() + stream + b"endstream")
    objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    out = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode()
    out += b"0000000000 65535 f \n"
    for offset in offsets[1:]:
        out += f"{offset:010d} 00000 n \n".encode()
    out += (
        f"trailer << /Size {len(objects) + 1} /Root 1 0 R >>\n"
        f"startxref\n{xref}\n%%EOF\n"
    ).encode()
    OUTPUT.write_bytes(out)
    print(f"wrote {OUTPUT} ({len(page_lines)} pages)")


if __name__ == "__main__":
    build()
