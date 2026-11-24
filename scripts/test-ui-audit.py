#!/usr/bin/env python3
"""Test that launcher-wide source inventory cannot silently skip UI surfaces."""
from __future__ import annotations
import importlib.util
import sys
from pathlib import Path
import unittest

SOURCE = Path(__file__).with_name("audit-ui-layout.py")
spec = importlib.util.spec_from_file_location("tes3np_ui_audit", SOURCE)
if spec is None or spec.loader is None:
    raise RuntimeError("Missing source inventory utility")
audit = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = audit
spec.loader.exec_module(audit)


class InventoryCoverageTests(unittest.TestCase):
    def test_all_known_native_and_chat_surfaces_are_present(self):
        result = audit.summarize(audit.inventory())
        found = {entry["path"] for entry in result["files"]}
        required = {
            "src/ui/characters.ahk",
            "src/ui/macros.ahk",
            "src/ui/renderer.ahk",
            "src/ui/controls.ahk",
            "src/ui/launcher-layout.ahk",
            "src/ui/launcher-settings.ahk",
            "src/ui/windows.ahk",
            "src/ui/front-page.ahk",
            "src/ui/v016-refinements.ahk",
            "src/ui/update-dialogs.ahk",
            "src/ui/update-notes.ahk",
            "src/ui/bug-report.ahk",
            "src/ui/loading.ahk",
            "src/ui/login-progress.ahk",
            "src/ui/patcher.ahk",
            "src/ui/embedded-chat.ahk",
            "src/app/bootstrap.ahk",
            "game-chat/GameChatWindow.Layout.cs",
            "game-chat/GameChatWindow.Surface.cs",
            "game-chat/GameChatWindow.ChatComposer.cs",
            "game-chat/chat.css",
        }
        self.assertEqual(set(), required - found,
                         "Known production UI source files missing from audit")
        self.assertGreater(result["finding_counts"].get("geometry", 0), 0)
        self.assertGreater(result["finding_counts"].get("font", 0), 0)
        self.assertGreater(result["finding_counts"].get("renderer", 0), 0)
        self.assertGreater(result["finding_counts"].get("font-risk", 0), 0)

    def test_never_treat_comments_as_geometry(self):
        source = audit.inventory()
        self.assertTrue(source)
        for entry in source:
            for item in entry["findings"]:
                self.assertFalse(item["source"].startswith(";"))
                self.assertFalse(item["source"].startswith("//"))

    def test_layout_transaction_has_no_character_book_scaling_dependency(self):
        source = (SOURCE.parents[1] / "src/ui/windows.ahk").read_text(
            encoding="utf-8-sig")
        start = source.index("ApplyAccessibleControlLayout(gui, placements,")
        end = source.index("\n; Pure native draft", start)
        body = source[start:end]
        self.assertIn("validity := ValidateAccessibleControlRectangles(", body)
        self.assertIn("for snapshot in snapshots", body)
        self.assertIn("ctrl.Move(entry.X, entry.Y, entry.Width, entry.Height)", body)
        self.assertNotIn("MoveStyledButton(", body)
        self.assertNotIn("BookS(", body)
        self.assertNotIn("GetCharacterBookScale(", body)

    def test_empty_character_book_reflows_measured_copy_not_populated_rows(self):
        source = (SOURCE.parents[1] / "src/ui/characters.ahk").read_text(
            encoding="utf-8-sig")
        begin = source.index("RefreshProfiles()\n{")
        end = source.index("\nMoveStyledButton(control,", begin)
        refresh = source[begin:end]
        self.assertIn("CharacterDescription.Move(BookS(70), BookS(80), BookS(390), BookS(81))", refresh)
        self.assertIn("if !Profiles.Length", refresh)
        self.assertIn("MeasureAccessibleWrappedText(CharacterDescription, descriptionText,", refresh)
        self.assertIn("if proposedAddY + 65 <= 570", refresh)
        self.assertIn("MoveStyledButton(AddCharacterButton, 70, actionY, 370, 30)", refresh)
        self.assertIn("transferY := Profiles.Length ? 575 : actionY + 35", refresh)
        self.assertNotIn("CharacterDescription.Text := StrReplace", refresh)
        # Cached books must remeasure only when the font choice changed.
        open_section = source[
            source.index("OpenCharacterPage(*)"):source.index("\nRefreshProfiles()\n{")]
        self.assertIn("cachedTextChanged := CharacterPage.HasOwnProp", open_section)
        self.assertIn("if cachedTextChanged", open_section)
        self.assertIn("RefreshProfiles()", open_section)
        self.assertIn('CharacterPage.Show("Hide w" Round(960 * bookScale)', open_section)

    def test_populated_book_reflow_measures_and_restores_every_row(self):
        root = SOURCE.parents[1] / "src/ui"
        characters = (root / "characters.ahk").read_text(encoding="utf-8-sig")
        renderer = (root / "renderer.ahk").read_text(encoding="utf-8-sig")
        start = characters.index("ReflowAccessiblePopulatedCharacters()\n{")
        end = characters.index("\nMoveStyledButton(control,", start)
        section = characters[start:end]
        self.assertIn("MeasureAccessibleWrappedText(CharacterDescription,", section)
        self.assertIn("PrepareAccessibleBookName(controls.Name, name,", section)
        self.assertIn("MeasureAccessibleWrappedText(controls.Name, displayName,", section)
        self.assertIn("AccessibleNameText := layout.DisplayName", section)
        self.assertIn('nameFace.DeleteProp("AccessibleNameText")', section)
        self.assertIn("labelText := face.AccessibleNameText", renderer)
        macros = (root / "macros.ahk").read_text(encoding="utf-8-sig")
        self.assertIn("PrepareAccessibleBookName(row.Name, item.Name,", macros)
        self.assertIn("row.Name, displayName, BookS(width - 8)", macros)
        self.assertIn("face.AccessibleNameText := displayNames[position]", macros)
        self.assertIn('face.DeleteProp("AccessibleNameText")', macros)
        self.assertIn("MeasureAccessibleSingleLineText(button, button.Text)", section)
        self.assertIn('if !SetCharacterBookLayoutExtra("Characters", Max(0, addY + 30 - 570))', section)
        self.assertIn('SetCharacterBookLayoutExtra("Characters", 0)', section)
        self.assertIn('Max(addY, 540 + GetCharacterBookExtra())', section)
        self.assertIn('compactWidths[3] + 10 <= 200', section)
        self.assertIn('x += width + layout.Gap', section)
        parent = characters[characters.index('SetCharacterBookLayoutExtra(side, required)'):characters.index('\nGetCharacterBookExtra()')]
        self.assertIn('extra := Max(leftExtra, rightExtra)', parent)
        self.assertIn('MonitorGetWorkArea(monitor', parent)
        self.assertIn('DllCall("GetWindowRect", "Ptr", LauncherGui.Hwnd', parent)
        self.assertNotIn('WinGetPos(', parent)
        self.assertIn('ApplyExtendedBookArtwork(page, extra)', parent)
        self.assertIn('SetWindowPos', parent)
        self.assertNotIn('if DllCall("IsWindowVisible"', parent)
        self.assertIn('575 + extra', parent)
        self.assertIn('GdipBitmapLockBits', renderer)
        self.assertIn('CopyBookPixelRows', renderer)
        self.assertIn('RtlMoveMemory', renderer)
        self.assertIn('width, seam - 1, dest, half, -1', renderer)
        self.assertIn('bookImage := extended ? ButtonPaint.BookExtended : ButtonPaint.Book', renderer)
        self.assertIn("MoveStyledButton(controls.Tick,", section)
        self.assertIn("MoveStyledButton(controls.Name,", section)
        self.assertIn("MoveStyledButton(button, x, layout.ButtonY,", section)
        self.assertIn("RestoreAccessibleCharacterRowBaseline()", section)
        self.assertIn("face.DeleteProp(\"NoAccessibleDownfit\")", section)
        self.assertIn('face.HasOwnProp("NoAccessibleDownfit")', renderer)
        self.assertIn('AccessibleWrappedName := true', section)
        self.assertIn('nameFace.DeleteProp("AccessibleWrappedName")', section)
        self.assertIn("drawFlags := 0x0810 ; DT_NOPREFIX | DT_WORDBREAK", renderer)
        self.assertIn("if cachedTextChanged", characters)

    def test_editor_uses_measured_stack_and_right_column_ownership(self):
        root = SOURCE.parents[1] / "src/ui"
        characters = (root / "characters.ahk").read_text(encoding="utf-8-sig")
        macros = (root / "macros.ahk").read_text(encoding="utf-8-sig")
        self.assertIn("PlanBookEditorGeometry(LaunchSettingsHeading,", characters)
        self.assertIn("MeasureAccessibleWrappedText(", characters)
        self.assertIn('SetCharacterBookLayoutExtra("Macros", plan.Extra)', characters)
        self.assertIn("ReflowProfileEditor()", characters)
        self.assertIn("if !shown\n        return\n    selectedIndex", macros)
        self.assertIn("controls.Species.Move(BookS(525), BookS(plan.DropdownY))", characters)
        self.assertIn("ButtonFaces[button.Hwnd].NoAccessibleDownfit := measured", characters)

    def test_inventory_serializes_with_expected_categories(self):
        report = audit.summarize(audit.inventory())
        self.assertEqual(report["scope"], ["src", "game-chat"])
        self.assertGreaterEqual(report["flagged_files"], 21)
        self.assertIn("files", report)
        self.assertTrue(all(item["findings"] for item in report["files"]))


if __name__ == "__main__":
    unittest.main()
