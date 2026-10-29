#!/usr/bin/env python3
"""Finish the Word file pandoc writes, for the parts of the house style that a
reference document cannot carry.

1. The cover. doc-src/cover.png is anchored at the page corner, at full A4
   size, in a header used on the first page only. Word draws a header beneath
   the page's text, so the document's own title block sits over the cover.
   The picture is not marked "behind text": some viewers, the macOS preview
   among them, wash such pictures out.
2. Bullets. Pandoc writes its own bullet definitions, in the Symbol font. The
   house style uses a filled circle for the first level, an open circle for
   the second and a square for the third, in Arial.
3. Tables. Every table gets its black one-point grid, its cell padding and a
   bold header row as direct formatting, its cells the 9pt Table Text
   paragraph style, and its columns are scaled to the full text width. The reference document's table style says the same, but
   some viewers ignore a table style's borders and its header-row formatting,
   and pandoc sizes columns for a narrower page than this one.

Usage: finish_docx.py <docx> <cover.png>

The file is rewritten in place. Running it twice changes nothing more.
"""

import re
import sys
import zipfile
from pathlib import Path

# A4 in EMU (914400 per inch).
PAGE_EMU_W = 7560310
PAGE_EMU_H = 10692130

COVER_REL_ID = "rIdHouseCover"
COVER_PART = "media/house_cover.png"
COVER_HEADER = "header_cover.xml"
COVER_HEADER_REL_ID = "rIdHouseCoverHeader"

BULLET_GLYPHS = ("●", "○", "■")  # filled circle, open circle, square
BULLET_FONT = "Arial"

COVER_RUN = f"""<w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="0" behindDoc="0" locked="1" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionH><wp:positionV relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionV><wp:extent cx="{PAGE_EMU_W}" cy="{PAGE_EMU_H}"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapNone/><wp:docPr id="90001" name="Cover"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="90001" name="cover.png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="{COVER_REL_ID}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{PAGE_EMU_W}" cy="{PAGE_EMU_H}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r>"""


COVER_HEADER_XML = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">'
    f'<w:p><w:pPr><w:pStyle w:val="Header"/></w:pPr>{COVER_RUN}</w:p></w:hdr>'
)

COVER_HEADER_RELS = (
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    f'<Relationship Id="{COVER_REL_ID}" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
    f'Target="{COVER_PART}"/></Relationships>'
)


def add_cover_header(document: str) -> str:
    """Name the cover header as the first-page header of the last section."""
    if "<w:titlePg" not in document:
        raise SystemExit("the reference document must give the first page its own header")
    sect = document.rfind("<w:sectPr")
    if sect < 0:
        raise SystemExit("no section properties to give the cover header to")
    end = document.index(">", sect) + 1
    ref = f'<w:headerReference w:type="first" r:id="{COVER_HEADER_REL_ID}"/>'
    return document[:end] + ref + document[end:]


def add_cover_relationship(rels: str) -> str:
    rel = (
        f'<Relationship Id="{COVER_HEADER_REL_ID}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        f'relationships/header" Target="{COVER_HEADER}"/>'
    )
    return rels.replace("</Relationships>", rel + "</Relationships>")


def add_cover_content_type(types: str) -> str:
    override = (
        f'<Override PartName="/word/{COVER_PART}" ContentType="image/png"/>'
        f'<Override PartName="/word/{COVER_HEADER}" ContentType="application/'
        'vnd.openxmlformats-officedocument.wordprocessingml.header+xml"/>'
    )
    return types.replace("</Types>", override + "</Types>")


TABLE_RULE = '<w:{side} w:val="single" w:sz="8" w:space="0" w:color="000000"/>'
TABLE_BORDERS = "<w:tblBorders>" + "".join(
    TABLE_RULE.format(side=side) for side in ("top", "left", "bottom", "right", "insideH", "insideV")
) + "</w:tblBorders>"
TABLE_CELL_MARGINS = (
    '<w:tblCellMar><w:top w:w="80" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>'
    '<w:bottom w:w="80" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar>'
)


def text_width(document: str) -> int:
    """The text column of the document's last section, in twentieths of a point."""
    width = int(re.findall(r'<w:pgSz [^>]*w:w="(\d+)"', document)[-1])
    margins = re.findall(r"<w:pgMar [^>]*>", document)[-1]
    left = int(re.search(r'w:left="(\d+)"', margins).group(1))
    right = int(re.search(r'w:right="(\d+)"', margins).group(1))
    return width - left - right


def rule_tables(document: str) -> str:
    """Give every table the house grid, padding, width and bold header."""
    width = text_width(document)

    def bold_runs(row: str) -> str:
        def run(match: re.Match) -> str:
            props = match.group(1)
            if props is None:
                return "<w:r><w:rPr><w:b/><w:bCs/></w:rPr>"
            if "<w:b/>" in props or "<w:b />" in props:
                return match.group(0)
            # Schema order in rPr: rStyle, then rFonts, then b and bCs.
            lead = re.match(r"(?:<w:rStyle [^>]*/>)?(?:<w:rFonts [^>]*/>)?", props).group(0)
            return f"<w:r><w:rPr>{lead}<w:b/><w:bCs/>{props[len(lead):]}</w:rPr>"

        return re.sub(r"<w:r>(?:<w:rPr>(.*?)</w:rPr>)?", run, row, flags=re.S)

    def table(match: re.Match) -> str:
        tbl = match.group(0)
        if "<w:tblBorders>" in tbl.split("</w:tblPr>", 1)[0]:
            return tbl
        # Schema order in tblPr: tblW comes before tblBorders, tblLayout
        # before tblCellMar.
        tbl = re.sub(r"(<w:tblW [^>]*/>)", r"\1" + TABLE_BORDERS, tbl, count=1)
        if re.search(r"<w:tblLayout [^>]*/>", tbl):
            tbl = re.sub(r"(<w:tblLayout [^>]*/>)", r"\1" + TABLE_CELL_MARGINS, tbl, count=1)
        else:
            tbl = tbl.replace("</w:tblBorders>", "</w:tblBorders>" + TABLE_CELL_MARGINS, 1)
        cols = [int(w) for w in re.findall(r'<w:gridCol w:w="(\d+)"\s*/>', tbl)]
        if cols and sum(cols) > 0:
            scaled = [round(w * width / sum(cols)) for w in cols]
            scaled[-1] += width - sum(scaled)
            grid = "".join(f'<w:gridCol w:w="{w}"/>' for w in scaled)
            tbl = re.sub(r"<w:tblGrid>.*?</w:tblGrid>", f"<w:tblGrid>{grid}</w:tblGrid>", tbl, count=1, flags=re.S)

            # Each cell names its width too, for viewers that size columns from
            # the cells rather than the grid. Rows with merged cells are left
            # to the grid.
            def row_widths(row: re.Match) -> str:
                cells = re.findall(r"<w:tcPr\s*/>|<w:tcPr>.*?</w:tcPr>", row.group(0), flags=re.S)
                if len(cells) != len(scaled) or "gridSpan" in row.group(0):
                    return row.group(0)
                widths = iter(scaled)

                def cell(props: re.Match) -> str:
                    tcw = f'<w:tcW w:w="{next(widths)}" w:type="dxa"/>'
                    body = props.group(0)
                    if body.endswith("/>"):
                        return f"<w:tcPr>{tcw}</w:tcPr>"
                    return body.replace("<w:tcPr>", "<w:tcPr>" + tcw, 1)

                return re.sub(r"<w:tcPr\s*/>|<w:tcPr>.*?</w:tcPr>", cell, row.group(0), flags=re.S)

            tbl = re.sub(r"<w:tr>.*?</w:tr>", row_widths, tbl, flags=re.S)
        tbl = re.sub(r'<w:pStyle w:val="Compact"\s*/>', '<w:pStyle w:val="TableText"/>', tbl)
        return re.sub(
            r"<w:tr>\s*<w:trPr>\s*<w:tblHeader[^>]*/>.*?</w:tr>",
            lambda row: bold_runs(row.group(0)),
            tbl,
            flags=re.S,
        )

    # Tables do not nest in this document, so the shortest match is a table.
    return re.sub(r"<w:tbl>.*?</w:tbl>", table, document, flags=re.S)


def restyle_bullets(numbering: str) -> str:
    """Give every bullet list the house glyphs, level by level."""

    def level(match: re.Match) -> str:
        lvl = match.group(0)
        depth = int(match.group(1))
        glyph = BULLET_GLYPHS[depth % len(BULLET_GLYPHS)]
        lvl = re.sub(r'<w:lvlText w:val="[^"]*"\s*/>', f'<w:lvlText w:val="{glyph}"/>', lvl)
        fonts = (
            f'<w:rPr><w:rFonts w:ascii="{BULLET_FONT}" w:hAnsi="{BULLET_FONT}" '
            f'w:cs="{BULLET_FONT}" w:hint="default"/></w:rPr>'
        )
        if "<w:rPr>" in lvl:
            lvl = re.sub(r"<w:rPr>.*?</w:rPr>", fonts, lvl, flags=re.S)
        else:
            lvl = lvl.replace("</w:lvl>", fonts + "</w:lvl>")
        return lvl

    def abstract(match: re.Match) -> str:
        body = match.group(0)
        first = re.search(r'<w:lvl w:ilvl="0".*?</w:lvl>', body, re.S)
        # Only real bullets: a marker list whose first level shows a glyph.
        # Pandoc also writes a bullet definition with a blank marker, which
        # is left alone.
        if first is None or 'w:val="bullet"' not in first.group(0):
            return body
        if re.search(r'<w:lvlText w:val="\s*"\s*/>', first.group(0)):
            return body
        return re.sub(r'<w:lvl w:ilvl="(\d+)".*?</w:lvl>', level, body, flags=re.S)

    return re.sub(r"<w:abstractNum [^>]*>.*?</w:abstractNum>", abstract, numbering, flags=re.S)


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    docx = Path(sys.argv[1])
    cover = Path(sys.argv[2]).read_bytes()
    scratch = docx.with_suffix(".finishing.docx")

    with zipfile.ZipFile(docx) as src:
        names = src.namelist()
        parts = {name: src.read(name) for name in names}
    done = f"word/{COVER_PART}" in parts

    if not done:
        parts["word/document.xml"] = add_cover_header(parts["word/document.xml"].decode("utf-8")).encode("utf-8")
        parts["word/_rels/document.xml.rels"] = add_cover_relationship(
            parts["word/_rels/document.xml.rels"].decode("utf-8")
        ).encode("utf-8")
        parts["[Content_Types].xml"] = add_cover_content_type(
            parts["[Content_Types].xml"].decode("utf-8")
        ).encode("utf-8")
        parts[f"word/{COVER_PART}"] = cover
        parts[f"word/{COVER_HEADER}"] = COVER_HEADER_XML.encode("utf-8")
        parts[f"word/_rels/{COVER_HEADER}.rels"] = COVER_HEADER_RELS.encode("utf-8")
        names += [f"word/{COVER_PART}", f"word/{COVER_HEADER}", f"word/_rels/{COVER_HEADER}.rels"]
    parts["word/document.xml"] = rule_tables(parts["word/document.xml"].decode("utf-8")).encode("utf-8")
    if "word/numbering.xml" in parts:
        parts["word/numbering.xml"] = restyle_bullets(parts["word/numbering.xml"].decode("utf-8")).encode("utf-8")

    with zipfile.ZipFile(scratch, "w", zipfile.ZIP_DEFLATED) as dst:
        for name in names:
            dst.writestr(name, parts[name])
    scratch.replace(docx)
    print(f"finished {docx}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
