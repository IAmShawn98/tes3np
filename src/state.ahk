; Shared application state. Initialized before the UI is constructed.
global Profiles := []
global Client := {PID: 0, HWND: 0, Phase: "stopped", Deadline: 0, Enabled: false, Profile: 0, ProcessHandle: 0}
global CharacterPage := 0
global AppDataDirectory := A_AppData "\tes3np"
global DataFile := AppDataDirectory "\settings.ini"
; Full user-data reset closes ChatHost and exits without repopulating settings.
global LauncherDataResetting := false

global SelectedProfile := 0
global CharacterRows := []
global CharacterListPage := 1
global MaxCharacters := 10
global EditorControls := []
global InterfaceUpdateDepth := 0
global InterfaceFrameCover := 0
global InterfaceUpdateGui := 0
global InterfaceLoadingText := "Waiting for Jiub..."
global InterfaceCompletedSteps := 0
global InterfaceTotalSteps := 1
global InterfaceUpdating := false

; Main-window controls are assigned during BuildFrontPage.
global LauncherGui, DragStrip, LauncherHeading
global ButtonFaces := Map()
global HoverButton := 0
global PressedButton := 0
global IconHandles := []
global HoverTimer := UpdateButtonHover

; Feature state has one initialization point, before any GUI or timer exists.
global MacroPage := 0
global MacroList := 0
global MacroScrollOffset := 0
global MacroBookRows := []
global MacroBookControls := []
global MacroNameEdit := 0
global MacroEmptyNotice := 0
global MacroItems := []
global MacroImport := 0
global MacroRoot := AppDataDirectory "\macros"
global PatchJob := 0
global PatchFrame := 0
global ExpansionRecoveryRunning := false
global ExpansionRecoveryPending := false
global ExpansionToggleRunning := false

; Shared defaults; saved profile keys and runtime phase names remain compatible.
global AppConfig := {Version: "0.1.21-alpha.2", Server: "NerevarineProphecies.servegame.com:25565",
    Wiki: "https://wiki.nerevarineprophecies.com/Main_Page", UsernameDelay: 20,
    PasswordDelay: 3, LoadDelay: 20, WatchdogMs: 1000, TooltipMs: 100,
    GameWindowWaitMs: 30000}
