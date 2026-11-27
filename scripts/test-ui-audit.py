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
            "src/ui/server-map.ahk",
            "src/app/bootstrap.ahk",
            "game-chat/GameChatWindow.Layout.cs",
            "game-chat/GameChatWindow.Surface.cs",
            "game-chat/GameChatWindow.ChatComposer.cs",
            "game-chat/ServerMapHost.cs",
            "game-chat/web/map-filters.js",
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
        self.assertIn("CharacterDescription.Move(BookS(70), BookS(copyY), BookS(390), BookS(81))", refresh)
        self.assertIn("if !Profiles.Length", refresh)
        self.assertIn("MeasureAccessibleWrappedText(CharacterDescription, descriptionText,", refresh)
        self.assertIn("if proposedAddY + addMetrics.Height + 5 + importMetrics.Height <= 570", refresh)
        self.assertIn("MoveMeasuredBookAction(AddCharacterButton, 70, actionY, 370, addMetrics.Height)", refresh)
        self.assertIn("transferY := Profiles.Length ? 575 : actionY + addMetrics.Height + 5", refresh)
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
        self.assertIn("copyY := CharacterBookDescriptionY()", section)
        self.assertIn("return BookHeadingCopyY(CharacterPage.BookCharacterHeading, 70, 380, 30, 80)", characters)
        self.assertIn("copyY := BookHeadingCopyY(MacroBookControls[1], 525, 355, 32, 87)", (root / "macros.ahk").read_text(encoding="utf-8-sig"))
        self.assertIn("PrepareAccessibleBookName(controls.Name, name,", section)
        self.assertIn("MeasureAccessibleWrappedText(controls.Name, displayName,", section)
        self.assertIn("AccessibleNameText := layout.DisplayName", section)
        self.assertIn('nameFace.DeleteProp("AccessibleNameText")', section)
        self.assertIn("labelText := face.AccessibleNameText", renderer)
        macros = (root / "macros.ahk").read_text(encoding="utf-8-sig")
        self.assertIn("PrepareAccessibleBookName(sample, item.Name,", macros)
        self.assertIn("MeasureAccessibleWrappedText(sample, displayName,", macros)
        self.assertIn("MeasureMacroNameCollection(sample.Name, MacroItems, maxNameW)", macros)
        self.assertIn("metrics := collection.Items[MacroScrollOffset + position]", macros)
        self.assertIn("pages := PlanFixedBookPages(count, slots)", macros)
        self.assertIn("Loop pagePlan.Count", macros)
        self.assertIn("return PlanFixedBookPages(Profiles.Length, fixedSize)", characters)
        self.assertIn("desiredUploadY += upload.NavigationHeight + 8", macros)
        self.assertIn("upload.UploadWidth", macros)
        self.assertNotIn("MacroScrollThumb", macros)
        self.assertIn("nameH := Max(nameH, collection.Height)", macros)
        self.assertIn("GetMacroUploadMetrics()", macros)
        self.assertIn("upload.FeedbackOffset + upload.FeedbackHeight - 490", macros)
        self.assertIn("MoveMacroTextIfChanged(MacroStatus, BookS(525), BookS(desiredUploadY + upload.FeedbackOffset)", macros)
        self.assertIn("face.AccessibleNameText := displayNames[position]", macros)
        self.assertIn('face.DeleteProp("AccessibleNameText")', macros)
        self.assertIn("MeasureAccessibleSingleLineText(button, button.Text)", section)
        self.assertIn('SetCharacterBookLayoutExtra("Characters", 0)', section)
        self.assertIn('addHeight := GetBookFooterMetrics(CharacterPage).AddHeight', section)
        self.assertIn('PlanCharacterBookPages(pitches, limitY - firstY)', section)
        self.assertIn('ButtonX: 95, ButtonY: rowY + item.NameHeight + 4', section)
        self.assertIn('VisibleCharacterProfileIndex(position)', section)
        self.assertIn('BindCharacterBookRows(pages)', section)
        self.assertIn('CharacterPage.BookVisibleCount', section)
        self.assertIn('x += width + layout.Gap', section)
        parent = characters[characters.index('SetCharacterBookLayoutExtra(side, required)'):characters.index('\nGetCharacterBookExtra()')]
        self.assertIn('extra := Max(leftExtra, rightExtra) + footer.FooterHeight - 30', parent)
        self.assertIn('required := Max(0, Ceil(required))', parent)
        self.assertNotIn('Ceil(required / 8)', parent)
        self.assertIn('MonitorGetWorkArea(monitor', parent)
        self.assertIn('DllCall("GetWindowRect", "Ptr", LauncherGui.Hwnd', parent)
        self.assertNotIn('WinGetPos(', parent)
        self.assertIn('ApplyExtendedBookArtwork(page, extra)', parent)
        self.assertIn('SetWindowPos', parent)
        self.assertNotIn('if DllCall("IsWindowVisible"', parent)
        self.assertIn('footerY := 605 + extra - footer.FooterHeight', parent)
        self.assertIn('footerY - 5 - footer.AddHeight', parent)
        self.assertIn('885 - footer.TransferWidth', parent)
        self.assertIn('MeasureAccessibleSingleLineText(control, caption)', characters)
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
        self.assertIn('"Auto Login Settings"', characters)
        self.assertIn("EditorControls.Push(autoLoginHeading)", characters)
        self.assertIn("controls.AutoLoginHeading, BookS(525), BookS(plan.SectionY)", characters)
        self.assertIn("sectionY := rowY + 10", characters)
        self.assertIn("rowY := sectionY + sectionH + 12", characters)
        self.assertIn("raceY := rowY + 5", characters)
        self.assertIn('controls.Hint.Text = "" ? ddlY + ddlH + 12', characters)
        self.assertIn("MeasureAccessibleWrappedText(", characters)
        self.assertIn('SetCharacterBookLayoutExtra("Macros", plan.Extra)', characters)
        self.assertIn("ReflowProfileEditor()", characters)
        self.assertIn("if !shown\n        return\n    selectedIndex", macros)
        self.assertIn("controls.Species.Move(BookS(525), BookS(plan.DropdownY))", characters)
        self.assertIn("ButtonFaces[button.Hwnd].NoAccessibleDownfit := measured", characters)

    def test_settings_and_data_measure_existing_action_rows(self):
        root = SOURCE.parents[1] / "src/ui"
        settings = (root / "v016-refinements.ahk").read_text(encoding="utf-8-sig")
        renderer = (root / "renderer.ahk").read_text(encoding="utf-8-sig")
        self.assertIn("PlanV016MeasuredRows(groups)", settings)
        self.assertIn("copyExtra += ApplyV016MeasuredRows([[mainRows[1]]", settings)
        data = settings[settings.index("BuildV016LauncherDataRows(settings)\n{"):
                        settings.index("\nOpenAppDataSettingsV016(settings, *)")]
        self.assertIn("ApplyV016MeasuredRows([[rows[1]], [rows[2]], [rows[3]],\n"
                      "        [rows[4], rows[5]], [rows[6]], [rows[7]], [rows[8], rows[9]], [rows[10]]])", data)
        self.assertIn("rows[10].GetPos(, &backY, , &backHeight)", data)
        self.assertIn("return {Rows: rows, Extra: Max(0, backY + backHeight - V016S(513))}", data)
        self.assertIn("layout := BuildV016LauncherDataRows(settings)", settings)
        self.assertIn("copyExtra := layout.Extra", settings)
        self.assertIn("if GrowV016SettingsParchment(settings, copyExtra)", settings)
        self.assertIn("previousBottom + V016S(4) - originalTop", settings)
        self.assertIn("face.NoAccessibleDownfit := true", settings)
        self.assertIn("face.AccessibleWrappedButton := true", settings)
        self.assertIn("drawFlags := 0x0811", renderer)

    def test_accessible_native_measurements_use_matching_coordinate_units(self):
        root = SOURCE.parents[1] / "src/ui"
        windows = (root / "windows.ahk").read_text(encoding="utf-8-sig")
        characters = (root / "characters.ahk").read_text(encoding="utf-8-sig")
        settings = (root / "v016-refinements.ahk").read_text(encoding="utf-8-sig")
        self.assertIn("panel.AccessibleLayoutDpi := A_ScreenDPI / 96", windows)
        self.assertIn("Floor(width * dpi)", windows)
        self.assertIn('Ceil(NumGet(bounds, 12, "Int") / dpi)', windows)
        self.assertIn('Ceil(NumGet(bounds, 0, "Int") / dpi)', windows)
        self.assertIn("CharacterPage := CreateAccessibleLayoutGui(", characters)
        self.assertIn("settings := CreateAccessibleLayoutGui(", settings)
        self.assertNotIn("Round((w - padding) * A_ScreenDPI / 96)", settings)

    def test_book_smoke_artwork_uses_compiled_resource_root(self):
        smoke = (SOURCE.parents[1] / "scripts/launcher-smoke-tests.ahk").read_text(encoding="utf-8-sig")
        self.assertIn("assetRoot := A_IsCompiled ? BundledResourceRoot : A_ScriptDir", smoke)
        self.assertIn('path := assetRoot "\\assets\\backgrounds\\character-book.png"', smoke)
        self.assertNotIn('A_ScriptDir "\\assets\\backgrounds\\character-book.png"', smoke)
        # Audit every artwork constructor and reset, not a fixed call count.
        # New fixtures must use the helper without requiring a count update.
        self.assertEqual(smoke.count("\\assets\\backgrounds\\character-book.png"), 1)
        lines = smoke.splitlines()
        constructors = resets = 0
        for index, line in enumerate(lines):
            if ".BookBackground :=" in line:
                constructors += 1
                assignment = line.strip()
                if assignment.endswith(","):
                    assignment += " " + lines[index + 1].strip()
                self.assertTrue(assignment.endswith("GetBookSmokeArtworkPath())"), assignment)
            elif ".BookBackground.Value :=" in line:
                resets += 1
                self.assertTrue(line.strip().endswith(":= GetBookSmokeArtworkPath()"), line)
        self.assertGreater(constructors, 0)
        self.assertGreater(resets, 0)

    def test_inventory_serializes_with_expected_categories(self):
        report = audit.summarize(audit.inventory())
        self.assertEqual(report["scope"], ["src", "game-chat"])
        self.assertGreaterEqual(report["flagged_files"], 21)
        self.assertIn("files", report)
        self.assertTrue(all(item["findings"] for item in report["files"]))


if __name__ == "__main__":
    unittest.main()
