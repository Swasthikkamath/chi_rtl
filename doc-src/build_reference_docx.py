#!/usr/bin/env python3
"""Build the pandoc reference document used to style the design specification.

The house style being reproduced is the one used by the DMA-350 verification
architecture document: A4, Times New Roman body text set justified, chapter
openings that carry the chapter number on its own line above a centred
upper-case title, Courier New code in a boxed and shaded block, thin blue-grey
table rules with a shaded header row, 9pt centred captions below the object they
describe, and a two-line footer holding the project name and the page number.

Only the layout is taken from that document. No text, table or figure from it
appears here.

The script starts from pandoc's own default reference document so that every
style name pandoc emits keeps existing, and replaces the definitions that carry
visual formatting. Run it through `make reference` after changing anything here.
"""

import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

# Page geometry, in twentieths of a point. A4 with a 2cm left margin, a 1.65cm
# right margin and room at the foot of the page for the two footer lines.
PAGE_W = 11906
PAGE_H = 16838
MARGIN_TOP = 1134
MARGIN_BOTTOM = 1418
MARGIN_LEFT = 1134
MARGIN_RIGHT = 935
FOOTER_DIST = 709

# Half the text column, used as the centring tab stop inside chapter headings.
CENTRE_TAB = (PAGE_W - MARGIN_LEFT - MARGIN_RIGHT) // 2

BODY_FONT = "Times New Roman"
CODE_FONT = "Courier New"

# Sizes in half-points.
SZ_BODY = 22  # 11pt
SZ_SMALL = 18  # 9pt, used by tables, captions and code
SZ_H1 = 30  # 15pt, the upper-case chapter title
SZ_CHAPTER_LABEL = 40  # 20pt, the "Chapter N" line above it
SZ_H2 = 26  # 13pt
SZ_H3 = 24  # 12pt
SZ_TITLE = 44  # 22pt
SZ_SUBTITLE = 28  # 14pt

RULE_COLOR = "8EAADB"
HEADER_FILL = "D9E2F3"
CODE_FILL = "F4F7FB"
CODE_RULE = "C5D3E8"

FOOTER_NAME = "CHI_INTERCONNECT_RTL"

FONTS = (
    f'<w:rFonts w:ascii="{BODY_FONT}" w:eastAsia="{BODY_FONT}" '
    f'w:hAnsi="{BODY_FONT}" w:cs="{BODY_FONT}"/>'
)

DOC_DEFAULTS = f"""<w:docDefaults>
    <w:rPrDefault>
      <w:rPr>
        {FONTS}
        <w:sz w:val="{SZ_BODY}"/>
        <w:szCs w:val="{SZ_BODY}"/>
        <w:lang w:val="en-GB" w:eastAsia="en-GB" w:bidi="ar-SA"/>
      </w:rPr>
    </w:rPrDefault>
    <w:pPrDefault>
      <w:pPr>
        <w:spacing w:after="0" w:line="240" w:lineRule="auto"/>
      </w:pPr>
    </w:pPrDefault>
  </w:docDefaults>"""

# Style definitions keyed by styleId. Each value is the complete replacement
# element, so the visual result does not depend on what pandoc shipped.
STYLES = {
    "Normal": f"""<w:style w:type="paragraph" w:default="1" w:styleId="Normal">
    <w:name w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:jc w:val="both"/>
      <w:spacing w:after="0" w:line="240" w:lineRule="auto"/>
    </w:pPr>
  </w:style>""",
    "BodyText": f"""<w:style w:type="paragraph" w:styleId="BodyText">
    <w:name w:val="Body Text"/>
    <w:basedOn w:val="Normal"/>
    <w:link w:val="BodyTextChar"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="140" w:after="0"/>
      <w:jc w:val="both"/>
    </w:pPr>
  </w:style>""",
    # All of the space sits before the paragraph, so that a paragraph which
    # follows a list or a code block is separated from it even though neither
    # of those carries space of its own.
    "FirstParagraph": """<w:style w:type="paragraph" w:customStyle="1" w:styleId="FirstParagraph">
    <w:name w:val="First Paragraph"/>
    <w:basedOn w:val="BodyText"/>
    <w:next w:val="BodyText"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="0" w:after="0"/>
    </w:pPr>
  </w:style>""",
    # Compact carries both tight list items and every table cell, so it must not
    # name a font size of its own: cells take 9pt from the table style and list
    # items take 11pt from the document defaults.
    "Compact": """<w:style w:type="paragraph" w:customStyle="1" w:styleId="Compact">
    <w:name w:val="Compact"/>
    <w:basedOn w:val="BodyText"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="20" w:after="20"/>
      <w:jc w:val="left"/>
    </w:pPr>
  </w:style>""",
    "Heading1": f"""<w:style w:type="paragraph" w:styleId="Heading1">
    <w:name w:val="Heading 1"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:uiPriority w:val="9"/>
    <w:qFormat/>
    <w:pPr>
      <w:pageBreakBefore/>
      <w:keepNext/>
      <w:keepLines/>
      <w:tabs>
        <w:tab w:val="center" w:pos="{CENTRE_TAB}"/>
      </w:tabs>
      <w:spacing w:before="240" w:after="320" w:line="360" w:lineRule="auto"/>
      <w:jc w:val="left"/>
      <w:outlineLvl w:val="0"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:b/>
      <w:bCs/>
      <w:color w:val="000000"/>
      <w:sz w:val="{SZ_H1}"/>
      <w:szCs w:val="{SZ_H1}"/>
    </w:rPr>
  </w:style>""",
    "Heading2": f"""<w:style w:type="paragraph" w:styleId="Heading2">
    <w:name w:val="Heading 2"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:uiPriority w:val="9"/>
    <w:qFormat/>
    <w:pPr>
      <w:keepNext/>
      <w:keepLines/>
      <w:spacing w:before="280" w:after="120"/>
      <w:jc w:val="left"/>
      <w:outlineLvl w:val="1"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:b/>
      <w:bCs/>
      <w:color w:val="000000"/>
      <w:sz w:val="{SZ_H2}"/>
      <w:szCs w:val="{SZ_H2}"/>
    </w:rPr>
  </w:style>""",
    "Heading3": f"""<w:style w:type="paragraph" w:styleId="Heading3">
    <w:name w:val="Heading 3"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:uiPriority w:val="9"/>
    <w:qFormat/>
    <w:pPr>
      <w:keepNext/>
      <w:keepLines/>
      <w:spacing w:before="240" w:after="100"/>
      <w:jc w:val="left"/>
      <w:outlineLvl w:val="2"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:b/>
      <w:bCs/>
      <w:color w:val="000000"/>
      <w:sz w:val="{SZ_H3}"/>
      <w:szCs w:val="{SZ_H3}"/>
    </w:rPr>
  </w:style>""",
    "Heading4": f"""<w:style w:type="paragraph" w:styleId="Heading4">
    <w:name w:val="Heading 4"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:uiPriority w:val="9"/>
    <w:qFormat/>
    <w:pPr>
      <w:keepNext/>
      <w:keepLines/>
      <w:spacing w:before="200" w:after="80"/>
      <w:jc w:val="left"/>
      <w:outlineLvl w:val="3"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:b/>
      <w:i/>
      <w:color w:val="000000"/>
      <w:sz w:val="{SZ_BODY}"/>
      <w:szCs w:val="{SZ_BODY}"/>
    </w:rPr>
  </w:style>""",
    "TOCHeading": f"""<w:style w:type="paragraph" w:styleId="TOCHeading">
    <w:name w:val="TOC Heading"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:uiPriority w:val="39"/>
    <w:qFormat/>
    <w:pPr>
      <w:pageBreakBefore/>
      <w:keepNext/>
      <w:spacing w:before="0" w:after="240"/>
      <w:jc w:val="left"/>
      <w:outlineLvl w:val="9"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:b/>
      <w:color w:val="000000"/>
      <w:sz w:val="{SZ_H1}"/>
      <w:szCs w:val="{SZ_H1}"/>
    </w:rPr>
  </w:style>""",
    "Title": f"""<w:style w:type="paragraph" w:styleId="Title">
    <w:name w:val="Title"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:qFormat/>
    <w:pPr>
      <w:keepNext/>
      <w:spacing w:before="3600" w:after="240"/>
      <w:jc w:val="center"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:b/>
      <w:caps/>
      <w:color w:val="000000"/>
      <w:sz w:val="{SZ_TITLE}"/>
      <w:szCs w:val="{SZ_TITLE}"/>
    </w:rPr>
  </w:style>""",
    "Subtitle": f"""<w:style w:type="paragraph" w:styleId="Subtitle">
    <w:name w:val="Subtitle"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:qFormat/>
    <w:pPr>
      <w:keepNext/>
      <w:spacing w:before="120" w:after="240"/>
      <w:jc w:val="center"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:color w:val="000000"/>
      <w:sz w:val="{SZ_SUBTITLE}"/>
      <w:szCs w:val="{SZ_SUBTITLE}"/>
    </w:rPr>
  </w:style>""",
    "Author": f"""<w:style w:type="paragraph" w:customStyle="1" w:styleId="Author">
    <w:name w:val="Author"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:qFormat/>
    <w:pPr>
      <w:keepNext/>
      <w:spacing w:before="0" w:after="80"/>
      <w:jc w:val="center"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:sz w:val="{SZ_BODY}"/>
    </w:rPr>
  </w:style>""",
    "Date": f"""<w:style w:type="paragraph" w:customStyle="1" w:styleId="Date">
    <w:name w:val="Date"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="BodyText"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="0" w:after="80"/>
      <w:jc w:val="center"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:sz w:val="{SZ_BODY}"/>
    </w:rPr>
  </w:style>""",
    "Caption": f"""<w:style w:type="paragraph" w:styleId="Caption">
    <w:name w:val="Caption"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="80" w:after="240"/>
      <w:jc w:val="center"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:sz w:val="{SZ_SMALL}"/>
      <w:szCs w:val="{SZ_SMALL}"/>
    </w:rPr>
  </w:style>""",
    # Captions sit below the object they name, so they must not be glued to the
    # paragraph that follows them.
    "TableCaption": """<w:style w:type="paragraph" w:customStyle="1" w:styleId="TableCaption">
    <w:name w:val="Table Caption"/>
    <w:basedOn w:val="Caption"/>
    <w:next w:val="BodyText"/>
    <w:qFormat/>
  </w:style>""",
    "ImageCaption": """<w:style w:type="paragraph" w:customStyle="1" w:styleId="ImageCaption">
    <w:name w:val="Image Caption"/>
    <w:basedOn w:val="Caption"/>
    <w:next w:val="BodyText"/>
    <w:qFormat/>
  </w:style>""",
    "Figure": """<w:style w:type="paragraph" w:customStyle="1" w:styleId="Figure">
    <w:name w:val="Figure"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="160" w:after="0"/>
      <w:jc w:val="center"/>
    </w:pPr>
  </w:style>""",
    "CaptionedFigure": """<w:style w:type="paragraph" w:customStyle="1" w:styleId="CaptionedFigure">
    <w:name w:val="Captioned Figure"/>
    <w:basedOn w:val="Figure"/>
    <w:pPr>
      <w:keepNext/>
    </w:pPr>
  </w:style>""",
    "VerbatimChar": f"""<w:style w:type="character" w:customStyle="1" w:styleId="VerbatimChar">
    <w:name w:val="Verbatim Char"/>
    <w:basedOn w:val="DefaultParagraphFont"/>
    <w:rPr>
      <w:rFonts w:ascii="{CODE_FONT}" w:hAnsi="{CODE_FONT}" w:cs="{CODE_FONT}"/>
      <w:sz w:val="{SZ_SMALL}"/>
      <w:szCs w:val="{SZ_SMALL}"/>
    </w:rPr>
  </w:style>""",
    "BlockText": """<w:style w:type="paragraph" w:styleId="BlockText">
    <w:name w:val="Block Text"/>
    <w:basedOn w:val="BodyText"/>
    <w:next w:val="BodyText"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="120" w:after="120"/>
      <w:ind w:left="340" w:right="340"/>
    </w:pPr>
  </w:style>""",
    # Tables name their own size so that the 9pt of a cell does not leak into
    # the tight lists that share the Compact paragraph style.
    "Table": f"""<w:style w:type="table" w:default="1" w:styleId="Table">
    <w:name w:val="Table"/>
    <w:basedOn w:val="TableNormal"/>
    <w:qFormat/>
    <w:pPr>
      <w:spacing w:before="20" w:after="20"/>
      <w:jc w:val="left"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:sz w:val="{SZ_SMALL}"/>
      <w:szCs w:val="{SZ_SMALL}"/>
    </w:rPr>
    <w:tblPr>
      <w:tblInd w:w="0" w:type="dxa"/>
      <w:tblBorders>
        <w:top w:val="single" w:sz="4" w:space="0" w:color="{RULE_COLOR}"/>
        <w:left w:val="single" w:sz="4" w:space="0" w:color="{RULE_COLOR}"/>
        <w:bottom w:val="single" w:sz="4" w:space="0" w:color="{RULE_COLOR}"/>
        <w:right w:val="single" w:sz="4" w:space="0" w:color="{RULE_COLOR}"/>
        <w:insideH w:val="single" w:sz="4" w:space="0" w:color="{RULE_COLOR}"/>
        <w:insideV w:val="single" w:sz="4" w:space="0" w:color="{RULE_COLOR}"/>
      </w:tblBorders>
      <w:tblCellMar>
        <w:top w:w="60" w:type="dxa"/>
        <w:left w:w="108" w:type="dxa"/>
        <w:bottom w:w="60" w:type="dxa"/>
        <w:right w:w="108" w:type="dxa"/>
      </w:tblCellMar>
    </w:tblPr>
    <w:tblStylePr w:type="firstRow">
      <w:rPr>
        <w:b/>
        <w:bCs/>
      </w:rPr>
      <w:tcPr>
        <w:shd w:val="clear" w:color="auto" w:fill="{HEADER_FILL}"/>
        <w:vAlign w:val="center"/>
      </w:tcPr>
    </w:tblStylePr>
  </w:style>""",
}

# Styles pandoc's default reference document does not define.
EXTRA_STYLES = f"""<w:style w:type="character" w:customStyle="1" w:styleId="ChapterLabel">
    <w:name w:val="Chapter Label"/>
    <w:basedOn w:val="DefaultParagraphFont"/>
    <w:qFormat/>
    <w:rPr>
      {FONTS}
      <w:b w:val="0"/>
      <w:bCs w:val="0"/>
      <w:caps w:val="0"/>
      <w:sz w:val="{SZ_CHAPTER_LABEL}"/>
      <w:szCs w:val="{SZ_CHAPTER_LABEL}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Footer">
    <w:name w:val="footer"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="0" w:after="0"/>
      <w:jc w:val="center"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:sz w:val="{SZ_BODY}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="Header">
    <w:name w:val="header"/>
    <w:basedOn w:val="Normal"/>
    <w:pPr>
      <w:spacing w:before="0" w:after="0"/>
      <w:jc w:val="center"/>
    </w:pPr>
  </w:style>
  <w:style w:type="paragraph" w:customStyle="1" w:styleId="SourceCode">
    <w:name w:val="Source Code"/>
    <w:basedOn w:val="Normal"/>
    <w:qFormat/>
    <w:pPr>
      <w:keepLines/>
      <w:pBdr>
        <w:top w:val="single" w:sz="4" w:space="6" w:color="{CODE_RULE}"/>
        <w:left w:val="single" w:sz="4" w:space="6" w:color="{CODE_RULE}"/>
        <w:bottom w:val="single" w:sz="4" w:space="6" w:color="{CODE_RULE}"/>
        <w:right w:val="single" w:sz="4" w:space="6" w:color="{CODE_RULE}"/>
      </w:pBdr>
      <w:shd w:val="clear" w:color="auto" w:fill="{CODE_FILL}"/>
      <w:spacing w:before="160" w:after="160" w:line="240" w:lineRule="auto"/>
      <w:ind w:left="113" w:right="113"/>
      <w:jc w:val="left"/>
    </w:pPr>
    <w:rPr>
      <w:rFonts w:ascii="{CODE_FONT}" w:hAnsi="{CODE_FONT}" w:cs="{CODE_FONT}"/>
      <w:sz w:val="{SZ_SMALL}"/>
      <w:szCs w:val="{SZ_SMALL}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="TOC1">
    <w:name w:val="toc 1"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:pPr>
      <w:tabs>
        <w:tab w:val="right" w:leader="underscore" w:pos="{PAGE_W - MARGIN_LEFT - MARGIN_RIGHT}"/>
      </w:tabs>
      <w:spacing w:before="60" w:after="0"/>
      <w:jc w:val="left"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:sz w:val="{SZ_BODY}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="TOC2">
    <w:name w:val="toc 2"/>
    <w:basedOn w:val="Normal"/>
    <w:next w:val="Normal"/>
    <w:pPr>
      <w:tabs>
        <w:tab w:val="right" w:leader="underscore" w:pos="{PAGE_W - MARGIN_LEFT - MARGIN_RIGHT}"/>
      </w:tabs>
      <w:spacing w:before="20" w:after="0"/>
      <w:ind w:left="283"/>
      <w:jc w:val="left"/>
    </w:pPr>
    <w:rPr>
      {FONTS}
      <w:sz w:val="{SZ_SMALL}"/>
    </w:rPr>
  </w:style>
  <w:style w:type="paragraph" w:styleId="TOC3">
    <w:name w:val="toc 3"/>
    <w:basedOn w:val="TOC2"/>
    <w:next w:val="Normal"/>
    <w:pPr>
      <w:ind w:left="566"/>
    </w:pPr>
  </w:style>"""

SECT_PR = f"""<w:sectPr>
      <w:footerReference w:type="default" r:id="rIdFooterChi"/>
      <w:pgSz w:w="{PAGE_W}" w:h="{PAGE_H}"/>
      <w:pgMar w:top="{MARGIN_TOP}" w:right="{MARGIN_RIGHT}" w:bottom="{MARGIN_BOTTOM}"
               w:left="{MARGIN_LEFT}" w:header="709" w:footer="{FOOTER_DIST}" w:gutter="0"/>
      <w:cols w:space="708"/>
      <w:docGrid w:linePitch="360"/>
    </w:sectPr>"""

FOOTER_XML = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:ftr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
       xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:p>
    <w:pPr><w:pStyle w:val="Footer"/></w:pPr>
    <w:r><w:t>{FOOTER_NAME}</w:t></w:r>
  </w:p>
  <w:p>
    <w:pPr><w:pStyle w:val="Footer"/></w:pPr>
    <w:r><w:fldChar w:fldCharType="begin"/></w:r>
    <w:r><w:instrText xml:space="preserve"> PAGE </w:instrText></w:r>
    <w:r><w:fldChar w:fldCharType="separate"/></w:r>
    <w:r><w:t>1</w:t></w:r>
    <w:r><w:fldChar w:fldCharType="end"/></w:r>
  </w:p>
</w:ftr>
"""

FOOTER_REL_ID = "rIdFooterChi"


def patch_styles(xml: str) -> str:
    xml = re.sub(r"<w:docDefaults>.*?</w:docDefaults>", DOC_DEFAULTS, xml, flags=re.S)
    for style_id, replacement in STYLES.items():
        pattern = r'<w:style [^>]*w:styleId="%s">.*?</w:style>' % style_id
        xml, count = re.subn(pattern, replacement, xml, flags=re.S)
        if count != 1:
            raise SystemExit(f"style {style_id}: expected 1 definition, found {count}")
    return xml.replace("</w:styles>", f"  {EXTRA_STYLES}\n</w:styles>")


def patch_document(xml: str) -> str:
    xml, count = re.subn(r"<w:sectPr\s*/>", SECT_PR, xml)
    if count != 1:
        raise SystemExit(f"document: expected 1 empty sectPr, found {count}")
    return xml


def patch_rels(xml: str) -> str:
    rel = (
        f'<Relationship Id="{FOOTER_REL_ID}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/'
        'relationships/footer" Target="footer1.xml"/>'
    )
    return xml.replace("</Relationships>", rel + "</Relationships>")


def patch_content_types(xml: str) -> str:
    override = (
        '<Override PartName="/word/footer1.xml" ContentType="application/'
        'vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"/>'
    )
    return xml.replace("</Types>", override + "</Types>")


PATCHERS = {
    "word/styles.xml": patch_styles,
    "word/document.xml": patch_document,
    "word/_rels/document.xml.rels": patch_rels,
    "[Content_Types].xml": patch_content_types,
}


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "doc-src/reference.docx")
    pandoc = shutil.which("pandoc")
    if pandoc is None:
        raise SystemExit("pandoc not found")

    base = subprocess.run(
        [pandoc, "--print-default-data-file", "reference.docx"],
        check=True,
        capture_output=True,
    ).stdout
    scratch = out.with_suffix(".base.docx")
    scratch.write_bytes(base)

    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        with zipfile.ZipFile(scratch) as src:
            names = src.namelist()
            with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as dst:
                for name in names:
                    data = src.read(name)
                    patcher = PATCHERS.get(name)
                    if patcher is not None:
                        data = patcher(data.decode("utf-8")).encode("utf-8")
                    dst.writestr(name, data)
                dst.writestr("word/footer1.xml", FOOTER_XML)
    finally:
        scratch.unlink(missing_ok=True)

    missing = set(PATCHERS) - set(names)
    if missing:
        raise SystemExit(f"reference document is missing {sorted(missing)}")
    print(f"wrote {out} ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
