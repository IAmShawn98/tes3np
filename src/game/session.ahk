; Single-client login, sequential launches and crash recovery.

; Track successfully launched clients without retaining credentials or HWNDs.
global TES3NPActiveGamePids := []

CountTES3NPGameClients()
{
    global TES3NPActiveGamePids, Client
    live := []
    for pid in TES3NPActiveGamePids
        if pid && ProcessExist(pid)
            live.Push(pid)
    TES3NPActiveGamePids := live
    ; A game still undergoing automated login also occupies a slot.
    if IsObject(Client) && Client.Enabled && Client.PID && ProcessExist(Client.PID)
    {
        found := false
        for pid in live
            if pid = Client.PID
                found := true
        if !found
            return live.Length + 1
    }
    return live.Length
}

RememberTES3NPGameClient(pid)
{
    global TES3NPActiveGamePids
    if !pid
        return
    CountTES3NPGameClients()
    for existing in TES3NPActiveGamePids
        if existing = pid
            return
    TES3NPActiveGamePids.Push(pid)
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
    if !CanUseNPLauncher()
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
        MsgBox("TES3NP is still completing a character login. Try the next character when that login finishes.", "tes3np")
        return
    }
    if index < 1 || index > Profiles.Length || !CanStartAnotherTES3NPGame()
        return
    executable := GetSharedExecutable()
    if ValidateLaunch(Profiles[index], executable)
        StartProfileSession(Profiles[index], executable)
}

StartProfileSession(profile, executable)
{
    global Client, TES3MPLastMismatchEvidence
    ; Every login gets fresh mismatch evidence. Retain the previous result
    ; only while its own failed-login dialog is available for Copy Info.
    TES3MPLastMismatchEvidence := 0
    source := IsObject(profile) ? "Manual character" : "New Adventure"
    LogLauncherEvent("GAME | SOURCE | StartProfileSession | Source: " source " | Profile: " (IsObject(profile) ? "saved" : "new") ".")
    ; Release any retained process handle before replacing the Client record.
    if IsObject(Client) && Client.HasOwnProp("ProcessHandle") && Client.ProcessHandle
        DllCall("CloseHandle", "Ptr", Client.ProcessHandle)
    LogLauncherEvent("GAME | Launch requested | Profile: " (IsObject(profile) ? "saved" : "new") ".")
    global DataFile
    LogLauncherEvent("GAME | CLIENT | Mode: " IniRead(DataFile, "Launch", "ClientMode", "Bundled") " | Executable path omitted.")
    Client := {PID: 0, HWND: 0, Phase: "launch", Deadline: 0, Enabled: true, LaunchIssued: false,
        Profile: IsObject(profile) ? {Name: profile.Name, Password: profile.Password} : 0, Executable: executable,
        UsernameDelay: IsObject(profile) ? profile.UsernameDelay : 0,
        PasswordDelay: IsObject(profile) ? profile.PasswordDelay : 0,
        LoadDelay: IsObject(profile) ? profile.LoadDelay : 0, ProcessHandle: 0}
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
    if Client.HasOwnProp("ProcessHandle") && Client.ProcessHandle
    {
        DllCall("CloseHandle", "Ptr", Client.ProcessHandle)
        Client.ProcessHandle := 0
    }
    SetTimer(ClientTick, 0)
    ; Saved LoadDelay may be only one second. Keep the already-completed
    ; three-second visual alive when the successful manual watchdog ends.
    keepProgress := Client.HasOwnProp("KeepLoginProgress") && Client.KeepLoginProgress
        && LoginProgressMode = "complete" && A_TickCount < LoginProgressCloseAt
    if !keepProgress
    {
        SetTimer(UpdateGameLoginProgress, 0)
        DismissGameLoginProgress()
    }
    ToolTip(, , , 1)
    SetClientStatus("Recovery stopped. You can close the game normally.")
    if wasEnabled
        LogLauncherEvent("GAME | Recovery stopped | Previous phase: " phase ".")
}

SetClientStatus(text)
{
    global SessionStatus, Client
    Client.Status := text
    if IsSet(SessionStatus)
        SessionStatus.Text := text
    UpdateGameLoginProgress()
}

FindGameWindow(pid)
{
    for hwnd in WinGetList("ahk_pid " pid)
    {
        className := WinGetClass("ahk_id " hwnd)
        if className = "ConsoleWindowClass" || InStr(className, "Terminal")
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        if !InStr(className, "SDL")
            continue
        return hwnd
    }
    return 0
}

RetryClient(reason)
{
    global Client
    LogLauncherEvent("GAME | STOP | Profile: " (IsObject(Client.Profile) ? "saved" : "new") " | Reason: " reason ".")
    StopClient()
    SetClientStatus(reason " — session stopped.")
}

ClientTick()
{
    global Client, DataFile
    if !Client.Enabled
        return
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
            LogLauncherEvent("GAME | SOURCE | Executing TES3MP Run() | Profile: " (IsObject(Client.Profile) ? "saved" : "new") " | Phase: " Client.Phase ".")
            if !ValidateSelectedClientRuntime(Client.Executable)
                throw Error("Selected TES3MP runtime is incomplete.")
            SplitPath(Client.Executable, , &workingDirectory)
            Client.LogWatch := CaptureTES3MPLogBaseline()
            Run('"' Client.Executable '" --connect=' AppConfig.Server, workingDirectory, , &pid)
            Client.PID := pid
            ; Keep a process handle so Windows retains the real exit code even
            ; after the process disappears from ProcessExist().
            Client.ProcessHandle := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
            Client.Phase := "window"
            Client.Deadline := A_TickCount + AppConfig.GameWindowWaitMs
            LogLauncherEvent("GAME | TES3MP process started | PID: " pid ".")
        }
        ; Read only log output created after this launch. This is part of the
        ; existing client watchdog, not a parallel reconnect or polling timer.
        if Client.Phase != "launch" && CheckTES3MPPluginMismatch()
            return
        if !ProcessExist(Client.PID)
        {
            ; A closed or crashed client terminates this single monitored login.
            codeText := "unavailable"
            if Client.HasOwnProp("ProcessHandle") && Client.ProcessHandle
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
            LogLauncherEvent("GAME | EXIT | Process ended | Phase: " Client.Phase " | Exit code: " codeText " | Mode: " IniRead(DataFile, "Launch", "ClientMode", "Bundled") " | Executable path omitted.")
            LogLauncherEvent("GAME | Game process closed; login recovery stopped.")
            StopClient()
            SetClientStatus("Game closed.")
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
                    RememberTES3NPGameClient(Client.PID)
                    SetClientStatus("Game running. Create your character in-game.")
                    LogLauncherEvent("GAME | SUCCESS | Game session started for new adventure.")
                }
                else
                {
                    Client.Phase := "username"
                    SetGameLoginProgressStage(1)
                    Client.Deadline := A_TickCount + Client.UsernameDelay * 1000
                    SetClientStatus("Waiting for username screen — " Client.UsernameDelay " seconds.")
                    LogLauncherEvent("GAME | Login stage | Waiting for username screen.")
                }
            }
            else if A_TickCount >= Client.Deadline
                RetryClient("Game window did not appear")
            else
                SetClientStatus("Waiting for the game window (console does not count).")
            return
        }
        if !hwnd || hwnd != Client.HWND
        {
            RetryClient("Game window lost")
            return
        }
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
                RetryClient("Game window is unresponsive")
            return
        }
        remaining := Max(0, Ceil((Client.Deadline - A_TickCount) / 1000))
        if remaining > 0
        {
            label := Client.Phase = "username" ? "Waiting for username screen" : Client.Phase = "password" ? "Waiting for password screen" : "Loading character"
            SetClientStatus(label " — " remaining " seconds.")
            return
        }
        if Client.Phase = "loading"
        {
            Client.Phase := "playing"
            RememberTES3NPGameClient(Client.PID)
            SetClientStatus("Login inputs completed. You can return to TES3NP and launch another character (up to four clients).")
            LogLauncherEvent("GAME | SUCCESS | Login completed | Profile: saved | Active clients: " CountTES3NPGameClients() ".")
            ; Completed manual logins no longer hold the one-at-a-time login
            ; watchdog. Keep the game running and allow another launch.
            Client.KeepLoginProgress := true
            StopClient()
            return
        }
        WinActivate("ahk_id " hwnd)
        if !WinWaitActive("ahk_id " hwnd, , 2)
            throw Error("Could not focus game window")
        if Client.Phase = "username"
        {
            SetGameLoginProgressStage(2)
            SetClientStatus("Entering username...")
            LogLauncherEvent("GAME | Login stage | Entering username.")
            SendText(Client.Profile.Name)
            Send("{Enter}")
            SetGameLoginProgressStage(3)
            Client.Phase := "password"
            Client.Deadline := A_TickCount + Client.PasswordDelay * 1000
            SetClientStatus("Waiting for password screen — " Client.PasswordDelay " seconds.")
        }
        else if Client.Phase = "password"
        {
            SetGameLoginProgressStage(4)
            SetClientStatus("Entering password...")
            LogLauncherEvent("GAME | Login stage | Entering password. Password value not logged.")
            SendText(Client.Profile.Password)
            Send("{Enter}")
            ; Finish only the visual. The saved LoadDelay and recovery continue.
            CompleteGameLoginProgress(Client.Profile.Name, Client.PID, Client.HWND)
            Client.Phase := "loading"
            Client.Deadline := A_TickCount + Client.LoadDelay * 1000
            SetClientStatus("Loading character — " Client.LoadDelay " seconds.")
        }
        else
        {
            Client.Phase := "playing"
            RememberTES3NPGameClient(Client.PID)
            LogLauncherEvent("GAME | SUCCESS | Login state completed.")
            StopClient()
        }
    }
    catch Error as err
    {
        ; If Run() succeeded and a later launch/login step failed, do not leave
        ; the TES3MP process orphaned after recovery monitoring stops.
        failedPid := Client.HasOwnProp("PID") ? Client.PID : 0
        if failedPid && ProcessExist(failedPid)
            try ProcessClose(failedPid)
        Client.LaunchIssued := false
        LogLauncherEvent("GAME | ERROR | Client launch/login exception type: " Type(err) ".")
        RetryClient("Client launch or login failed")
    }
}

StartNewAdventure(*)
{
    if !CanUseNPLauncher()
        return
    global Client, DataFile
    if Client.Enabled
    {
        LogLauncherEvent("GAME | BLOCKED | New Adventure requested while another monitored session is active.")
        MsgBox("A game session is already being monitored. Use the tray menu to stop recovery before starting another.", "tes3np")
        return
    }
    if !CanStartAnotherTES3NPGame()
        return
    executable := GetSharedExecutable()
    if !ValidateSelectedClientRuntime(executable)
        return
    ; Use the same tracked launch watchdog so a new-adventure connection
    ; receives exactly the same fresh-log mismatch handling as saved profiles.
    LogLauncherEvent("GAME | New Adventure launch requested.")
    StartProfileSession(0, executable)
}
