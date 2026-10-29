; Single-client login, sequential launches and crash recovery.

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
        LogLauncherEvent("GAME | BLOCKED | TES3MP executable is missing or invalid.")
        MsgBox("The bundled markerless client is not beside this launcher." Chr(10) Chr(10) "Expected: " executable Chr(10) Chr(10) "Run tes3np.exe from the complete dist\\tes3np-windows folder, or extract the entire TES3NP release ZIP. Keep the client folder beside tes3np.exe.", "Missing bundled client", "Icon!")
        return false
    }
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
        MsgBox("A game session is already running. Stop recovery from the tray before launching another.", "tes3np")
        return
    }
    if index < 1 || index > Profiles.Length
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
    batchText := IsObject(queue) ? " | Batch remaining after this character: " queue.Length : ""
    LogLauncherEvent("GAME | Launch requested | Character: " profile.Name batchText ".")
    Client := {PID: 0, HWND: 0, Phase: "launch", Deadline: 0, Enabled: true, LaunchIssued: false,
        Profile: {Name: profile.Name, Password: profile.Password}, Executable: executable,
        UsernameDelay: profile.UsernameDelay, PasswordDelay: profile.PasswordDelay,
        LoadDelay: profile.LoadDelay, Queue: queue,
        ScheduledDailyLogin: scheduledDailyLogin, ScheduledLoginAction: scheduledLoginAction, KeptPids: IsObject(keptPids) ? keptPids : []}
    SetTimer(UpdateGameStatusTooltip, AppConfig.TooltipMs)
    SetTimer(ClientTick, AppConfig.WatchdogMs)
    ClientTick()
}

StopClient(*)
{
    global Client
    wasEnabled := Client.Enabled
    phase := Client.Phase
    Client.Enabled := false
    Client.Phase := "stopped"
    SetTimer(ClientTick, 0)
    SetTimer(UpdateGameStatusTooltip, 0)
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
    UpdateGameStatusTooltip()
}

UpdateGameStatusTooltip(*)
{
    global Client
    static lastText := "", lastX := -1, lastY := -1
    try
    {
        if !Client.Enabled || Client.Phase = "playing" || !Client.HWND || !Client.HasOwnProp("Status")
            throw Error("No active game status")
        target := "ahk_id " Client.HWND
        if !WinActive(target) || WinGetPID(target) != Client.PID || !InStr(WinGetClass(target), "SDL")
            throw Error("Game is not the active window")
        if WinGetMinMax(target) = -1
            throw Error("Game is minimized")
        point := Buffer(8, 0)
        loginEntry := Client.Phase = "username" || Client.Phase = "password"
        clientRect := Buffer(16, 0)
        if !DllCall("GetClientRect", "Ptr", Client.HWND, "Ptr", clientRect)
            throw Error("Game dimensions unavailable")
        width := NumGet(clientRect, 8, "Int"), height := NumGet(clientRect, 12, "Int")
        localX := loginEntry ? Round(width / 2) : 16
        localY := loginEntry ? Max(16, Round(height / 2 - 75)) : 16
        NumPut("Int", localX, "Int", localY, point)
        if !DllCall("ClientToScreen", "Ptr", Client.HWND, "Ptr", point)
            throw Error("Game window is unavailable")
        x := NumGet(point, 0, "Int"), y := NumGet(point, 4, "Int")
        text := "tes3np — " Client.Status
        if text != lastText || x != lastX || y != lastY
        {
            CoordMode("ToolTip", "Screen")
            ToolTip(text, x, y, 1)
            if loginEntry
            {
                tooltipWindow := WinExist("ahk_class tooltips_class32 ahk_pid " ProcessExist())
                if tooltipWindow
                {
                    WinGetPos(, , &tooltipWidth, &tooltipHeight, "ahk_id " tooltipWindow)
                    origin := Buffer(8, 0)
                    DllCall("ClientToScreen", "Ptr", Client.HWND, "Ptr", origin)
                    left := NumGet(origin, 0, "Int")
                    tooltipX := Max(left, Min(x - Round(tooltipWidth / 2), left + width - tooltipWidth))
                    DllCall("SetWindowPos", "Ptr", tooltipWindow, "Ptr", 0,
                        "Int", tooltipX, "Int", y, "Int", 0, "Int", 0, "UInt", 0x15)
                }
            }
            lastText := text, lastX := x, lastY := y
        }
    }
    catch
    {
        ToolTip(, , , 1)
        lastText := "", lastX := -1, lastY := -1
    }
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
    global Client
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
            if !PrepareMarkerlessClientRuntime()
                throw Error("TES3MP runtime folder was not found.")
            workingDirectory := FindTES3MPFolder()
            Run('"' Client.Executable '" --connect=' AppConfig.Server, workingDirectory, , &pid)
            Client.PID := pid
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
                keptPids := Client.HasOwnProp("KeptPids") ? Client.KeptPids : []
                keptPids.Push(Client.PID)
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
            SetClientStatus("Login inputs completed.")
            LogLauncherEvent("GAME | SUCCESS | Login completed | Character: " Client.Profile.Name ".")
            return
        }
        WinActivate("ahk_id " hwnd)
        if !WinWaitActive("ahk_id " hwnd, , 2)
            throw Error("Could not focus game window")
        if Client.Phase = "username"
        {
            SetClientStatus("Entering username...")
            LogLauncherEvent("GAME | Login stage | Entering username.")
            SendText(Client.Profile.Name)
            Send("{Enter}")
            Client.Phase := "password"
            Client.Deadline := A_TickCount + Client.PasswordDelay * 1000
            SetClientStatus("Waiting for password screen — " Client.PasswordDelay " seconds.")
        }
        else if Client.Phase = "password"
        {
            SetClientStatus("Entering password...")
            LogLauncherEvent("GAME | Login stage | Entering password. Password value not logged.")
            SendText(Client.Profile.Password)
            Send("{Enter}")
            Client.Phase := "loading"
            Client.Deadline := A_TickCount + Client.LoadDelay * 1000
            SetClientStatus("Loading character — " Client.LoadDelay " seconds.")
        }
        else
        {
            Client.Phase := "playing"
            SetClientStatus("Login inputs completed.")
            LogLauncherEvent("GAME | SUCCESS | Login state completed.")
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
    executable := GetSharedExecutable()
    if !FileExist(executable) || !PrepareMarkerlessClientRuntime()
        return
    workingDirectory := FindTES3MPFolder()
    LogLauncherEvent("GAME | New Adventure launch requested.")
    try
    {
        Run('"' executable '" --connect=' AppConfig.Server, workingDirectory, , &pid)
        LogLauncherEvent("GAME | SUCCESS | New Adventure TES3MP process started | PID: " pid ".")
    }
    catch Error as err
    {
        LogLauncherEvent("GAME | ERROR | Could not start New Adventure: " err.Message ".")
        MsgBox("Could not launch TES3MP. Check the selected executable and try again.", "tes3np")
    }
}
