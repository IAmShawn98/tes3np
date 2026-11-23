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
