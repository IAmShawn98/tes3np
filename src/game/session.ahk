; Serialized login and tracking of launched game clients.

; Track successfully launched clients without retaining credentials or HWNDs.
global TES3NPActiveGameHandles := []

CountTES3NPGameClients()
{
    global TES3NPActiveGameHandles, Client
    live := []
    count := 0
    for handle in TES3NPActiveGameHandles
    {
        running := DllCall("WaitForSingleObject", "Ptr", handle, "UInt", 0, "UInt") = 258
        if running
            count += 1
        if running || (Client.Enabled && Client.ProcessHandle = handle)
            live.Push(handle)
        else
            DllCall("CloseHandle", "Ptr", handle)
    }
    TES3NPActiveGameHandles := live
    return count
}

ReleaseTES3NPGameClients()
{
    global TES3NPActiveGameHandles
    for handle in TES3NPActiveGameHandles
        DllCall("CloseHandle", "Ptr", handle)
    TES3NPActiveGameHandles := []
}

CanStartAnotherTES3NPGame()
{
    count := CountTES3NPGameClients()
    if count >= 4
    {
        LogLauncherEvent("GAME | BLOCKED | Four TES3MP clients are already running.")
        MsgBox("TES3NP allows up to four simultaneous TES3MP clients. Close one game client before launching another.", "Game client limit")
        return false
    }
    return true
}

LaunchProfile(*)
{
    global SelectedProfile
    LaunchProfileIndex(SelectedProfile)
}

PlayVisibleProfile(position, *)
{
    global CharacterListPage
    LaunchProfileIndex((CharacterListPage - 1) * 10 + position)
}

ValidateLaunch(profile, executable)
{
    if !EnsureMorrowindForGameLaunch()
        return false
    SplitPath(executable, &filename)
    if StrLower(filename) != "tes3mp.exe" || !FileExist(executable)
    {
        LogLauncherEvent("GAME | BLOCKED | Selected TES3MP executable is missing or invalid.")
        MsgBox("TES3MP executable not found:" Chr(10) executable Chr(10) Chr(10) "Open Launcher Settings to select a working client, or return to the bundled one.", "Missing TES3MP client", "Icon!")
        return false
    }
    if !ValidateSelectedClientRuntime(executable)
        return false
    if profile.Password = ""
    {
        LogLauncherEvent("GAME | BLOCKED | Character credentials require attention.")
        MsgBox("Edit " profile.Name " and re-enter their password.", "tes3np")
        return false
    }
    return true
}

LaunchProfileIndex(index)
{
    LogLauncherEvent("GAME | SOURCE | Manual character launch requested | Index: " index ".")
    global Client, Profiles
    if Client.Enabled
    {
        LogLauncherEvent("GAME | BLOCKED | Launch requested while another monitored session is active.")
        if Client.Phase = "launch" || Client.Phase = "window"
            return
        MsgBox("TES3NP is still completing a character login. Try the next character when that login finishes.", "tes3np")
        return
    }
    if index < 1 || index > Profiles.Length || !CanUseNPLauncher() || !CanStartAnotherTES3NPGame()
        return
    profile := Profiles[index]
    executable := GetSharedExecutable()
    if ValidateLaunch(profile, executable)
        StartProfileSession(profile, executable)
}

StartProfileSession(profile, executable)
{
    global Client, TES3MPLastMismatchEvidence, DataFile
    ; A file picker or prompt can yield to another launch request.
    if Client.Enabled || !CanUseNPLauncher() || !CanStartAnotherTES3NPGame()
        return
    previousCritical := Critical("On")
    try
    {
        if Client.Enabled || PatchInProgress()
            return
        session := {PID: 0, HWND: 0, Phase: "launch", Deadline: 0, Enabled: true, LaunchIssued: false,
            Profile: IsObject(profile) ? {Name: profile.Name, Password: profile.Password} : 0, Executable: executable,
            UsernameDelay: IsObject(profile) ? profile.UsernameDelay : 0,
            PasswordDelay: IsObject(profile) ? profile.PasswordDelay : 0,
            LoadDelay: IsObject(profile) ? profile.LoadDelay : 0, ProcessHandle: 0}
        Client := session
    }
    finally Critical(previousCritical)
    ResetPendingExpansionPromptForNewLaunch()
    ; Every login gets fresh mismatch evidence. Retain the previous result
    ; only while its own failed-login dialog is available for Copy Info.
    TES3MPLastMismatchEvidence := 0
    source := IsObject(profile) ? "Manual character" : "New Adventure"
    profileName := IsObject(profile) ? profile.Name : "New Adventure"
    LogLauncherEvent("GAME | SOURCE | StartProfileSession | Source: " source " | Character: " profileName ".")
    LogLauncherEvent("GAME | Launch requested | Character: " profileName ".")
    LogLauncherEvent("GAME | CLIENT | Mode: " IniRead(DataFile, "Launch", "ClientMode", "Bundled"))
    if Client != session || !Client.Enabled
        return
    if IsObject(profile)
    {
        BeginGameLoginProgress(profile.Name, profile.HasOwnProp("Species") ? profile.Species : "",
            profile.HasOwnProp("PortraitFile") ? profile.PortraitFile : "")
        SetTimer(UpdateGameLoginProgress, AppConfig.TooltipMs)
    }
    SetTimer(ClientTick, AppConfig.WatchdogMs)
    ClientTick()
}

StopClient(*)
{
    global Client, LoginProgressMode, LoginProgressCloseAt
    wasEnabled := Client.Enabled
    phase := Client.Phase
    Client.Enabled := false
    Client.Phase := "stopped"
    SetTimer(ClientTick, 0)
    ; Saved LoadDelay may be only one second. Keep the already-completed
    ; three-second visual alive when the successful manual watchdog ends.
    keepProgress := Client.HasOwnProp("KeepLoginProgress") && Client.KeepLoginProgress
        && LoginProgressMode = "complete" && A_TickCount < LoginProgressCloseAt
    if !keepProgress
    {
        SetTimer(UpdateGameLoginProgress, 0)
        ; Cancellation, crash, plugin rejection and manual Stop must tear
        ; down the native always-on-top card, not merely clear its state.
        DisposeGameLoginProgress()
    }
    Client.Profile := 0
    Client.ProcessHandle := 0
    if wasEnabled
        LogLauncherEvent("GAME | Recovery stopped | Previous phase: " phase ".")
}

FindGameWindow(pid)
{
    for hwnd in WinGetList("ahk_pid " pid)
    {
        ; The window can disappear while the process is closing.
        try className := WinGetClass("ahk_id " hwnd)
        catch
            continue
        if !InStr(className, "SDL") || !DllCall("IsWindowVisible", "Ptr", hwnd)
            continue
        return hwnd
    }
    return 0
}

EndClientMonitoring(reason)
{
    global Client
    profileName := IsObject(Client.Profile) ? Client.Profile.Name : "New Adventure"
    LogLauncherEvent("GAME | STOP | Character: " profileName " | Reason: " reason ".")
    StopClient()
}

ClientTick()
{
    global Client, DataFile, TES3NPActiveGameHandles
    if !Client.Enabled
        return
    session := Client
    try
    {
        if Client.Phase = "launch"
        {
            ; Claim this launch attempt before Run(). If the watchdog re-enters while
            ; Run is still in progress, the second invocation exits instead of
            ; starting another TES3MP process.
            if Client.LaunchIssued
                return
            Client.LaunchIssued := true
            LogLauncherEvent("GAME | SOURCE | Executing TES3MP Run() | Character: " (IsObject(Client.Profile) ? Client.Profile.Name : "New Adventure") " | Phase: " Client.Phase ".")
            if !ValidateSelectedClientRuntime(Client.Executable)
                throw Error("Selected TES3MP runtime is incomplete.")
            ; Recheck the game files immediately before starting the process.
            if !EnsureMorrowindForGameLaunch()
            {
                if Client = session
                    StopClient()
                return
            }
            if Client != session || !Client.Enabled
                return
            SplitPath(Client.Executable, , &workingDirectory)
            Client.LogWatch := CaptureTES3MPLogBaseline()
            Run('"' Client.Executable '" --connect=' AppConfig.Server, workingDirectory, , &pid)
            Client.PID := pid
            ; Keep a handle for the lifetime of the launched process, including
            ; after the login controller has stopped watching it.
            handle := DllCall("OpenProcess", "UInt", 0x101001, "Int", 0, "UInt", pid, "Ptr")
            if !handle
                handle := DllCall("OpenProcess", "UInt", 0x101000, "Int", 0, "UInt", pid, "Ptr")
            if handle
            {
                Client.ProcessHandle := handle
                TES3NPActiveGameHandles.Push(handle)
            }
            Client.Phase := "window"
            Client.Deadline := A_TickCount + AppConfig.GameWindowWaitMs
            LogLauncherEvent("GAME | TES3MP process started | PID: " pid ".")
        }
        ; Read only log output created after this launch. This is part of the
        ; existing client watchdog, not a parallel reconnect or polling timer.
        if Client.Phase != "launch" && CheckTES3MPPluginMismatch()
            return
        running := Client.ProcessHandle
            ? DllCall("WaitForSingleObject", "Ptr", Client.ProcessHandle, "UInt", 0, "UInt") = 258
            : ProcessExist(Client.PID)
        if !running
        {
            ; A rejected client may exit before its last log writes are flushed.
            ; Keep the existing watchdog alive briefly to capture only NEW
            ; mismatch evidence, then stop normally if nothing appears.
            if !Client.HasOwnProp("MismatchExitGraceUntil")
            {
                Client.MismatchExitGraceUntil := A_TickCount + 2000
                return
            }
            if A_TickCount < Client.MismatchExitGraceUntil
                return
            ; A closed or crashed client terminates this single monitored login.
            codeText := "unavailable"
            exitCode := -1
            if Client.ProcessHandle
            {
                resultCode := Buffer(4, 0)
                if DllCall("GetExitCodeProcess", "Ptr", Client.ProcessHandle, "Ptr", resultCode)
                {
                    exitCode := NumGet(resultCode, 0, "UInt")
                    codeText := Format("0x{:08X}", exitCode)
                    if exitCode = 0
                        codeText .= " (normal exit)"
                    else if exitCode = 0xC0000005
                        codeText .= " (access violation)"
                    else if exitCode = 0xC0000409
                        codeText .= " (stack buffer overrun / fail-fast)"
                    else if exitCode = 0xC000001D
                        codeText .= " (illegal instruction)"
                }
            }
            LogLauncherEvent("GAME | EXIT | Process ended | Phase: " Client.Phase " | Exit code: " codeText " | Mode: " IniRead(DataFile, "Launch", "ClientMode", "Bundled"))
            LogLauncherEvent("GAME | Game process closed; login recovery stopped.")
            failedToStart := Client.Phase = "window"
            StopClient()
            if failedToStart
            {
                message := "TES3MP closed before a game window opened. Exit code: " codeText "."
                if exitCode = 0xC0000135 || exitCode = 0xC0000139 || exitCode = 0xC000007B
                    message .= Chr(10) Chr(10) "For a custom EXE, add the DLLs from the same build in Game Client Settings."
                MsgBox(message, "TES3MP Startup Failed", "Icon!")
            }
            return
        }
        hwnd := FindGameWindow(Client.PID)
        if Client.Phase = "window"
        {
            if hwnd
            {
                Client.HWND := hwnd
                LogLauncherEvent("GAME | TES3MP game window detected.")
                if !IsObject(Client.Profile)
                {
                    Client.Phase := "playing"
                    Client.Deadline := A_TickCount + 15000
                    LogLauncherEvent("GAME | SUCCESS | Game session started for new adventure.")
                }
                else
                {
                    Client.Phase := "username"
                    SetGameLoginProgressStage(1)
                    Client.Deadline := A_TickCount + Client.UsernameDelay * 1000
                    LogLauncherEvent("GAME | Login stage | Waiting for username screen.")
                }
            }
            else if A_TickCount >= Client.Deadline
            {
                EndClientMonitoring("Game window did not appear")
                MsgBox("TES3MP did not open a game window in time. Check for a TES3MP error window and close the client if it is still running.",
                    "TES3MP Startup Timed Out", "Icon!")
            }
            return
        }
        if !hwnd || hwnd != Client.HWND
        {
            ; The game can replace its SDL window with a plugin-error window.
            ; Give the existing fresh-log checker time to catch that rejection.
            if !Client.HasOwnProp("MismatchWindowGraceUntil") || !Client.MismatchWindowGraceUntil
                Client.MismatchWindowGraceUntil := A_TickCount + 2000
            if A_TickCount >= Client.MismatchWindowGraceUntil
                EndClientMonitoring("Game window lost")
            return
        }
        Client.MismatchWindowGraceUntil := 0
        if Client.Phase = "playing"
        {
            ; A new-adventure launch needs a short connection-error watch, not
            ; a permanent second login controller or continuous game monitoring.
            if !IsObject(Client.Profile) && A_TickCount >= Client.Deadline
            {
                StopClient()
                return
            }
            if DllCall("IsHungAppWindow", "Ptr", hwnd)
                EndClientMonitoring("Game window is unresponsive")
            return
        }
        if A_TickCount < Client.Deadline
            return
        if Client.Phase = "loading"
        {
            Client.Phase := "playing"
            LogLauncherEvent("GAME | SUCCESS | Login completed | Character: " Client.Profile.Name " | Active clients: " CountTES3NPGameClients() ".")
            ; Completed manual logins no longer hold the one-at-a-time login
            ; watchdog. Keep the game running and allow another launch.
            Client.KeepLoginProgress := true
            StopClient()
            return
        }
        if Client != session || !Client.Enabled
            return
        WinActivate("ahk_id " hwnd)
        focused := WinWaitActive("ahk_id " hwnd, , 2)
        if Client != session || !Client.Enabled
            return
        if !focused
            throw Error("Could not focus game window")
        ; The tray stop action can run while WinWaitActive is waiting.
        previousCritical := A_IsCritical
        Critical("On")
        try
        {
            if Client != session || !Client.Enabled || Client.HWND != hwnd
                return
            if !WinActive("ahk_id " hwnd)
                return
            if Client.Phase = "username"
            {
                SetGameLoginProgressStage(2)
                LogLauncherEvent("GAME | Login stage | Entering username.")
                if !WinActive("ahk_id " hwnd) || WinGetPID("ahk_id " hwnd) != session.PID
                    return
                SendText(Client.Profile.Name)
                Send("{Enter}")
                SetGameLoginProgressStage(3)
                Client.Phase := "password"
                Client.Deadline := A_TickCount + Client.PasswordDelay * 1000
            }
            else if Client.Phase = "password"
            {
                SetGameLoginProgressStage(4)
                LogLauncherEvent("GAME | Login stage | Entering password.")
                if !WinActive("ahk_id " hwnd) || WinGetPID("ahk_id " hwnd) != session.PID
                    return
                SendText(Client.Profile.Password)
                Send("{Enter}")
                ; Finish only the visual. The saved LoadDelay and recovery continue.
                CompleteGameLoginProgress(Client.Profile.Name, Client.PID, Client.HWND)
                Client.Phase := "loading"
                Client.Deadline := A_TickCount + Client.LoadDelay * 1000
            }
        }
        finally Critical(previousCritical)
    }
    catch Error as err
    {
        if Client != session || !Client.Enabled
            return
        ; If Run() succeeded and a later launch/login step failed, do not leave
        ; the TES3MP process orphaned after recovery monitoring stops.
        if Client.ProcessHandle
            DllCall("TerminateProcess", "Ptr", Client.ProcessHandle, "UInt", 0)
        LogLauncherEvent("GAME | ERROR | Client launch/login exception type: " Type(err) ".")
        failedToStart := Client.Phase = "launch" || Client.Phase = "window"
        EndClientMonitoring("Client launch or login failed")
        if failedToStart
            MsgBox("TES3MP could not start. Check the selected executable and its dependencies in Game Client Settings.",
                "TES3MP Startup Failed", "Icon!")
    }
}

StartNewAdventure(*)
{
    if !CanUseNPLauncher()
        return
    global Client
    if Client.Enabled
    {
        LogLauncherEvent("GAME | BLOCKED | New Adventure requested while another monitored session is active.")
        MsgBox("A game session is already being monitored. Use the tray menu to stop recovery before starting another.", "tes3np")
        return
    }
    if !CanStartAnotherTES3NPGame()
        return
    if !EnsureMorrowindForGameLaunch()
        return
    executable := GetSharedExecutable()
    if !ValidateSelectedClientRuntime(executable)
        return
    ; Use the same tracked launch watchdog so a new-adventure connection
    ; receives exactly the same fresh-log mismatch handling as saved profiles.
    LogLauncherEvent("GAME | New Adventure launch requested.")
    StartProfileSession(0, executable)
}
