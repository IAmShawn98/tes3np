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

LaunchAllCharacters(*)
{
    LogLauncherEvent("GAME | SOURCE | LaunchAllCharacters invoked.")
    global Client, Profiles, DataFile, CharacterPage
    if Client.Enabled
    {
        LogLauncherEvent("GAME | BLOCKED | Launch-all requested while another monitored session is active.")
        MsgBox("A game session is already running. Stop recovery from the tray before launching all characters.", "tes3np")
        return
    }
    if Profiles.Length < 2
        return
    if !CanStartAnotherTES3NPGame()
        return
    if Profiles.Length > 4 - CountTES3NPGameClients()
    {
        MsgBox("This would exceed the four-client server limit. Choose fewer characters or close running clients.", "Game client limit")
        return
    }
    executable := GetSharedExecutable()
    queue := []
    for profile in Profiles
    {
        if !ValidateLaunch(profile, executable)
            return
        queue.Push(profile.Clone())
    }
    if IniRead(DataFile, "Launcher", "HideLaunchAllExplanation", "0") != "1"
        if !ShowLaunchAllExplanation()
            return
    profile := queue.RemoveAt(1)
    LogLauncherEvent("GAME | Batch launch requested. Characters: " (queue.Length + 1) ".")
    StartProfileSession(profile, executable, queue)
}

StartProfileSession(profile, executable, queue := 0, scheduledDailyLogin := false, scheduledLoginAction := "", keptPids := 0)
{
    global Client
    source := scheduledDailyLogin ? "Daily Login" : IsObject(queue) ? "Batch" : "Manual character"
    LogLauncherEvent("GAME | SOURCE | StartProfileSession | Source: " source " | Character: " profile.Name ".")
    ; Batch transitions replace the old Client record without going through
    ; StopClient, so release its retained process handle first.
    if IsObject(Client) && Client.HasOwnProp("ProcessHandle") && Client.ProcessHandle
        DllCall("CloseHandle", "Ptr", Client.ProcessHandle)
    batchText := IsObject(queue) ? " | Batch remaining after this character: " queue.Length : ""
    LogLauncherEvent("GAME | Launch requested | Character: " profile.Name batchText ".")
    global DataFile
    LogLauncherEvent("GAME | CLIENT | Mode: " IniRead(DataFile, "Launch", "ClientMode", "Bundled") " | Executable: " executable ".")
    Client := {PID: 0, HWND: 0, Phase: "launch", Deadline: 0, Enabled: true, LaunchIssued: false,
        Profile: {Name: profile.Name, Password: profile.Password}, Executable: executable,
        UsernameDelay: profile.UsernameDelay, PasswordDelay: profile.PasswordDelay,
        LoadDelay: profile.LoadDelay, Queue: queue,
        ScheduledDailyLogin: scheduledDailyLogin, ScheduledLoginAction: scheduledLoginAction, KeptPids: IsObject(keptPids) ? keptPids : [], ProcessHandle: 0,
        LoginCompletionPending: false}
    BeginGameLoginProgress(profile.Name, profile.HasOwnProp("Species") ? profile.Species : "")
    SetTimer(UpdateGameLoginProgress, AppConfig.TooltipMs)
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
    profileName := IsObject(Client.Profile) ? Client.Profile.Name : "New Adventure"
    LogLauncherEvent("GAME | STOP | Character: " profileName " | Reason: " reason ".")
    if IsObject(Client.Queue)
        Client.Queue := 0
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
            LogLauncherEvent("GAME | SOURCE | Executing TES3MP Run() | Character: " Client.Profile.Name " | Phase: " Client.Phase ".")
            if !ValidateSelectedClientRuntime(Client.Executable)
                throw Error("Selected TES3MP runtime is incomplete.")
            SplitPath(Client.Executable, , &workingDirectory)
            Run('"' Client.Executable '" --connect=' AppConfig.Server, workingDirectory, , &pid)
            Client.PID := pid
            ; Keep a process handle so Windows retains the real exit code even
            ; after the process disappears from ProcessExist().
            Client.ProcessHandle := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
            Client.Phase := "window"
            Client.Deadline := A_TickCount + AppConfig.GameWindowWaitMs
            LogLauncherEvent("GAME | TES3MP process started | PID: " pid ".")
        }
        if Client.Phase = "closing"
        {
            if ProcessExist(Client.PID)
            {
                if A_TickCount >= Client.Deadline
                {
                    try ProcessClose(Client.PID)
                    Client.Deadline := A_TickCount + AppConfig.RetryMs
                }
                return
            }
            if Client.Queue.Length
            {
                queue := Client.Queue
                profile := queue.RemoveAt(1)
                LogLauncherEvent("GAME | Batch advancing to next character | Remaining after next: " queue.Length ".")
                StartProfileSession(profile, Client.Executable, queue, Client.HasOwnProp("ScheduledDailyLogin") && Client.ScheduledDailyLogin, Client.HasOwnProp("ScheduledLoginAction") ? Client.ScheduledLoginAction : "", Client.HasOwnProp("KeptPids") ? Client.KeptPids : 0)
            }
            else
            {
                LogLauncherEvent("GAME | SUCCESS | All batch characters completed.")
                scheduledDailyLogin := Client.HasOwnProp("ScheduledDailyLogin") && Client.ScheduledDailyLogin
                if scheduledDailyLogin
                    MarkScheduledDailyLoginComplete()
                StopClient()
                SetClientStatus("All characters completed. Game clients closed.")
            }
            return
        }
        if !ProcessExist(Client.PID)
        {
            ; Only the explicit "closing" phase above is allowed to advance a
            ; Daily Login queue. If TES3MP disappears during any other phase,
            ; the user closed it (or it exited unexpectedly), so cancel the
            ; entire monitored session instead of logging another character in.
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
            LogLauncherEvent("GAME | EXIT | Process ended | Phase: " Client.Phase " | Exit code: " codeText " | Mode: " IniRead(DataFile, "Launch", "ClientMode", "Bundled") " | Executable: " Client.Executable ".")
            LogLauncherEvent("GAME | Game process closed; session and queued launches cancelled.")
            scheduledDailyLogin := Client.HasOwnProp("ScheduledDailyLogin") && Client.ScheduledDailyLogin
            if IsObject(Client.Queue)
                Client.Queue := 0
            if scheduledDailyLogin
                CancelScheduledDailyLoginForToday()
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
            if DllCall("IsHungAppWindow", "Ptr", hwnd)
                RetryClient("Game window is unresponsive")
            return
        }
        remaining := Max(0, Ceil((Client.Deadline - A_TickCount) / 1000))
        if remaining > 0
        {
            label := Client.Phase = "username" ? "Waiting for username screen" : Client.Phase = "password" ? "Waiting for password screen" : Client.Phase = "claim" ? "Collecting daily login points" : "Loading character"
            SetClientStatus(label " — " remaining " seconds.")
            return
        }
        if Client.Phase = "claim"
        {
            Client.Phase := "closing"
            Client.Deadline := A_TickCount + AppConfig.RetryMs
            SetClientStatus("Closing " Client.Profile.Name " before the next character...")
            LogLauncherEvent("GAME | Batch character claim wait completed; closing client.")
            WinClose("ahk_id " hwnd)
            return
        }
        if Client.Phase = "loading" && IsObject(Client.Queue)
        {
            if Client.HasOwnProp("ScheduledLoginAction") && Client.ScheduledLoginAction = "LoginUpTo4"
            {
                ; Preserve the three-second scheduled post-load handoff buffer,
                ; independent of the completed login progress window.
                if !Client.LoginCompletionPending
                {
                    Client.LoginCompletionPending := true
                    Client.Deadline := A_TickCount + 3000
                    return
                }
                keptPids := Client.HasOwnProp("KeptPids") ? Client.KeptPids : []
                keptPids.Push(Client.PID)
                RememberTES3NPGameClient(Client.PID)
                if Client.Queue.Length
                {
                    queue := Client.Queue
                    profile := queue.RemoveAt(1)
                    executable := Client.Executable
                    scheduled := Client.HasOwnProp("ScheduledDailyLogin") && Client.ScheduledDailyLogin
                    action := Client.ScheduledLoginAction
                    LogLauncherEvent("GAME | Scheduled multi-login advancing | Logged in: " keptPids.Length " | Remaining: " queue.Length ".")
                    StartProfileSession(profile, executable, queue, scheduled, action, keptPids)
                }
                else
                {
                    LogLauncherEvent("GAME | SUCCESS | Scheduled multi-login completed | Characters left logged in: " keptPids.Length ".")
                    MarkScheduledDailyLoginComplete()
                    StopClient()
                    SetClientStatus("Up to 4 scheduled characters are logged in.")
                }
                return
            }
            Client.Phase := "claim"
            Client.Deadline := A_TickCount + AppConfig.ClaimWaitMs
            SetClientStatus("Waiting 10 seconds for " Client.Profile.Name " before closing.")
            LogLauncherEvent("GAME | Login inputs completed | Batch character loaded; waiting for claim period.")
            return
        }
        if Client.Phase = "loading"
        {
            Client.Phase := "playing"
            RememberTES3NPGameClient(Client.PID)
            SetClientStatus("Login inputs completed. You can return to TES3NP and launch another character (up to four clients).")
            LogLauncherEvent("GAME | SUCCESS | Login completed | Character: " Client.Profile.Name " | Active clients: " CountTES3NPGameClients() ".")
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
        LogLauncherEvent("GAME | ERROR | Client launch/login exception: " err.Message ".")
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
    SplitPath(executable, , &workingDirectory)
    LogLauncherEvent("GAME | New Adventure launch requested.")
    try
    {
        Run('"' executable '" --connect=' AppConfig.Server, workingDirectory, , &pid)
        RememberTES3NPGameClient(pid)
        LogLauncherEvent("GAME | SUCCESS | New Adventure TES3MP process started | PID: " pid ".")
    }
    catch Error as err
    {
        LogLauncherEvent("GAME | ERROR | Could not start New Adventure: " err.Message ".")
        MsgBox("Could not launch TES3MP. Check the selected executable and try again.", "tes3np")
    }
}
