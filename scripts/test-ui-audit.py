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

    def test_inventory_serializes_with_expected_categories(self):
        report = audit.summarize(audit.inventory())
        self.assertEqual(report["scope"], ["src", "game-chat"])
        self.assertGreaterEqual(report["flagged_files"], 21)
        self.assertIn("files", report)
        self.assertTrue(all(item["findings"] for item in report["files"]))


if __name__ == "__main__":
    unittest.main()
