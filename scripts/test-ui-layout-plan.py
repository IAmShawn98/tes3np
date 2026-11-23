#!/usr/bin/env python3
"""Cross-platform dry-run tests for the TES3NP all-content layout planner.

These tests do not make any claims about GDI/Windows pixel measurements. The
heights supplied here represent hypothetical results of native text measuring.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

MODULE = Path(__file__).with_name("ui-layout-plan.py")
spec = importlib.util.spec_from_file_location("tes3np_ui_layout_plan", MODULE)
if spec is None or spec.loader is None:
    raise RuntimeError("Could not import UI layout planner")
layout = importlib.util.module_from_spec(spec)
import sys
sys.modules[spec.name] = layout
spec.loader.exec_module(layout)


class LayoutPlanningTest(unittest.TestCase):
    def test_normal_uses_approved_character_and_action_positions(self):
        result = layout.character_book_left_column(measured_paragraph_height=70)
        self.assertTrue(result.feasible)
        positions = {name: (top, bottom) for name, top, bottom in result.positions}
        self.assertEqual(positions["complete-description"], (80, 161))
        self.assertEqual(positions["character-rows"], (164, 403))
        self.assertEqual(positions["add-character"], (540, 570))

    def test_large_paragraph_rejects_unsafe_10_row_plan(self):
        result = layout.character_book_left_column(measured_paragraph_height=220)
        self.assertFalse(result.feasible)
        self.assertGreater(result.overflow, 0)
        self.assertEqual(result.available_bottom, 570)
        self.assertIn("overflow", result.violations[0])

    def test_recompute_normal_is_independent_of_prior_large_attempt(self):
        large = layout.character_book_left_column(220)
        normal = layout.character_book_left_column(70)
        again = layout.character_book_left_column(70)
        self.assertFalse(large.feasible)
        self.assertEqual(normal, again)
        self.assertEqual(normal.positions[-1], ("add-character", 540, 570))

    def test_empty_rows_still_reserve_action_area(self):
        result = layout.character_book_left_column(70, row_count=0)
        self.assertTrue(result.feasible)
        positions = {name: (top, bottom) for name, top, bottom in result.positions}
        self.assertEqual(positions["character-rows"][0], positions["character-rows"][1])
        self.assertEqual(positions["add-character"], (540, 570))

    def test_reject_invalid_dimensions_and_row_overlap(self):
        with self.assertRaises(ValueError):
            layout.character_book_left_column(-5)
        with self.assertRaises(ValueError):
            layout.FixedRows("overlap", count=10, row_pitch=12, row_height=23)
        with self.assertRaises(ValueError):
            layout.plan_vertical_stack(600, 570, ())

    def test_unmeasured_or_unknown_items_not_silently_accepted(self):
        with self.assertRaises(TypeError):
            layout.plan_vertical_stack(0, 200, ("not-a-layout-item",))

    def test_oversize_description_does_not_shrink_text(self):
        result = layout.plan_vertical_stack(
            top=0, available_bottom=90,
            items=(layout.TextBlock("full-unchanged-copy", 40, 180),)
        )
        self.assertEqual(result.positions[0][2], 180)
        self.assertEqual(result.overflow, 90)
        self.assertFalse(result.feasible)


if __name__ == "__main__":
    unittest.main()
