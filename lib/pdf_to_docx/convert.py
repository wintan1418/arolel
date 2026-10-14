#!/usr/bin/env python3
"""PDF -> DOCX with two engines and an automatic chooser.

  flow   pdf2docx. Rebuilds paragraphs, tables and columns. Best for letters,
         invoices and reports, where the result should be ordinary editable
         Word text.
  exact  Layout-preserving. Every page keeps its size, all vector artwork and
         images are rendered as a page backdrop, and every line of text is
         placed at its PDF position as an editable, width-fitted text frame.
         Best for designed pages: sidebar resumes, letterheads, flyers,
         multi-column layouts, text over shapes.
  auto   Measures each page and picks exact when the layout is designed
         rather than written (large filled shapes, light text on dark fills,
         side-by-side columns, dense vector art), otherwise flow.

Usage: convert.py INPUT.pdf OUTPUT.docx [--mode auto|exact|flow]
Prints one JSON line on success: {"engine": "exact"|"flow", "pages": N, ...}
Exit codes: 0 ok, 2 bad input, 3 conversion failed.
"""

import io
import json
import math
import re
import sys
import zipfile
from xml.sax.saxutils import escape

try:
    import pymupdf as fitz  # PyMuPDF >= 1.24
except ImportError:  # pragma: no cover
    import fitz  # type: ignore

PT_TO_TWIP = 20
PT_TO_EMU = 12700
BACKDROP_DPI = 150
MIN_FONT_PT = 1.0

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
WP_NS = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
A_NS = "http://schemas.openxmlformats.org/drawingml/2006/main"
PIC_NS = "http://schemas.openxmlformats.org/drawingml/2006/picture"
R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

# Characters outside the XML 1.0 range make Word refuse the file.
XML_ILLEGAL = re.compile("[^\x09\x0a\x0d\x20-퟿-�\U00010000-\U0010ffff]")


# --------------------------------------------------------------------------
# Font handling
# --------------------------------------------------------------------------

SERIF_HINTS = ("times", "georgia", "garamond", "cambria", "book", "palatino", "baskerville", "minion", "serif")
MONO_HINTS = ("courier", "mono", "consolas", "menlo")
KNOWN_FAMILIES = {
    "arial": "Arial", "helvetica": "Arial", "liberationsans": "Arial", "nimbussans": "Arial", "dejavusans": "Arial",
    "calibri": "Calibri", "carlito": "Calibri", "verdana": "Verdana", "tahoma": "Tahoma", "trebuchet": "Trebuchet MS",
    "segoe": "Segoe UI", "roboto": "Arial", "opensans": "Arial", "lato": "Arial", "inter": "Arial", "montserrat": "Arial",
    "times": "Times New Roman", "liberationserif": "Times New Roman", "nimbusroman": "Times New Roman",
    "georgia": "Georgia", "garamond": "Garamond", "cambria": "Cambria", "palatino": "Palatino Linotype",
    "courier": "Courier New", "liberationmono": "Courier New", "consolas": "Consolas",
}


def font_family(raw_name, flags):
    """Map a PDF font name to a family Word is likely to have."""
    name = (raw_name or "").split("+")[-1]  # strip subset prefix ABCDEF+
    key = re.sub(r"[^a-z]", "", name.lower().split(",")[0].split("-")[0])
    for prefix, family in KNOWN_FAMILIES.items():
        if key.startswith(prefix):
            return family
    lower = name.lower()
    if flags & 8 or any(h in lower for h in MONO_HINTS):
        return "Courier New"
    if flags & 4 or any(h in lower for h in SERIF_HINTS):
        return "Times New Roman"
    return "Arial"


def measure_font(family, bold, italic):
    """Base-14 font used to estimate the width Word will render."""
    if family in ("Courier New", "Consolas"):
        base = "co"
    elif family in ("Times New Roman", "Georgia", "Garamond", "Cambria", "Palatino Linotype"):
        base = "ti"
    else:
        base = "he"
    if base == "co":
        return {"": "cour", "b": "cobo", "i": "coit", "bi": "cobi"}[("b" if bold else "") + ("i" if italic else "")]
    if base == "ti":
        return {"": "tiro", "b": "tibo", "i": "tiit", "bi": "tibi"}[("b" if bold else "") + ("i" if italic else "")]
    return {"": "helv", "b": "hebo", "i": "heit", "bi": "hebi"}[("b" if bold else "") + ("i" if italic else "")]


def is_bold(span):
    name = (span.get("font") or "").lower()
    return bool(span.get("flags", 0) & 16) or "bold" in name or "black" in name or "heavy" in name or "semibold" in name


def is_italic(span):
    name = (span.get("font") or "").lower()
    return bool(span.get("flags", 0) & 2) or "italic" in name or "oblique" in name


def color_hex(value):
    if value is None:
        return "000000"
    return "%06X" % (int(value) & 0xFFFFFF)


def clean_text(text):
    return XML_ILLEGAL.sub("", text or "")


# --------------------------------------------------------------------------
# Page analysis (auto mode)
# --------------------------------------------------------------------------

def luminance(rgb):
    if not rgb:
        return 1.0
    r, g, b = rgb[:3]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def page_text_lines(page):
    data = page.get_text("dict", flags=fitz.TEXT_PRESERVE_WHITESPACE | fitz.TEXT_PRESERVE_LIGATURES | fitz.TEXT_MEDIABOX_CLIP)
    lines = []
    for block in data.get("blocks", []):
        if block.get("type") != 0:
            continue
        for line in block.get("lines", []):
            spans = [s for s in line.get("spans", []) if clean_text(s.get("text", "")).strip()]
            if not spans:
                continue
            bbox = fitz.Rect(line["bbox"])
            for s in spans:
                bbox |= fitz.Rect(s["bbox"])
            lines.append({"bbox": bbox, "spans": spans, "dir": line.get("dir", (1, 0))})
    return lines


def text_extent(lines):
    """Horizontal extent of the page's text, used to tell rules from decoration."""
    if not lines:
        return 0.0, 0.0
    return min(ln["bbox"].x0 for ln in lines), max(ln["bbox"].x1 for ln in lines)


def analyse_page(page):
    """Return a dict of layout signals for one page.

    Reflowing (pdf2docx) copes with text, tables and full-width rules. It
    breaks on *decoration*: coloured blocks, sidebars, logos drawn as shapes,
    light text on dark fills, and real side-by-side prose columns. Those are
    what this function counts.
    """
    area = max(page.rect.width * page.rect.height, 1.0)
    drawings = page.get_drawings()
    lines = page_text_lines(page)
    text_x0, text_x1 = text_extent(lines)
    text_width = max(text_x1 - text_x0, 1.0)

    decorative = 0          # filled, visible shapes that are not table rules
    decorative_area = 0.0
    dark_fill_area = 0.0
    for d in drawings:
        rect = d.get("rect")
        if rect is None:
            continue
        fill = d.get("fill")
        a = rect.width * rect.height
        is_rule = rect.height <= 2.5 and rect.width >= 0.5 * text_width
        is_box_outline = fill is None
        if is_box_outline or is_rule:
            continue
        if luminance(fill) >= 0.93 and a / area < 0.3:
            continue  # near-white panels behave like paper
        if a < 12:
            continue  # specks, bullets
        decorative += 1
        decorative_area += a
        if luminance(fill) < 0.6:
            dark_fill_area += a

    light_text = sum(1 for ln in lines for s in ln["spans"] if luminance(fitz.sRGB_to_pdf(s.get("color", 0))) > 0.85)

    # Prose columns: two multi-word lines side by side. Table cells (short
    # values next to a description) do not count.
    def words(ln):
        return sum(len(clean_text(s.get("text", "")).split()) for s in ln["spans"])
    prose = [ln for ln in lines if words(ln) >= 4]
    columns = 0
    for i, a in enumerate(prose[:300]):
        for b in prose[i + 1:i + 30]:
            if a["bbox"].y1 > b["bbox"].y0 and b["bbox"].y1 > a["bbox"].y0:
                if a["bbox"].x1 < b["bbox"].x0 - 24 or b["bbox"].x1 < a["bbox"].x0 - 24:
                    columns += 1
    images = len(page.get_images(full=True))
    return {
        "lines": len(lines),
        "drawings": len(drawings),
        "decorative": decorative,
        "decorative_ratio": decorative_area / area,
        "dark_fill_ratio": dark_fill_area / area,
        "light_text": light_text,
        "column_pairs": columns,
        "images": images,
    }


def choose_engine(doc):
    """auto: exact for designed pages, flow for written ones."""
    reasons = []
    pages = min(len(doc), 12)
    for pno in range(pages):
        sig = analyse_page(doc[pno])
        n = pno + 1
        if sig["dark_fill_ratio"] >= 0.05:
            reasons.append(f"page {n}: dark fill covers {sig['dark_fill_ratio']:.0%}")
        if sig["decorative"] >= 1:
            reasons.append(f"page {n}: {sig['decorative']} decorative shape(s)")
        if sig["light_text"] >= 2:
            reasons.append(f"page {n}: {sig['light_text']} light-on-dark text spans")
        if sig["column_pairs"] >= 6:
            reasons.append(f"page {n}: side-by-side text columns")
        if sig["images"] >= 1 and sig["lines"] <= 80:
            reasons.append(f"page {n}: {sig['images']} image(s) on a designed page")
        if sig["drawings"] >= 80:
            reasons.append(f"page {n}: {sig['drawings']} vector drawings")
        if reasons:
            break
    return ("exact", reasons) if reasons else ("flow", [])


def flow_looks_broken(docx_path, pdf_pages):
    """pdf2docx splits a page into extra sections when its layout confuses it.
    Many more sections than PDF pages means the result will not resemble the
    original."""
    try:
        with zipfile.ZipFile(docx_path) as z:
            xml = z.read("word/document.xml").decode("utf-8", "replace")
    except Exception:  # noqa: BLE001
        return True
    sections = xml.count("<w:sectPr")
    return sections > pdf_pages + 1


# --------------------------------------------------------------------------
# Exact-layout engine
# --------------------------------------------------------------------------

def backdrop_dpi(page_count):
    """Crisp artwork for normal documents, lighter files for long ones."""
    if page_count > 60:
        return 96
    if page_count > 25:
        return 120
    return BACKDROP_DPI


def backdrop_png(doc, pno):
    """Render the page with all text removed: images, fills, lines, logos."""
    tmp = fitz.open()
    tmp.insert_pdf(doc, from_page=pno, to_page=pno)
    page = tmp[0]
    words = page.get_text("words")
    if words:
        for w in words:
            page.add_redact_annot(fitz.Rect(w[:4]), fill=False)
        try:
            page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE, graphics=fitz.PDF_REDACT_LINE_ART_NONE, text=fitz.PDF_REDACT_TEXT_REMOVE)
        except TypeError:  # older PyMuPDF without the text= keyword
            page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE, graphics=fitz.PDF_REDACT_LINE_ART_NONE)
    pix = page.get_pixmap(dpi=backdrop_dpi(len(doc)), alpha=False)
    # Skip the picture entirely when the page has no artwork.
    if pix.n >= 3 and pix.is_unicolor and pix.pixel(0, 0)[:3] == (255, 255, 255):
        tmp.close()
        return None
    png = pix.tobytes("png")
    tmp.close()
    return png


def frame_xml(line, page_w, page_h):
    """One absolutely positioned paragraph for a text line."""
    bbox = line["bbox"]
    spans = line["spans"]
    size = max(MIN_FONT_PT, max(s.get("size", 10) for s in spans))
    height = max(bbox.height, size * 1.05)
    x = max(0.0, bbox.x0)
    y = max(0.0, bbox.y0)
    width = bbox.width
    frame_w = min(page_w - x, width * 1.08 + size * 0.6 + 2)
    runs = []
    for s in spans:
        text = clean_text(s.get("text", ""))
        if not text:
            continue
        fam = font_family(s.get("font"), s.get("flags", 0))
        bold, italic = is_bold(s), is_italic(s)
        fsize = max(MIN_FONT_PT, float(s.get("size", size)))
        # Fit the substitute font to the original span width with character scaling.
        try:
            est = fitz.get_text_length(text, fontname=measure_font(fam, bold, italic), fontsize=fsize)
        except Exception:
            est = 0
        span_w = fitz.Rect(s["bbox"]).width
        scale = 100
        if est > 0 and span_w > 0:
            scale = int(round(100 * span_w / est))
            scale = max(66, min(133, scale))
        rpr = [f'<w:rFonts w:ascii="{fam}" w:hAnsi="{fam}" w:cs="{fam}"/>']
        if bold:
            rpr.append("<w:b/>")
        if italic:
            rpr.append("<w:i/>")
        rpr.append(f'<w:color w:val="{color_hex(s.get("color"))}"/>')
        # Schema order matters to Word: w (character scale) precedes sz.
        if scale != 100:
            rpr.append(f'<w:w w:val="{scale}"/>')
        rpr.append(f'<w:sz w:val="{int(round(fsize * 2))}"/><w:szCs w:val="{int(round(fsize * 2))}"/>')
        runs.append(f'<w:r><w:rPr>{"".join(rpr)}</w:rPr><w:t xml:space="preserve">{escape(text)}</w:t></w:r>')
    if not runs:
        return ""
    line_twips = int(round(height * PT_TO_TWIP))
    return (
        "<w:p><w:pPr>"
        f'<w:framePr w:w="{int(round(frame_w * PT_TO_TWIP))}" w:h="{line_twips}" w:hRule="exact" w:wrap="none" '
        f'w:vAnchor="page" w:hAnchor="page" w:x="{int(round(x * PT_TO_TWIP))}" w:y="{int(round(y * PT_TO_TWIP))}"/>'
        "<w:widowControl w:val=\"0\"/>"
        f'<w:spacing w:before="0" w:after="0" w:line="{line_twips}" w:lineRule="exact"/>'
        '<w:ind w:left="0" w:right="0" w:firstLine="0"/>'
        "</w:pPr>" + "".join(runs) + "</w:p>"
    )


def backdrop_xml(rid, pno, page_w, page_h):
    cx = int(round(page_w * PT_TO_EMU))
    cy = int(round(page_h * PT_TO_EMU))
    return (
        '<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/><w:rPr><w:sz w:val="2"/></w:rPr></w:pPr>'
        "<w:r><w:rPr><w:sz w:val=\"2\"/></w:rPr><w:drawing>"
        '<wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="0" behindDoc="1" locked="1" layoutInCell="1" allowOverlap="1">'
        '<wp:simplePos x="0" y="0"/>'
        '<wp:positionH relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionH>'
        '<wp:positionV relativeFrom="page"><wp:posOffset>0</wp:posOffset></wp:positionV>'
        f'<wp:extent cx="{cx}" cy="{cy}"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapNone/>'
        f'<wp:docPr id="{pno + 1}" name="Page {pno + 1} artwork" descr="Page {pno + 1} graphics from the original PDF"/>'
        '<wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        f'<pic:pic><pic:nvPicPr><pic:cNvPr id="{pno + 1}" name="page-{pno + 1}.png"/><pic:cNvPicPr/></pic:nvPicPr>'
        f'<pic:blipFill><a:blip r:embed="{rid}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{cx}" cy="{cy}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        "</pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r></w:p>"
    )


def sect_xml(page_w, page_h, last):
    w = int(round(page_w * PT_TO_TWIP))
    h = int(round(page_h * PT_TO_TWIP))
    orient = ' w:orient="landscape"' if page_w > page_h else ""
    body = (
        '<w:type w:val="nextPage"/>'
        f'<w:pgSz w:w="{w}" w:h="{h}"{orient}/>'
        '<w:pgMar w:top="0" w:right="0" w:bottom="0" w:left="0" w:header="0" w:footer="0" w:gutter="0"/>'
    )
    if last:
        return f"<w:sectPr>{body}</w:sectPr>"
    return f"<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"20\" w:lineRule=\"exact\"/><w:rPr><w:sz w:val=\"2\"/></w:rPr><w:sectPr>{body}</w:sectPr></w:pPr></w:p>"


def convert_exact(doc, out_path):
    media = []  # (name, bytes)
    rels = []
    parts = []
    total_lines = 0
    for pno in range(len(doc)):
        page = doc[pno]
        pw, ph = page.rect.width, page.rect.height
        png = backdrop_png(doc, pno)
        if png:
            name = f"page-{pno + 1}.png"
            rid = f"rIdImg{pno + 1}"
            media.append((name, png))
            rels.append((rid, name))
            parts.append(backdrop_xml(rid, pno, pw, ph))
        else:
            parts.append('<w:p><w:pPr><w:spacing w:before="0" w:after="0" w:line="20" w:lineRule="exact"/><w:rPr><w:sz w:val="2"/></w:rPr></w:pPr></w:p>')
        lines = page_text_lines(page)
        # Rotated text cannot be placed in a frame; keep it in the backdrop only.
        for line in lines:
            d = line["dir"]
            if abs(d[0] - 1) > 0.05 or abs(d[1]) > 0.05:
                continue
            xml = frame_xml(line, pw, ph)
            if xml:
                parts.append(xml)
                total_lines += 1
        parts.append(sect_xml(pw, ph, last=(pno == len(doc) - 1)))

    document = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<w:document xmlns:w="{W_NS}" xmlns:wp="{WP_NS}" xmlns:a="{A_NS}" xmlns:pic="{PIC_NS}" xmlns:r="{R_NS}">'
        "<w:body>" + "".join(parts) + "</w:body></w:document>"
    )
    content_types = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Default Extension="png" ContentType="image/png"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>'
        "</Types>"
    )
    root_rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        "</Relationships>"
    )
    doc_rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '<Relationship Id="rIdSettings" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>'
        + "".join(
            f'<Relationship Id="{rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/{name}"/>'
            for rid, name in rels
        )
        + "</Relationships>"
    )
    styles = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<w:styles xmlns:w="{W_NS}"><w:docDefaults><w:rPrDefault><w:rPr>'
        '<w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:sz w:val="20"/><w:szCs w:val="20"/><w:lang w:val="en-US"/>'
        '</w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:before="0" w:after="0" w:line="240" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>'
        '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
        "</w:styles>"
    )
    settings = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        f'<w:settings xmlns:w="{W_NS}"><w:defaultTabStop w:val="720"/><w:characterSpacingControl w:val="doNotCompress"/>'
        '<w:compat><w:compatSetting w:name="compatibilityMode" w:uri="http://schemas.microsoft.com/office/word" w:val="15"/></w:compat>'
        "</w:settings>"
    )
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=False) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", root_rels)
        z.writestr("word/document.xml", document)
        z.writestr("word/_rels/document.xml.rels", doc_rels)
        z.writestr("word/styles.xml", styles)
        z.writestr("word/settings.xml", settings)
        for name, data in media:
            z.writestr(f"word/media/{name}", data)
    return {"engine": "exact", "pages": len(doc), "lines": total_lines, "backdrops": len(media)}


# --------------------------------------------------------------------------
# Flow engine (pdf2docx)
# --------------------------------------------------------------------------

def convert_flow(in_path, out_path):
    from pdf2docx import Converter

    cv = Converter(in_path)
    try:
        cv.convert(out_path, ignore_page_error=True)
    finally:
        cv.close()
    return {"engine": "flow"}


# --------------------------------------------------------------------------

def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    in_path, out_path = argv[1], argv[2]
    mode = "auto"
    if "--mode" in argv:
        mode = argv[argv.index("--mode") + 1]
    if mode not in ("auto", "exact", "flow"):
        print(f"unknown mode {mode}", file=sys.stderr)
        return 2
    try:
        doc = fitz.open(in_path)
    except Exception as e:  # noqa: BLE001
        print(f"cannot open PDF: {e}", file=sys.stderr)
        return 2
    if doc.needs_pass:
        print("PDF is password-protected", file=sys.stderr)
        return 2
    if len(doc) == 0:
        print("PDF has no pages", file=sys.stderr)
        return 2

    reasons = []
    engine = mode
    page_count = len(doc)
    if mode == "auto":
        engine, reasons = choose_engine(doc)
    try:
        if engine == "flow":
            info = convert_flow(in_path, out_path)
            info["pages"] = page_count
            if mode == "auto" and flow_looks_broken(out_path, page_count):
                reasons.append("reflow produced more sections than pages")
                engine = "exact"
        if engine == "exact":
            info = convert_exact(doc, out_path)
    except Exception as e:  # noqa: BLE001
        print(f"{engine} conversion failed: {e}", file=sys.stderr)
        return 3
    finally:
        doc.close()
    info["mode"] = mode
    info["reasons"] = reasons
    print(json.dumps(info))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
