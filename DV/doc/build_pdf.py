#!/usr/bin/env python3
"""Render a Markdown specification to PDF.

The repository builds its design specification with pandoc, which is not
installed here, so this script does the same job with what is: it renders the
Markdown subset the specifications actually use to styled HTML, then hands the
HTML to LibreOffice for conversion.

Supported: YAML front matter, ATX headings, paragraphs, fenced code blocks,
pipe tables with pandoc-style captions, bullet and numbered lists, and the
inline forms `code`, **bold**, *italic* and [text](url). A table of contents is
generated from the headings.

Usage: build_pdf.py <source.md> [output.pdf]
"""

import html
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

CSS = """
@page { size: A4; margin: 20mm 18mm 20mm 18mm; }
body { font-family: "Liberation Serif", serif; font-size: 10.5pt;
       line-height: 1.35; color: #000000; }
h1 { font-family: "Liberation Sans", sans-serif; font-size: 17pt;
     color: #16436f; margin-top: 20pt; margin-bottom: 8pt; }
h2 { font-family: "Liberation Sans", sans-serif; font-size: 13.5pt;
     color: #1d5c99; margin-top: 15pt; margin-bottom: 6pt; }
h3 { font-family: "Liberation Sans", sans-serif; font-size: 11.5pt;
     color: #333333; margin-top: 12pt; margin-bottom: 5pt; }
p { margin-top: 0pt; margin-bottom: 7pt; text-align: justify; }
table { border-collapse: collapse; width: 100%; margin-top: 4pt;
        margin-bottom: 2pt; }
th { font-family: "Liberation Sans", sans-serif; font-size: 8.5pt;
     background-color: #dce6f0; border: 0.5pt solid #7f7f7f;
     padding: 3pt 4pt; text-align: left; vertical-align: top; }
td { font-size: 8.5pt; border: 0.5pt solid #7f7f7f; padding: 3pt 4pt;
     text-align: left; vertical-align: top; }
pre { font-family: "Liberation Mono", monospace; font-size: 8pt;
      background-color: #f4f4f4; border: 0.5pt solid #c0c0c0;
      padding: 5pt; margin-top: 4pt; margin-bottom: 8pt;
      line-height: 1.0; }
code, tt { font-family: "Liberation Mono", monospace; font-size: 9pt; }
td code, th code { font-size: 8pt; }
li { font-size: 10.5pt; margin-bottom: 3pt; }
.caption { font-size: 8.5pt; font-style: italic; color: #333333;
           margin-top: 2pt; margin-bottom: 9pt; }
.title { font-family: "Liberation Sans", sans-serif; font-size: 26pt;
         color: #16436f; margin-top: 150pt; margin-bottom: 4pt; }
.subtitle { font-family: "Liberation Sans", sans-serif; font-size: 15pt;
            color: #1d5c99; margin-bottom: 30pt; }
.docmeta { font-size: 10.5pt; color: #333333; margin-bottom: 2pt; }
.tocheading { font-family: "Liberation Sans", sans-serif; font-size: 15pt;
              color: #16436f; margin-bottom: 10pt; }
.toc1 { font-family: "Liberation Sans", sans-serif; font-size: 10.5pt;
        margin-top: 5pt; margin-bottom: 1pt; }
.toc2 { font-size: 9.5pt; margin-top: 0pt; margin-bottom: 1pt;
        margin-left: 14pt; }
"""

# LibreOffice's HTML import honours a page break only as an inline style, and
# only on a paragraph: putting one on a heading hangs the import outright, and
# so does sprinkling a dozen of them through a document this size. Two breaks
# are enough to give the front matter its own pages, and the body then flows.
PAGE_BREAK = ('<p style="page-break-before: always; font-size: 2pt; '
              'margin: 0pt">&nbsp;</p>')

INLINE_CODE = re.compile(r'`([^`]+)`')
BOLD = re.compile(r'\*\*([^*]+)\*\*')
ITALIC = re.compile(r'(?<![\w*])\*([^*\n]+)\*(?![\w*])')
LINK = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
AUTOLINK = re.compile(r'<(https?://[^>]+)>')
HEADING = re.compile(r'^(#{1,4})\s+(.*)$')
TABLE_SEP = re.compile(r'^\|[\s:|-]+\|$')
CAPTION = re.compile(r'^:\s+(.*)$')
BULLET = re.compile(r'^[-*]\s+(.*)$')
NUMBERED = re.compile(r'^(\d+)\.\s+(.*)$')


def inline(text):
    """Convert inline Markdown to HTML, protecting code spans from the rest."""
    spans = []

    def stash(match):
        spans.append(html.escape(match.group(1)))
        return f'\x00{len(spans) - 1}\x00'

    text = INLINE_CODE.sub(stash, text)
    text = html.escape(text)
    text = text.replace('---', '&#8212;')
    text = AUTOLINK.sub(r'<a href="\1">\1</a>', text)
    text = LINK.sub(r'<a href="\2">\1</a>', text)
    text = BOLD.sub(r'<b>\1</b>', text)
    text = ITALIC.sub(r'<i>\1</i>', text)
    for index, span in enumerate(spans):
        text = text.replace(f'\x00{index}\x00', f'<tt>{span}</tt>')
    return text


def split_row(line):
    return [cell.strip() for cell in line.strip().strip('|').split('|')]


def parse_front_matter(lines):
    meta = {}
    if not lines or lines[0].strip() != '---':
        return meta, lines
    for end, line in enumerate(lines[1:], start=1):
        if line.strip() == '---':
            return meta, lines[end + 1:]
        if ':' in line:
            key, value = line.split(':', 1)
            meta[key.strip()] = value.strip().strip('"')
    return meta, lines


def render(source):
    meta, lines = parse_front_matter(source.splitlines())
    body = []
    toc = []
    index = 0
    total = len(lines)

    while index < total:
        line = lines[index]

        if line.startswith('```'):
            index += 1
            block = []
            while index < total and not lines[index].startswith('```'):
                block.append(lines[index])
                index += 1
            index += 1
            body.append('<pre>' + html.escape('\n'.join(block)) + '</pre>')
            continue

        heading = HEADING.match(line)
        if heading:
            level = len(heading.group(1))
            title = heading.group(2).strip()
            if level == 1 and not body:
                body.append(PAGE_BREAK)
            if level <= 2:
                anchor = f'sec{len(toc)}'
                toc.append((level, title, anchor))
                body.append(f'<h{level}><a name="{anchor}">'
                            f'{inline(title)}</a></h{level}>')
            else:
                body.append(f'<h{level}>{inline(title)}</h{level}>')
            index += 1
            continue

        # A pipe table is a header row, a separator row, then body rows,
        # optionally followed by a pandoc caption line.
        if (line.startswith('|') and index + 1 < total
                and TABLE_SEP.match(lines[index + 1])):
            header = split_row(line)
            index += 2
            rows = []
            while index < total and lines[index].startswith('|'):
                rows.append(split_row(lines[index]))
                index += 1
            cells = ''.join(f'<th>{inline(c)}</th>' for c in header)
            # LibreOffice draws cell rules from the border attribute, not from
            # a CSS border on the cells.
            table = [f'<table border="1" cellspacing="0" cellpadding="3">'
                     f'<tr>{cells}</tr>']
            for row in rows:
                cells = ''.join(f'<td>{inline(c)}</td>' for c in row)
                table.append(f'<tr>{cells}</tr>')
            table.append('</table>')
            body.append(''.join(table))
            while index < total and not lines[index].strip():
                index += 1
            caption = CAPTION.match(lines[index]) if index < total else None
            if caption:
                body.append(f'<p class="caption">{inline(caption.group(1))}</p>')
                index += 1
            continue

        if BULLET.match(line) or NUMBERED.match(line):
            ordered = NUMBERED.match(line) is not None
            items = []
            while index < total:
                match = (NUMBERED.match(lines[index]) if ordered
                         else BULLET.match(lines[index]))
                if match:
                    items.append(match.group(2) if ordered else match.group(1))
                    index += 1
                elif (lines[index].startswith('  ') and lines[index].strip()
                      and items):
                    items[-1] += ' ' + lines[index].strip()
                    index += 1
                else:
                    break
            tag = 'ol' if ordered else 'ul'
            entries = ''.join(f'<li>{inline(i)}</li>' for i in items)
            body.append(f'<{tag}>{entries}</{tag}>')
            continue

        if not line.strip():
            index += 1
            continue

        paragraph = [line.strip()]
        index += 1
        while index < total and lines[index].strip():
            nxt = lines[index]
            if (HEADING.match(nxt) or nxt.startswith('```')
                    or nxt.startswith('|') or BULLET.match(nxt)
                    or NUMBERED.match(nxt) or CAPTION.match(nxt)):
                break
            paragraph.append(nxt.strip())
            index += 1
        body.append(f'<p>{inline(" ".join(paragraph))}</p>')

    title_page = [
        f'<p class="title">{inline(meta.get("title", ""))}</p>',
        f'<p class="subtitle">{inline(meta.get("subtitle", ""))}</p>',
    ]
    for key in ('author', 'date'):
        if meta.get(key):
            title_page.append(f'<p class="docmeta">{inline(meta[key])}</p>')

    contents = [PAGE_BREAK,
                f'<p class="tocheading">'
                f'{meta.get("toc-title", "Contents")}</p>']
    for level, title, anchor in toc:
        contents.append(f'<p class="toc{level}">'
                        f'<a href="#{anchor}">{inline(title)}</a></p>')

    return (f'<html><head><meta charset="utf-8">'
            f'<title>{html.escape(meta.get("title", ""))}</title>'
            f'<style>{CSS}</style></head><body>'
            + ''.join(title_page)
            + ''.join(contents)
            + ''.join(body)
            + '</body></html>')


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    source = Path(sys.argv[1])
    output = Path(sys.argv[2]) if len(sys.argv) > 2 \
        else source.with_suffix('.pdf')

    soffice = shutil.which('soffice') or shutil.which('libreoffice')
    if soffice is None:
        sys.exit('neither soffice nor libreoffice is on PATH')

    markup = render(source.read_text())

    # LibreOffice writes the PDF beside the input and needs a private profile
    # so a headless run cannot collide with an interactive one.
    with tempfile.TemporaryDirectory() as scratch:
        scratch = Path(scratch)
        page = scratch / (source.stem + '.html')
        page.write_text(markup)
        subprocess.run(
            [soffice, '--headless', '--norestore',
             f'-env:UserInstallation=file://{scratch / "profile"}',
             '--convert-to', 'pdf', '--outdir', str(scratch), str(page)],
            check=True, stdout=subprocess.DEVNULL)
        produced = scratch / (source.stem + '.pdf')
        if not produced.exists():
            sys.exit('LibreOffice produced no PDF')
        output.write_bytes(produced.read_bytes())

    print(f'{output} ({output.stat().st_size // 1024} KiB)')


if __name__ == '__main__':
    main()
