#!/usr/bin/env python3
"""Pure geometry planning for TES3NP text-aware layouts.

No Windows, game state, assets, or GUI mutation. A plan is feasible only when
EVERY item fits; callers must not commit partly reflowed controls. Font and text
measurements are inputs from the actual renderer, not estimated here.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


@dataclass(frozen=True)
class TextBlock:
    name: str
    minimum_height: int
    required_height: int
    gap_after: int = 0
    minimum_top: int = 0

    def __post_init__(self):
        if not self.name or min(self.minimum_height, self.required_height, self.gap_after, self.minimum_top) < 0:
            raise ValueError("Invalid text block measurements")


@dataclass(frozen=True)
class FixedRows:
    name: str
    count: int
    row_height: int
    row_pitch: int
    gap_after: int = 0

    def __post_init__(self):
        if not self.name or self.count < 0 or min(self.row_height, self.row_pitch, self.gap_after) < 0:
            raise ValueError("Invalid row group dimensions")
        if self.count and self.row_pitch < self.row_height:
            raise ValueError("Rows must not overlap")


@dataclass(frozen=True)
class Plan:
    feasible: bool
    positions: tuple[tuple[str, int, int], ...]
    needed_bottom: int
    available_bottom: int
    overflow: int
    violations: tuple[str, ...]


def plan_vertical_stack(
    top: int,
    available_bottom: int,
    items: Sequence[TextBlock | FixedRows],
    minimum_next_top: int | None = None,
) -> Plan:
    """Resolve positions from immutable inputs. NEVER mutate existing controls.

    TextBlock.required_height must be measured using the requested accessible
    font and actual render width. FixedRows.count may represent all ten
    allocated row controls; a caller may use another count for visible rows.
    """
    if top < 0 or available_bottom < 0 or available_bottom < top:
        raise ValueError("Invalid content bounds")
    cursor = top
    positions: list[tuple[str, int, int]] = []
    violations: list[str] = []
    for item in items:
        if minimum_next_top is not None:
            cursor = max(cursor, minimum_next_top)
            minimum_next_top = None
        if isinstance(item, TextBlock):
            cursor = max(cursor, item.minimum_top)
            height = max(item.minimum_height, item.required_height)
            positions.append((item.name, cursor, cursor + height))
            cursor += height + item.gap_after
        elif isinstance(item, FixedRows):
            height = (item.count - 1) * item.row_pitch + item.row_height if item.count else 0
            positions.append((item.name, cursor, cursor + height))
            cursor += height + item.gap_after
        else:
            raise TypeError("Unsupported layout item")
    needed_bottom = max(top, max((bottom for _, _, bottom in positions), default=top))
    overflow = max(0, needed_bottom - available_bottom)
    if overflow:
        violations.append(f"Content requires bottom {needed_bottom}, but the available bottom is {available_bottom}; overflow {overflow}")
    return Plan(not violations, tuple(positions), needed_bottom,
                available_bottom, overflow, tuple(violations))


@dataclass(frozen=True)
class ParentPagePlan:
    feasible: bool
    required_height: int
    target_height: int
    available_height: int
    growth: int
    overflow: int


def plan_responsive_parent(
    content: Plan,
    minimum_page_height: int,
    footer_reserved_height: int,
    available_work_height: int,
) -> ParentPagePlan:
    """Plan a parent resize BEFORE placing children.

    The caller must measure every content region (columns and footer) and
    pass the maximum required lower edge. This only computes geometry; it
    never decides to shrink text, add scrolling, or edit a live window.
    """
    if min(minimum_page_height, footer_reserved_height, available_work_height) < 0:
        raise ValueError("Negative parent/page height")
    required = max(minimum_page_height, content.needed_bottom + footer_reserved_height)
    overflow = max(0, required - available_work_height)
    return ParentPagePlan(
        feasible=overflow == 0,
        required_height=required,
        target_height=required if not overflow else 0,
        available_height=available_work_height,
        growth=max(0, required - minimum_page_height),
        overflow=overflow,
    )


def character_book_left_column(
    measured_paragraph_height: int,
    row_count: int = 10,
    action_height: int = 30,
    available_bottom: int = 570,
    show_limit_notice: bool = False,
) -> Plan:
    """Diagnostic only; does not authorize changing Character Book positions.

    Coordinates and row pitch mirror existing native Character Book geometry.
    The baseline top positions and footer constraints must be considered before
    attempting any live reflow. The Add action ends at y570, just above
    the fixed Wipe Character List action beginning near y575.
    """
    if measured_paragraph_height < 0 or action_height < 0:
        raise ValueError("Negative text/action height")
    items: list[TextBlock | FixedRows] = [
        TextBlock("complete-description", 81, measured_paragraph_height, gap_after=3),
        FixedRows("character-rows", row_count, row_height=23, row_pitch=24, gap_after=10),
    ]
    if show_limit_notice:
        items.append(TextBlock("character-limit-notice", 25, 25, minimum_top=429))
    items.append(TextBlock("add-character", action_height, action_height, minimum_top=540))
    return plan_vertical_stack(
        top=80,
        available_bottom=available_bottom,
        items=items,
    )


@dataclass(frozen=True)
class Rect:
    """Immutable logical-pixel rectangle, independently measured from GUI state."""
    x: int
    y: int
    width: int
    height: int

    def __post_init__(self):
        if min(self.x, self.y, self.width, self.height) < 0:
            raise ValueError("Negative rectangle dimension")

    @property
    def right(self) -> int:
        return self.x + self.width

    @property
    def bottom(self) -> int:
        return self.y + self.height

    def intersects(self, other: "Rect") -> bool:
        return (self.x < other.right and other.x < self.right
                and self.y < other.bottom and other.y < self.bottom)


@dataclass(frozen=True)
class BookPlan:
    """All-or-nothing Character/Macro Book draft, not live control coordinates."""
    feasible: bool
    page_width: int
    page_height: int
    controls: tuple[tuple[str, Rect], ...]
    violations: tuple[str, ...]



def expand_book_control_positions(
    plan: BookPlan,
    profile_count: int = 10,
    macro_count: int = 4,
    character_row_height: int = 23,
    macro_row_height: int = 62,
    row_pitch: int = 24,
    macro_pitch: int = 70,
) -> tuple[tuple[str, Rect], ...]:
    """Expand a feasible two-column plan into one immutable control geometry.

    This does NOT change the native button faces, hit targets, or live GUI.
    It is a full-transaction preview used to check relative row alignment,
    footer placement, and original Normal anchors before implementing them.
    """
    if not plan.feasible or not plan.controls:
        return ()
    if min(profile_count, macro_count, character_row_height,
           macro_row_height, row_pitch, macro_pitch) < 0:
        raise ValueError("Invalid control dimensions")
    if profile_count > 10 or macro_count > 4:
        raise ValueError("More controls requested than allocated")
    regions = dict(plan.controls)
    left = regions["character-rows"]
    right = regions["macro-rows"]
    char_pitch = max(row_pitch, character_row_height + 1)
    mac_pitch = max(macro_pitch, macro_row_height + 8)
    controls: list[tuple[str, Rect]] = []
    for number in range(profile_count):
        y = left.y + number * char_pitch
        prefix = f"character-{number + 1}"
        controls.extend((
            (prefix + "-tick", Rect(70, y + 2, 18, max(18, character_row_height - 5))),
            (prefix + "-name", Rect(95, y, 140, character_row_height)),
            (prefix + "-play", Rect(240, y, 55, max(22, character_row_height - 1))),
            (prefix + "-edit", Rect(300, y, 60, max(22, character_row_height - 1))),
            (prefix + "-remove", Rect(365, y, 75, max(22, character_row_height - 1))),
        ))
    for number in range(macro_count):
        y = right.y + number * mac_pitch
        prefix = f"macro-{number + 1}"
        # The larger row height is a budget, not permission to overlay the
        # name and action buttons. Grow the name region first, then start the
        # action row strictly below it, keeping the complete original content.
        name_height = max(22, macro_row_height * 3 // 10)
        action_offset = max(42, 19 + name_height + 1)
        action_height = max(20, macro_row_height - action_offset)
        controls.extend((
            (prefix + "-status", Rect(551, y, 329, 17)),
            (prefix + "-tick", Rect(525, y + 20, 18, 18)),
            (prefix + "-name", Rect(551, y + 19, 125, name_height)),
            (prefix + "-rename", Rect(680, y + 19, 21, name_height)),
            (prefix + "-run", Rect(551, y + action_offset, 103, action_height)),
            (prefix + "-stop", Rect(663, y + action_offset, 103, action_height)),
            (prefix + "-remove", Rect(775, y + action_offset, 105, action_height)),
        ))
    # Aggregate rectangles are not returned because they intentionally
    # contain the individual controls. The footer is returned as independent
    # buttons; shared coordinate planning prevents painter/hitbox drift.
    controls.extend((name, rect) for name, rect in plan.controls
                    if name not in ("character-rows", "macro-rows"))
    return tuple(controls)


def validate_book_control_positions(
    plan: BookPlan,
    positions: Sequence[tuple[str, Rect]],
) -> tuple[str, ...]:
    """Check same-column row bounds, no duplicate IDs, and parent containment."""
    if not plan.feasible:
        return ("Parent layout infeasible",)
    issues: list[str] = []
    seen: set[str] = set()
    for name, rect in positions:
        if name in seen:
            issues.append(f"Duplicate control ID: {name}")
        seen.add(name)
        if rect.right > plan.page_width or rect.bottom > plan.page_height:
            issues.append(f"Control outside book: {name}")
    # Individual rectangles may never overlap, including text and native
    # clickable targets. Aggregate parent regions were deliberately omitted.
    for i, (name, rect) in enumerate(positions):
        for other_name, other_rect in positions[i + 1:]:
            if rect.intersects(other_rect):
                issues.append(f"Controls overlap: {name} / {other_name}")
    return tuple(issues)


def plan_character_macro_book(
    paragraph_height: int,
    macro_explanation_height: int,
    row_height: int,
    macro_row_height: int,
    screen_width: int,
    screen_height: int,
    profile_count: int = 10,
    macro_count: int = 4,
    row_pitch: int = 24,
    macro_pitch: int = 70,
    baseline_width: int = 960,
    baseline_height: int = 650,
) -> BookPlan:
    """Plan BOTH parchment columns, actions and footer before applying ANY move.

    Geometry comes from the currently approved Character Book anchors.
    Paragraph and row heights are required measured inputs, not font guesses.
    The parent may grow vertically when there is real work-area space.
    Insufficient monitor space returns an infeasible plan, never a partial move.
    """
    if min(paragraph_height, macro_explanation_height, row_height,
           macro_row_height, screen_width, screen_height, profile_count,
           macro_count, row_pitch, macro_pitch) < 0:
        raise ValueError("Negative geometry or count")
    if profile_count > 10 or macro_count > 4:
        raise ValueError("Visible row count exceeds existing controls")
    # Grow the pitch when text/hit targets grow. Retain each column's
    # original baseline spacing (1px for character rows, 8px for macros),
    # instead of rejecting larger accessible fonts or overlapping the rows.
    effective_row_pitch = max(row_pitch, row_height + 1)
    effective_macro_pitch = max(macro_pitch, macro_row_height + 8)

    # A column's planned height is measured from its original top anchor.
    paragraph_bottom = 80 + max(81, paragraph_height)
    left_first = max(164, paragraph_bottom + 3)
    last_left = left_first + (profile_count - 1) * effective_row_pitch + row_height if profile_count else left_first
    left_action = max(540, last_left + 10) if profile_count else max(164, paragraph_bottom + 3)
    left_action_bottom = left_action + 30

    macro_text_bottom = 87 + max(48, macro_explanation_height)
    macro_first = max(140, macro_text_bottom + 5)
    macro_last = (macro_first + (macro_count - 1) * effective_macro_pitch + macro_row_height
                  if macro_count else macro_first)
    macro_upload = max(188, macro_last + 8)
    macro_upload_bottom = macro_upload + 29

    # The two columns are independently laid out; the footer is downstream
    # of whichever column needs the most vertical room.
    footer_y = max(575, left_action_bottom + 5, macro_upload_bottom + 8)
    needed_page_height = max(baseline_height, footer_y + 75)
    controls = (
        ("description", Rect(70, 80, 390, max(81, paragraph_height))),
        ("character-rows", Rect(70, left_first, 370,
             max(0, last_left - left_first))),
        ("add-character", Rect(70, left_action, 370, 30)),
        ("macro-explanation", Rect(525, 87, 355, max(48, macro_explanation_height))),
        ("macro-rows", Rect(525, macro_first, 355,
             max(0, macro_last - macro_first))),
        ("macro-upload", Rect(525, macro_upload, 355, 29)),
        ("footer-left", Rect(70, footer_y, 370, 30)),
        ("footer-close", Rect(515, footer_y, 90, 30)),
        ("footer-right", Rect(775, footer_y, 110, 30)),
    )
    violations = []
    if baseline_width > screen_width:
        violations.append("Character Book artwork exceeds available work-area width")
    if needed_page_height > screen_height:
        violations.append("Character Book content exceeds available work-area height")
    for name, rect in controls:
        if rect.right > baseline_width or rect.bottom > needed_page_height:
            violations.append(f"{name} falls outside the planned parent bounds")
    for i, (name, rect) in enumerate(controls):
        for other_name, other_rect in controls[i + 1:]:
            if rect.intersects(other_rect):
                violations.append(f"{name} overlaps {other_name}")
    return BookPlan(not violations, baseline_width,
                    needed_page_height if not violations else 0,
                    controls if not violations else tuple(),
                    tuple(violations))
