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
        self.assertEqual(positions["add-character"], (505, 535))
        self.assertEqual(positions["export-character-list"], (540, 570))
        self.assertEqual(positions["reset-character-list"], (575, 605))

    def test_large_paragraph_rejects_unsafe_10_row_plan(self):
        result = layout.character_book_left_column(measured_paragraph_height=220)
        self.assertFalse(result.feasible)
        self.assertGreater(result.overflow, 0)
        self.assertEqual(result.available_bottom, 605)
        self.assertIn("overflow", result.violations[0])

    def test_character_limit_notice_is_part_of_available_height(self):
        normal = layout.character_book_left_column(70, show_limit_notice=True)
        self.assertTrue(normal.feasible)
        positions = {name: (top, bottom) for name, top, bottom in normal.positions}
        self.assertEqual(positions["character-limit-notice"], (429, 454))
        self.assertEqual(positions["add-character"], (505, 535))
        self.assertEqual(positions["export-character-list"], (540, 570))
        self.assertEqual(positions["reset-character-list"], (575, 605))
        large = layout.character_book_left_column(220, show_limit_notice=True)
        self.assertFalse(large.feasible)
        self.assertGreater(large.overflow, 0)

    def test_recompute_normal_is_independent_of_prior_large_attempt(self):
        large = layout.character_book_left_column(220)
        normal = layout.character_book_left_column(70)
        again = layout.character_book_left_column(70)
        self.assertFalse(large.feasible)
        self.assertEqual(normal, again)
        self.assertEqual(normal.positions[-1], ("reset-character-list", 575, 605))

    def test_empty_rows_still_reserve_action_area(self):
        result = layout.character_book_left_column(70, row_count=0)
        self.assertTrue(result.feasible)
        positions = {name: (top, bottom) for name, top, bottom in result.positions}
        self.assertEqual(positions["character-rows"][0], positions["character-rows"][1])
        self.assertEqual(positions["add-character"], (164, 194))
        self.assertEqual(positions["import-data"], (199, 229))
        self.assertNotIn("export-character-list", positions)
        self.assertNotIn("reset-character-list", positions)

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
            content, minimum_page_height=650, footer_reserved_height=45,
            available_work_height=800,
        )
        self.assertTrue(page.feasible)
        self.assertGreater(page.target_height, 650)
        self.assertEqual(page.target_height, page.required_height)
        self.assertEqual(page.overflow, 0)

    def test_responsive_parent_rejects_small_screen_without_partial_commit(self):
        content = layout.character_book_left_column(220, show_limit_notice=True)
        page = layout.plan_responsive_parent(content, 650, 45, 640)
        self.assertFalse(page.feasible)
        self.assertEqual(page.target_height, 0)
        self.assertGreater(page.overflow, 0)

    def test_responsive_parent_returns_to_normal_baseline(self):
        large = layout.character_book_left_column(220, show_limit_notice=True)
        normal = layout.character_book_left_column(70, show_limit_notice=True)
        larger_window = layout.plan_responsive_parent(large, 650, 45, 800)
        restored_window = layout.plan_responsive_parent(normal, 650, 45, 800)
        self.assertGreater(larger_window.target_height, restored_window.target_height)
        self.assertEqual(restored_window.target_height, 650)

    def test_two_columns_keep_normal_artwork_anchors(self):
        plan = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        self.assertTrue(plan.feasible, plan.violations)
        self.assertEqual((plan.page_width, plan.page_height), (960, 650))
        rect = dict(plan.controls)
        self.assertEqual(rect["character-rows"].y, 164)
        self.assertEqual(rect["macro-rows"].y, 140)
        self.assertEqual(rect["footer-close"], layout.Rect(795, 575, 90, 30))
        self.assertEqual(rect["add-character"], layout.Rect(70, 505, 370, 30))
        self.assertEqual(rect["export-character-list"], layout.Rect(70, 540, 370, 30))
        self.assertEqual(rect["footer-left"], layout.Rect(70, 575, 370, 30))
        self.assertNotIn("footer-right", rect)

    def test_two_columns_grow_parent_with_large_full_text(self):
        plan = layout.plan_character_macro_book(220, 72, 23, 62, 1920, 1080)
        self.assertTrue(plan.feasible, plan.violations)
        self.assertGreater(plan.page_height, 650)
        rect = dict(plan.controls)
        self.assertGreater(rect["character-rows"].y, 164)
        self.assertEqual(rect["add-character"].bottom + 5, rect["export-character-list"].y)
        self.assertEqual(rect["export-character-list"].bottom + 5, rect["footer-left"].y)
        self.assertLessEqual(rect["macro-upload"].bottom + 8, rect["footer-close"].y)
        self.assertEqual(rect["footer-close"].right, 885)

    def test_resizing_book_requires_artwork_safe_extension(self):
        normal = layout.plan_character_macro_book(70, 40, 23, 62, 1920, 1080)
        enlarged = layout.plan_character_macro_book(220, 72, 38, 130, 1920, 1080)
        self.assertTrue(normal.feasible, normal.violations)
        self.assertTrue(enlarged.feasible, enlarged.violations)
        self.assertFalse(normal.requires_art_extension)
        self.assertTrue(enlarged.requires_art_extension)
        # Geometry feasibility must not be confused with permission to
        # stretch the fixed 960x650 Morrowind artwork.
        self.assertEqual(normal.page_height, 650)
        self.assertGreater(enlarged.page_height, 650)

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
        self.assertEqual(controls["footer-close"], layout.Rect(795, 575, 90, 30))

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
        self.assertEqual(positions["footer-left"], layout.Rect(70, 575, 370, 30))
        self.assertEqual(positions["export-character-list"], layout.Rect(70, 540, 370, 30))
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

    def test_state_and_scale_matrix_never_clips_or_overlaps(self):
        # Every plan is a fresh immutable computation, not an incremental
        # adjustment to the last setting. The real Windows smoke still must
        # supply rendered font measurements before live layout is enabled.
        for profiles in (0, 1, 6, 10):
            for macros in (0, 1, 4):
                for label, paragraph, macro_copy, char_row, macro_row in (
                    ("Normal", 70, 40, 23, 62),
                    ("Extra Large", 220, 72, 38, 130),
                ):
                    for ui_scale, dpi_scale in ((1.0, 1.0), (0.5, 1.0),
                                                (1.0, 1.5), (0.5, 2.0)):
                        with self.subTest(profiles=profiles, macros=macros,
                                          preference=label, ui_scale=ui_scale,
                                          dpi_scale=dpi_scale):
                            plan = layout.plan_character_macro_book(
                                paragraph, macro_copy, char_row, macro_row,
                                1920, 1600,
                                profile_count=profiles, macro_count=macros,
                                show_limit_notice=(profiles == 10),
                                ui_scale=ui_scale, dpi_scale=dpi_scale)
                            self.assertTrue(plan.feasible, plan.violations)
                            positions = layout.expand_book_control_positions(plan)
                            self.assertEqual(
                                layout.validate_book_control_positions(plan, positions), ())
                            self.assertEqual(len(set(name for name, _ in positions)),
                                             len(positions))
                            self.assertEqual(
                                layout.expand_book_control_positions(plan), positions)

    def test_complete_button_labels_wrap_as_controls_not_as_words(self):
        normal = (
            layout.MeasuredControl("Play", 28, 16, 55, 22, padding_x=6),
            layout.MeasuredControl("Edit", 25, 16, 60, 22, padding_x=6),
            layout.MeasuredControl("Remove", 53, 16, 75, 22, padding_x=6),
        )
        large = (
            layout.MeasuredControl("Play", 49, 25, 55, 22, padding_x=6),
            layout.MeasuredControl("Edit", 48, 25, 60, 22, padding_x=6),
            layout.MeasuredControl("Remove", 96, 25, 75, 22, padding_x=6),
        )
        a = layout.plan_measured_control_flow(normal, 240, 164, 200, 5, 8)
        b = layout.plan_measured_control_flow(large, 240, 164, 200, 5, 8)
        self.assertTrue(a.feasible)
        self.assertTrue(b.feasible)
        self.assertEqual(a.required_height, 186)
        self.assertGreater(b.required_height, a.required_height)
        rect = dict(b.controls)
        self.assertGreaterEqual(rect["Remove"].width, 108)
        self.assertGreater(rect["Remove"].y, 164)
        self.assertEqual(layout.plan_measured_control_flow(normal, 240, 164, 200, 5, 8), a)

    def test_text_too_wide_requires_parent_redesign_without_clipping(self):
        unbreakable = (layout.MeasuredControl(
            "Expansion Pack: Enabled", 480, 26, 120, 30, padding_x=12),)
        result = layout.plan_measured_control_flow(unbreakable, 45, 60, 264)
        self.assertFalse(result.feasible)
        self.assertEqual(result.controls, ())
        self.assertIn("too wide", result.violations[0])

    def test_flow_rejects_duplicate_names_and_invalid_measurements(self):
        control = layout.MeasuredControl("Settings", 70, 16, 90, 24)
        result = layout.plan_measured_control_flow((control, control), 0, 0, 300)
        self.assertFalse(result.feasible)
        with self.assertRaises(ValueError):
            layout.MeasuredControl("broken", -1, 16, 20, 20)

    def test_horizontal_name_overflow_blocks_live_book_application(self):
        normal = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080,
            measured_character_name_width=110, measured_macro_name_width=100)
        long_names = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080,
            measured_character_name_width=215, measured_macro_name_width=165)
        self.assertTrue(normal.feasible, normal.violations)
        self.assertFalse(normal.live_application_ready)
        approved_fixture = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080,
            measured_character_name_width=110, measured_macro_name_width=100,
            complete_control_metrics=True, artwork_strategy_validated=True)
        self.assertTrue(approved_fixture.live_application_ready)
        self.assertTrue(long_names.feasible, long_names.violations)
        self.assertTrue(long_names.requires_horizontal_reflow)
        self.assertFalse(long_names.live_application_ready)
        self.assertEqual(normal.page_height, long_names.page_height)

    def test_missing_text_measurements_or_unsupported_artwork_are_not_ready(self):
        unmeasured = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080)
        enlarged = layout.plan_character_macro_book(
            220, 72, 38, 130, 1920, 1080,
            measured_character_name_width=120, measured_macro_name_width=108)
        self.assertTrue(unmeasured.feasible)
        self.assertFalse(unmeasured.live_application_ready)
        self.assertTrue(enlarged.requires_art_extension)
        self.assertFalse(enlarged.live_application_ready)

    def test_incomplete_metrics_and_unverified_artwork_block_live_application(self):
        kwargs = dict(
            measured_character_name_width=115,
            measured_macro_name_width=103,
        )
        no_controls = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080,
            artwork_strategy_validated=True, **kwargs)
        no_art = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080,
            complete_control_metrics=True, **kwargs)
        both = layout.plan_character_macro_book(
            70, 40, 23, 62, 1920, 1080,
            complete_control_metrics=True, artwork_strategy_validated=True,
            **kwargs)
        self.assertFalse(no_controls.live_application_ready)
        self.assertFalse(no_art.live_application_ready)
        self.assertTrue(both.live_application_ready)
        self.assertEqual(no_controls.controls, both.controls)

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
