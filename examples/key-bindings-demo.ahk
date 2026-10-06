#Requires AutoHotkey v2.0
#SingleInstance Force
; @tes3np-key Fish|Sneak / Fish|C
; @tes3np-key ReadyWeapon|Ready weapon|F
; This demonstration sends one action per hotkey, only to an active SDL game.
bindingsFile := EnvGet("TES3NP_BINDINGS")
fishKey := bindingsFile != "" ? IniRead(bindingsFile, "Bindings", "Fish", "C") : "C"
weaponKey := bindingsFile != "" ? IniRead(bindingsFile, "Bindings", "ReadyWeapon", "F") : "F"
MsgBox("Bindings loaded: Fish = " fishKey ", Ready weapon = " weaponKey ".`n`nF8 sends Fish; F7 sends Ready weapon when the SDL game is active. F9 closes this demo.", "tes3np binding demo")
#HotIf InStr(WinGetClass("A"), "SDL")
F8::Send("{" fishKey "}")
F7::Send("{" weaponKey "}")
#HotIf
F9::ExitApp()
