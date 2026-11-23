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

    def test_character_limit_notice_is_part_of_available_height(self):
        normal = layout.character_book_left_column(70, show_limit_notice=True)
        self.assertTrue(normal.feasible)
        positions = {name: (top, bottom) for name, top, bottom in normal.positions}
        self.assertEqual(positions["character-limit-notice"], (429, 454))
        self.assertEqual(positions["add-character"], (540, 570))
        large = layout.character_book_left_column(220, show_limit_notice=True)
        self.assertFalse(large.feasible)
        self.assertGreater(large.overflow, 0)

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

    def test_responsive_parent_can_grow_without_shrinking_text(self):
        content = layout.character_book_left_column(220, show_limit_notice=True)
        self.assertFalse(content.feasible)
        page = layout.plan_responsive_parent(
            content, minimum_page_height=650, footer_reserved_height=60,
            available_work_height=800,
        )
        self.assertTrue(page.feasible)
        self.assertGreater(page.target_height, 650)
        self.assertEqual(page.target_height, page.required_height)
        self.assertEqual(page.overflow, 0)

    def test_responsive_parent_rejects_small_screen_without_partial_commit(self):
        content = layout.character_book_left_column(220, show_limit_notice=True)
        page = layout.plan_responsive_parent(content, 650, 60, 640)
        self.assertFalse(page.feasible)
        self.assertEqual(page.target_height, 0)
        self.assertGreater(page.overflow, 0)

    def test_responsive_parent_returns_to_normal_baseline(self):
        large = layout.character_book_left_column(220, show_limit_notice=True)
        normal = layout.character_book_left_column(70, show_limit_notice=True)
        larger_window = layout.plan_responsive_parent(large, 650, 60, 800)
        restored_window = layout.plan_responsive_parent(normal, 650, 60, 800)
        self.assertGreater(larger_window.target_height, restored_window.target_height)
        self.assertEqual(restored_window.target_height, 650)

    def test_two_columns_keep_normal_artwork_anchors(self):
        plan = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        self.assertTrue(plan.feasible, plan.violations)
        self.assertEqual((plan.page_width, plan.page_height), (960, 650))
        rect = dict(plan.controls)
        self.assertEqual(rect["character-rows"].y, 164)
        self.assertEqual(rect["macro-rows"].y, 140)
        self.assertEqual(rect["footer-close"].y, 575)

    def test_two_columns_grow_parent_with_large_full_text(self):
        plan = layout.plan_character_macro_book(220, 72, 23, 62, 1920, 1080)
        self.assertTrue(plan.feasible, plan.violations)
        self.assertGreater(plan.page_height, 650)
        rect = dict(plan.controls)
        self.assertGreater(rect["character-rows"].y, 164)
        self.assertLessEqual(rect["add-character"].bottom + 5, rect["footer-left"].y)
        self.assertLessEqual(rect["macro-upload"].bottom + 8, rect["footer-close"].y)

    def test_two_columns_are_reversible(self):
        before = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        larger = layout.plan_character_macro_book(220, 72, 23, 62, 1920, 1080)
        restored = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        self.assertTrue(larger.feasible)
        self.assertEqual(before, restored)

    def test_two_columns_small_monitor_rejects_every_move(self):
        plan = layout.plan_character_macro_book(220, 72, 23, 62, 960, 650)
        self.assertFalse(plan.feasible)
        self.assertEqual(plan.page_height, 0)
        self.assertEqual(plan.controls, ())
        self.assertIn("height", plan.violations[0])

    def test_two_columns_reject_horizontally_constrained_work_area(self):
        plan = layout.plan_character_macro_book(70, 40, 23, 62, 800, 1080)
        self.assertFalse(plan.feasible)
        self.assertEqual(plan.controls, ())

    def test_two_columns_grow_row_pitches_instead_of_shrinking_font(self):
        normal = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        character_grown = layout.plan_character_macro_book(70, 40, 38, 62, 1920, 1080)
        macro_grown = layout.plan_character_macro_book(70, 40, 23, 130, 1920, 1080)
        self.assertTrue(normal.feasible, normal.violations)
        self.assertTrue(character_grown.feasible, character_grown.violations)
        self.assertTrue(macro_grown.feasible, macro_grown.violations)
        self.assertGreater(dict(character_grown.controls)["character-rows"].height,
                           dict(normal.controls)["character-rows"].height)
        self.assertGreater(dict(macro_grown.controls)["macro-rows"].height,
                           dict(normal.controls)["macro-rows"].height)
        self.assertGreater(macro_grown.page_height, normal.page_height)

    def test_full_control_plan_keeps_approved_normal_positions(self):
        plan = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        positions = layout.expand_book_control_positions(plan)
        self.assertEqual(layout.validate_book_control_positions(plan, positions), ())
        controls = dict(positions)
        self.assertEqual(controls["character-1-name"], layout.Rect(95, 164, 140, 23))
        self.assertEqual(controls["character-10-remove"], layout.Rect(365, 380, 75, 22))
        self.assertEqual(controls["macro-1-status"], layout.Rect(551, 140, 329, 17))
        self.assertEqual(controls["macro-4-run"], layout.Rect(551, 392, 103, 20))
        self.assertEqual(controls["footer-close"], layout.Rect(515, 575, 90, 30))

    def test_full_control_plan_reflows_all_row_buttons_together(self):
        normal = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        enlarged = layout.plan_character_macro_book(220, 72, 38, 130, 1920, 1080)
        self.assertTrue(enlarged.feasible, enlarged.violations)
        before = dict(layout.expand_book_control_positions(normal))
        after = dict(layout.expand_book_control_positions(enlarged))
        self.assertEqual(layout.validate_book_control_positions(enlarged, tuple(after.items())), ())
        self.assertGreater(after["character-1-play"].y, before["character-1-play"].y)
        self.assertEqual(after["character-1-play"].y, after["character-1-name"].y)
        self.assertEqual(after["character-1-remove"].y, after["character-1-name"].y)
        self.assertGreater(after["macro-4-run"].y, before["macro-4-run"].y)
        self.assertEqual(after["macro-4-run"].y, after["macro-4-stop"].y)

    def test_larger_macro_name_never_overlays_action_controls(self):
        plan = layout.plan_character_macro_book(220, 72, 38, 130, 1920, 1080)
        positions = dict(layout.expand_book_control_positions(plan))
        self.assertTrue(plan.feasible, plan.violations)
        self.assertLessEqual(positions["macro-1-name"].bottom,
                             positions["macro-1-run"].y)
        self.assertLessEqual(positions["macro-4-name"].bottom,
                             positions["macro-4-run"].y)
        self.assertEqual(layout.validate_book_control_positions(
            plan, tuple(positions.items())), ())

    def test_control_expander_uses_measured_plan_without_second_font_guess(self):
        large = layout.plan_character_macro_book(220, 72, 38, 130, 1920, 1080)
        controls = dict(layout.expand_book_control_positions(large))
        self.assertEqual(large.character_row_height, 38)
        self.assertEqual(large.macro_row_height, 130)
        self.assertEqual(controls["character-1-name"].height, 38)
        self.assertGreater(controls["macro-1-run"].y, controls["macro-1-name"].y)
        self.assertEqual(layout.validate_book_control_positions(
            large, tuple(controls.items())), ())

    def test_empty_character_book_keeps_original_add_and_import_positions(self):
        plan = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080, profile_count=0, macro_count=0)
        self.assertTrue(plan.feasible, plan.violations)
        positions = dict(layout.expand_book_control_positions(plan))
        self.assertEqual(positions["add-character"], layout.Rect(70, 164, 370, 30))
        self.assertEqual(positions["import-data"], layout.Rect(70, 199, 370, 30))
        self.assertNotIn("footer-left", positions)
        self.assertNotIn("footer-right", positions)
        self.assertNotIn("character-1-name", positions)
        self.assertEqual(layout.validate_book_control_positions(
            plan, tuple(positions.items())), ())

    def test_full_character_book_keeps_notice_and_wipe_without_overlap(self):
        plan = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080,
            profile_count=10, show_limit_notice=True)
        self.assertTrue(plan.feasible, plan.violations)
        positions = dict(layout.expand_book_control_positions(plan))
        self.assertEqual(positions["character-limit-notice"], layout.Rect(70, 429, 370, 25))
        self.assertEqual(positions["footer-left"], layout.Rect(70, 577, 370, 25))
        self.assertNotIn("import-data", positions)
        self.assertEqual(layout.validate_book_control_positions(
            plan, tuple(positions.items())), ())

    def test_enlarged_limit_notice_moves_with_rows_and_actions(self):
        plan = layout.plan_character_macro_book(
            220, 72, 38, 130, 1920, 1080,
            profile_count=10, show_limit_notice=True)
        self.assertTrue(plan.feasible, plan.violations)
        positions = dict(layout.expand_book_control_positions(plan))
        notice = positions["character-limit-notice"]
        last_name = positions["character-10-name"]
        add = positions["add-character"]
        self.assertGreaterEqual(notice.y, last_name.bottom + 8)
        self.assertGreaterEqual(add.y, notice.bottom + 10)
        self.assertEqual(layout.validate_book_control_positions(
            plan, tuple(positions.items())), ())

    def test_half_scale_fits_without_changing_logical_content_or_text(self):
        full = layout.plan_character_macro_book(220, 72, 38, 130, 1920, 1080)
        half = layout.plan_character_macro_book(
            220, 72, 38, 130, 520, 490, ui_scale=0.5)
        self.assertTrue(full.feasible, full.violations)
        self.assertTrue(half.feasible, half.violations)
        self.assertEqual(full.controls, half.controls)
        self.assertEqual(full.page_height, half.page_height)
        self.assertEqual(layout.expand_book_control_positions(full),
                         layout.expand_book_control_positions(half))

    def test_zoom_and_dpi_are_independent_screen_constraints(self):
        base = layout.plan_character_macro_book(
            70, 40, 23, 62, 960, 650)
        zoomed = layout.plan_character_macro_book(
            70, 40, 23, 62, 960, 650, ui_scale=0.5, dpi_scale=2)
        exceeds = layout.plan_character_macro_book(
            70, 40, 23, 62, 960, 650, ui_scale=1.0, dpi_scale=1.5)
        self.assertTrue(base.feasible)
        self.assertTrue(zoomed.feasible)
        self.assertEqual(base.controls, zoomed.controls)
        self.assertFalse(exceeds.feasible)
        self.assertEqual(exceeds.controls, ())

    def test_reject_invalid_viewport_scale_or_impossible_limit_notice(self):
        with self.assertRaises(ValueError):
            layout.plan_character_macro_book(
                70, 40, 23, 62, 1920, 1080, ui_scale=0)
        with self.assertRaises(ValueError):
            layout.plan_character_macro_book(
                70, 40, 23, 62, 1920, 1080, dpi_scale=float("nan"))
        with self.assertRaises(ValueError):
            layout.plan_character_macro_book(
                70, 40, 23, 62, 1920, 1080,
                profile_count=0, show_limit_notice=True)

    def test_control_plan_rejects_infeasible_parent_and_restores_normal(self):
        rejected = layout.plan_character_macro_book(220, 72, 38, 130, 960, 650)
        self.assertEqual(layout.expand_book_control_positions(rejected), ())
        baseline = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        restored = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        self.assertEqual(layout.expand_book_control_positions(baseline),
                         layout.expand_book_control_positions(restored))

    def test_validator_catches_colliding_click_targets(self):
        plan = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        broken = (
            ("character-1-play", layout.Rect(240, 164, 55, 22)),
            ("character-1-edit", layout.Rect(250, 164, 60, 22)),
        )
        self.assertTrue(any("overlap" in item
                            for item in layout.validate_book_control_positions(plan, broken)))

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
