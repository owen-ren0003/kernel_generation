#!/usr/bin/env python3
"""Build the template-matched half-page harness overview slide."""

from __future__ import annotations

import argparse
from pathlib import Path

from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_AUTO_SHAPE_TYPE, MSO_SHAPE_TYPE
from pptx.enum.text import MSO_ANCHOR, PP_ALIGN
from pptx.oxml.xmlchemy import OxmlElement
from pptx.util import Inches, Pt


RED = RGBColor(0xC0, 0x00, 0x00)
RED_BRIGHT = RGBColor(0xE6, 0x00, 0x12)
RED_PALE = RGBColor(0xFC, 0xEE, 0xEE)
INK = RGBColor(0x20, 0x20, 0x20)
MUTED = RGBColor(0x66, 0x66, 0x66)
GRID = RGBColor(0xD9, 0xD9, 0xD9)
PANEL = RGBColor(0xFF, 0xFF, 0xFF)
SOFT = RGBColor(0xF7, 0xF7, 0xF7)
AMBER_PALE = RGBColor(0xFF, 0xF4, 0xE5)
AMBER_ALT = RGBColor(0xFA, 0xEB, 0xD7)
AMBER_TEXT = RGBColor(0x70, 0x38, 0x00)
FONT = "Microsoft YaHei"


def _set_cell_border(cell, color: str = "D9D9D9", width: int = 9000) -> None:
    """Set simple solid borders on a PowerPoint table cell."""
    tc_pr = cell._tc.get_or_add_tcPr()
    for edge in ("a:lnL", "a:lnR", "a:lnT", "a:lnB"):
        old = tc_pr.find(edge, tc_pr.nsmap)
        if old is not None:
            tc_pr.remove(old)
        line = OxmlElement(edge)
        line.set("w", str(width))
        solid = OxmlElement("a:solidFill")
        rgb = OxmlElement("a:srgbClr")
        rgb.set("val", color)
        solid.append(rgb)
        line.append(solid)
        dash = OxmlElement("a:prstDash")
        dash.set("val", "solid")
        line.append(dash)
        tc_pr.append(line)


def _style_run(run, size: float, *, bold: bool = False, color=INK) -> None:
    run.font.name = FONT
    run.font.size = Pt(size)
    run.font.bold = bold
    run.font.color.rgb = color


def _set_text(
    shape,
    text: str,
    size: float,
    *,
    bold: bool = False,
    color=INK,
    align=PP_ALIGN.LEFT,
    anchor=MSO_ANCHOR.MIDDLE,
    margins=(0.08, 0.08, 0.04, 0.04),
) -> None:
    tf = shape.text_frame
    tf.clear()
    tf.word_wrap = True
    tf.margin_left = Inches(margins[0])
    tf.margin_right = Inches(margins[1])
    tf.margin_top = Inches(margins[2])
    tf.margin_bottom = Inches(margins[3])
    tf.vertical_anchor = anchor
    lines = text.split("\n")
    for index, line in enumerate(lines):
        paragraph = tf.paragraphs[0] if index == 0 else tf.add_paragraph()
        paragraph.alignment = align
        paragraph.space_before = Pt(0)
        paragraph.space_after = Pt(0)
        paragraph.line_spacing = 1.0
        run = paragraph.add_run()
        run.text = line
        _style_run(run, size, bold=bold, color=color)


def _add_textbox(slide, x, y, w, h, text, size, **kwargs):
    shape = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    _set_text(shape, text, size, **kwargs)
    return shape


def _add_round_box(slide, x, y, w, h, text, size=9.0, *, fill=SOFT, line=RED):
    shape = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE,
        Inches(x),
        Inches(y),
        Inches(w),
        Inches(h),
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = fill
    shape.line.color.rgb = line
    shape.line.width = Pt(0.9)
    _set_text(shape, text, size, bold=True, align=PP_ALIGN.CENTER)
    return shape


def _clear_slide_except_navigation(slide):
    navigation = None
    for shape in list(slide.shapes):
        if shape.shape_type == MSO_SHAPE_TYPE.GROUP and shape.name == "Group 1":
            navigation = shape
            continue
        slide.shapes._spTree.remove(shape._element)
    if navigation is None:
        return

    labels = ["Overview", "Workflow", "Consulting", "Limits"]
    children = sorted(navigation.shapes, key=lambda item: item.left)
    for child, label in zip(children, labels):
        _set_text(
            child,
            label,
            6.8,
            bold=True,
            color=RED if label == "Overview" else MUTED,
            align=PP_ALIGN.CENTER,
            margins=(0.0, 0.0, 0.0, 0.0),
        )


def _style_summary_cell(cell, text, *, label=False, bold=False, align=PP_ALIGN.LEFT):
    cell.margin_left = Inches(0.08)
    cell.margin_right = Inches(0.08)
    cell.margin_top = Inches(0.03)
    cell.margin_bottom = Inches(0.03)
    cell.vertical_anchor = MSO_ANCHOR.MIDDLE
    cell.fill.solid()
    cell.fill.fore_color.rgb = RED if label else PANEL
    _set_cell_border(cell, "FFFFFF" if label else "D9D9D9", 6500)
    tf = cell.text_frame
    tf.clear()
    tf.word_wrap = True
    for idx, line in enumerate(text.split("\n")):
        p = tf.paragraphs[0] if idx == 0 else tf.add_paragraph()
        p.alignment = PP_ALIGN.CENTER if label else align
        p.space_before = Pt(0)
        p.space_after = Pt(0)
        p.line_spacing = 1.0
        run = p.add_run()
        run.text = line
        _style_run(run, 10.2, bold=True if label else bold, color=PANEL if label else INK)


def _add_summary_strip(slide):
    table_shape = slide.shapes.add_table(
        1, 4, Inches(0.385), Inches(0.842), Inches(12.196), Inches(0.927)
    )
    table = table_shape.table
    widths = (0.82, 5.10, 0.86, 5.416)
    for column, width in zip(table.columns, widths):
        column.width = Inches(width)
    table.rows[0].height = Inches(0.927)
    cells = table.rows[0].cells
    _style_summary_cell(cells[0], "GOAL", label=True)
    _style_summary_cell(
        cells[1],
        "One scoped task for code, investigation, analysis, documents or slides;\nresumable and evidence-backed",
        bold=True,
    )
    _style_summary_cell(cells[2], "CONSULT", label=True)
    _style_summary_cell(
        cells[3],
        "A5 hardware + 8 AscendNPU-IR playbooks feed Define, Investigate and Verify;\nmeasured results decide what is true",
    )


def _add_step_box(slide, x, y, heading, body):
    shape = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE,
        Inches(x), Inches(y), Inches(2.22), Inches(0.72),
    )
    shape.fill.solid()
    shape.fill.fore_color.rgb = SOFT
    shape.line.color.rgb = RED
    shape.line.width = Pt(0.9)

    tf = shape.text_frame
    tf.clear()
    tf.word_wrap = True
    tf.margin_left = Inches(0.05)
    tf.margin_right = Inches(0.05)
    tf.margin_top = Inches(0.025)
    tf.margin_bottom = Inches(0.025)
    tf.vertical_anchor = MSO_ANCHOR.MIDDLE

    heading_paragraph = tf.paragraphs[0]
    heading_paragraph.alignment = PP_ALIGN.CENTER
    heading_paragraph.space_before = Pt(0)
    heading_paragraph.space_after = Pt(0)
    heading_paragraph.line_spacing = 1.0
    heading_run = heading_paragraph.add_run()
    heading_run.text = heading
    _style_run(heading_run, 9.2, bold=True, color=RED)

    body_paragraph = tf.add_paragraph()
    body_paragraph.alignment = PP_ALIGN.CENTER
    body_paragraph.space_before = Pt(0)
    body_paragraph.space_after = Pt(0)
    body_paragraph.line_spacing = 1.0
    body_run = body_paragraph.add_run()
    body_run.text = body
    _style_run(body_run, 8.0, color=INK)
    return shape


def _add_flow_arrow(slide, x, y, *, rotation=0):
    arrow = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.CHEVRON,
        Inches(x), Inches(y), Inches(0.18), Inches(0.21),
    )
    arrow.rotation = rotation
    arrow.fill.solid()
    arrow.fill.fore_color.rgb = RED
    arrow.line.fill.background()
    return arrow


def _add_workflow_card(slide):
    card = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE,
        Inches(0.385), Inches(2.004), Inches(8.15), Inches(2.69),
    )
    card.fill.solid()
    card.fill.fore_color.rgb = PANEL
    card.line.color.rgb = RED
    card.line.width = Pt(1.0)
    _add_textbox(
        slide, 0.53, 2.07, 7.84, 0.32,
        "How one task moves through the harness",
        12.0, bold=True, color=RED, margins=(0, 0, 0, 0),
    )
    _add_textbox(
        slide, 0.58, 2.36, 7.72, 0.22,
        "One task folder keeps the request, decisions, commands, results and reviews.",
        8.4, color=MUTED, align=PP_ALIGN.LEFT, margins=(0, 0, 0, 0),
    )

    top_steps = [
        ("1  BIND TASK", "Create or resume the task record"),
        ("2  DEFINE", "Set the objective, success checks and scope"),
        ("3  INVESTIGATE", "Use skills and consulting to establish the cause or plan"),
    ]
    bottom_steps = [
        ("6  REVIEW & CLOSE", "Check the evidence; close only when success criteria pass"),
        ("5  VERIFY", "Build, test, measure or review the deliverable"),
        ("4  EXECUTE", "Make the scoped change or produce the deliverable"),
    ]
    x_positions = (0.62, 3.26, 5.90)
    for x, (heading, body) in zip(x_positions, top_steps):
        _add_step_box(slide, x, 2.65, heading, body)
    _add_flow_arrow(slide, 2.99, 2.90)
    _add_flow_arrow(slide, 5.63, 2.90)

    down = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.DOWN_ARROW,
        Inches(6.92), Inches(3.38), Inches(0.18), Inches(0.16),
    )
    down.fill.solid()
    down.fill.fore_color.rgb = RED
    down.line.fill.background()

    for x, (heading, body) in zip(x_positions, bottom_steps):
        _add_step_box(slide, x, 3.56, heading, body)
    _add_flow_arrow(slide, 2.99, 3.81, rotation=180)
    _add_flow_arrow(slide, 5.63, 3.81, rotation=180)

    loop_band = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE,
        Inches(0.70), Inches(4.38), Inches(7.52), Inches(0.22),
    )
    loop_band.fill.solid()
    loop_band.fill.fore_color.rgb = RED_PALE
    loop_band.line.color.rgb = RED
    loop_band.line.width = Pt(0.7)
    _set_text(
        loop_band,
        "↺  Failed check: record the result, update the analysis or plan, and repeat.",
        7.9,
        bold=True,
        color=RED,
        align=PP_ALIGN.CENTER,
        margins=(0.02, 0.02, 0, 0),
    )


def _style_support_cell(cell, text, *, label=False, shade=False):
    cell.margin_left = Inches(0.05)
    cell.margin_right = Inches(0.05)
    cell.margin_top = Inches(0.02)
    cell.margin_bottom = Inches(0.02)
    cell.vertical_anchor = MSO_ANCHOR.MIDDLE
    cell.fill.solid()
    cell.fill.fore_color.rgb = RED_PALE if label else (SOFT if shade else PANEL)
    _set_cell_border(cell, "FFFFFF" if label else "D9D9D9", 7000)
    tf = cell.text_frame
    tf.clear()
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER if label else PP_ALIGN.LEFT
    p.space_before = Pt(0)
    p.space_after = Pt(0)
    p.line_spacing = 1.0
    run = p.add_run()
    run.text = text
    _style_run(run, 8.0, bold=label, color=RED if label else INK)


def _add_support_card(slide):
    card = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE,
        Inches(8.69), Inches(2.004), Inches(3.89), Inches(2.69),
    )
    card.fill.solid()
    card.fill.fore_color.rgb = PANEL
    card.line.color.rgb = RED
    card.line.width = Pt(1.0)
    _add_textbox(
        slide, 8.85, 2.07, 3.57, 0.32,
        "Consulting materials",
        12.0, bold=True, color=RED, align=PP_ALIGN.CENTER,
        margins=(0, 0, 0, 0),
    )

    rows = [
        ("A5 hardware", "compute • memory/data • synchronization • performance"),
        ("Settings 1", "VF fusion • AutoBlockify • SIMT"),
        ("Settings 2", "SSBuffer • CV pipeline • CV 1:2"),
        ("Pipeline", "multibuffer • preload"),
        ("How to prove", "evidence model • harness flow • source/drift notes"),
    ]
    shape = slide.shapes.add_table(
        len(rows), 2, Inches(8.87), Inches(2.47), Inches(3.53), Inches(1.70)
    )
    table = shape.table
    table.columns[0].width = Inches(0.94)
    table.columns[1].width = Inches(2.59)
    for row in table.rows:
        row.height = Inches(0.34)
    for r, (left, right) in enumerate(rows):
        _style_support_cell(table.cell(r, 0), left, label=True)
        _style_support_cell(table.cell(r, 1), right, shade=(r % 2 == 1))

    _add_textbox(
        slide, 8.87, 4.28, 3.53, 0.31,
        "Use in 2 Define • 3 Investigate • 5 Verify;\nmeasurements decide.",
        7.9, bold=True, color=RED, align=PP_ALIGN.CENTER,
        margins=(0, 0, 0, 0),
    )


def _add_delivery_line(slide):
    _add_textbox(
        slide,
        0.70,
        4.84,
        11.75,
        0.31,
        "Outputs: code change • verified experiment • technical analysis • consulting document • presentation",
        10.4,
        bold=True,
        color=RED,
        align=PP_ALIGN.CENTER,
        margins=(0, 0, 0, 0),
    )


def _style_bottom_cell(
    cell,
    text,
    *,
    label=False,
    shade=False,
    amber=False,
    bold=False,
):
    cell.margin_left = Inches(0.05)
    cell.margin_right = Inches(0.05)
    cell.margin_top = Inches(0.015)
    cell.margin_bottom = Inches(0.015)
    cell.vertical_anchor = MSO_ANCHOR.MIDDLE
    cell.fill.solid()
    if amber:
        cell.fill.fore_color.rgb = AMBER_ALT if shade else AMBER_PALE
    else:
        cell.fill.fore_color.rgb = RED_PALE if label else (SOFT if shade else PANEL)
    _set_cell_border(cell, "FFFFFF" if label else "D9D9D9", 6500)

    tf = cell.text_frame
    tf.clear()
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER if label else PP_ALIGN.LEFT
    p.space_before = Pt(0)
    p.space_after = Pt(0)
    p.line_spacing = 1.0
    run = p.add_run()
    run.text = text
    _style_run(
        run,
        7.7,
        bold=(label or bold),
        color=RED if label else AMBER_TEXT if amber else INK,
    )


def _add_two_column_bottom_card(slide, x, title, rows, *, label_width=1.02):
    width = 4.0
    card = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE,
        Inches(x), Inches(5.22), Inches(width), Inches(2.02),
    )
    card.fill.solid()
    card.fill.fore_color.rgb = PANEL
    card.line.color.rgb = RED
    card.line.width = Pt(1.0)
    _add_textbox(
        slide, x + 0.14, 5.29, width - 0.28, 0.28,
        title, 11.0, bold=True, color=RED, align=PP_ALIGN.CENTER,
        margins=(0, 0, 0, 0),
    )

    shape = slide.shapes.add_table(
        len(rows), 2, Inches(x + 0.16), Inches(5.65), Inches(width - 0.32), Inches(1.43)
    )
    table = shape.table
    table.columns[0].width = Inches(label_width)
    table.columns[1].width = Inches(width - 0.32 - label_width)
    row_height = 1.43 / len(rows)
    for row in table.rows:
        row.height = Inches(row_height)
    for index, (label, body) in enumerate(rows):
        _style_bottom_cell(table.cell(index, 0), label, label=True)
        _style_bottom_cell(table.cell(index, 1), body, shade=(index % 2 == 1))


def _add_interaction_card(slide):
    rows = [
        ("Rules + skills", "choose the method; guide Investigate, Execute and Review"),
        ("Consulting", "Steps 2/3/5: form A5/IR hypotheses and select evidence"),
        ("Scripts + guides", "Steps 4/5: run controlled builds, deploys and tests"),
        ("State + hooks", "every step: preserve evidence and enforce scope"),
    ]
    _add_two_column_bottom_card(
        slide, 0.385, "How support enters the loop", rows, label_width=1.08
    )


def _add_improvement_card(slide):
    rows = [
        ("Correctness", "outputs • determinism • batch invariance"),
        ("Performance", "latency • throughput • utilization • overlap"),
        ("Compiler / IR", "lowering • layouts • fusion • feature activation"),
        ("Data / sync", "local reuse • transfers • waits • deadlocks"),
        ("Knowledge", "analysis • documentation • presentations"),
    ]
    _add_two_column_bottom_card(
        slide, 4.54, "What can be improved", rows, label_width=1.04
    )


def _add_limits_card(slide):
    x = 8.69
    width = 3.89
    card = slide.shapes.add_shape(
        MSO_AUTO_SHAPE_TYPE.ROUNDED_RECTANGLE,
        Inches(x), Inches(5.22), Inches(width), Inches(2.02),
    )
    card.fill.solid()
    card.fill.fore_color.rgb = PANEL
    card.line.color.rgb = RED
    card.line.width = Pt(1.0)
    _add_textbox(
        slide, x + 0.14, 5.29, width - 0.28, 0.28,
        "Hardware / platform limits", 11.0, bold=True, color=RED,
        align=PP_ALIGN.CENTER, margins=(0, 0, 0, 0),
    )

    rows = [
        "Finite matrix/vector core balance, bandwidth and local memory",
        "Datatype, layout, alignment and legal data-path rules",
        "Registers, synchronization events and buffer capacity limit overlap",
        "Launch, runtime and inter-card costs sit outside compiler IR",
        "If Triton still trails equivalent Ascend C, reconsider the implementation layer",
    ]
    shape = slide.shapes.add_table(
        len(rows), 1, Inches(x + 0.16), Inches(5.65), Inches(width - 0.32), Inches(1.43)
    )
    table = shape.table
    table.columns[0].width = Inches(width - 0.32)
    for row in table.rows:
        row.height = Inches(1.43 / len(rows))
    for index, text in enumerate(rows):
        _style_bottom_cell(
            table.cell(index, 0), text, shade=(index % 2 == 1), amber=True,
            bold=(index == len(rows) - 1),
        )


def build(template: Path, output: Path) -> None:
    prs = Presentation(str(template))
    if len(prs.slides) != 1:
        raise ValueError(f"Expected one-slide template, found {len(prs.slides)}")
    slide = prs.slides[0]
    _clear_slide_except_navigation(slide)

    _add_textbox(
        slide,
        0.385,
        0.26,
        9.15,
        0.42,
        "【Codex Harness】From task request to verified outcome",
        20.5,
        bold=True,
        color=RED,
        margins=(0, 0, 0, 0),
    )
    _add_summary_strip(slide)
    _add_workflow_card(slide)
    _add_support_card(slide)
    _add_delivery_line(slide)
    _add_interaction_card(slide)
    _add_improvement_card(slide)
    _add_limits_card(slide)

    output.parent.mkdir(parents=True, exist_ok=True)
    prs.save(str(output))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--template", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.template.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()
