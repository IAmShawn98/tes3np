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
        MsgBox("Select an existing tes3mp.exe on the characters page.", "tes3np")
        return false
    }
    if profile.Password = ""
    {
        MsgBox("Edit " profile.Name " and re-enter their password.", "tes3np")
        return false
    }
    return true
}

LaunchProfileIndex(index)
{
    global Client, Profiles
    if Client.Enabled
    {
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
    global Client, Profiles, DataFile, CharacterPage
    if Client.Enabled
    {
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
    StartProfileSession(profile, executable, queue)
}

StartProfileSession(profile, executable, queue := 0)
{
    global Client
    Client := {PID: 0, HWND: 0, Phase: "launch", Deadline: 0, Enabled: true,
        Profile: {Name: profile.Name, Password: profile.Password}, Executable: executable,
        UsernameDelay: profile.UsernameDelay, PasswordDelay: profile.PasswordDelay,
        LoadDelay: profile.LoadDelay, AutoReconnect: profile.AutoReconnect, Queue: queue}
    SetTimer(UpdateGameStatusTooltip, AppConfig.TooltipMs)
    SetTimer(ClientTick, AppConfig.WatchdogMs)
    ClientTick()
}

StopClient(*)
{
    global Client
    Client.Enabled := false
    Client.Phase := "stopped"
    SetTimer(ClientTick, 0)
    SetTimer(UpdateGameStatusTooltip, 0)
    ToolTip(, , , 1)
    SetClientStatus("Recovery stopped. You can close the game normally.")
}

SetClientStatus(text)
{
    global SessionStatus, Client
    Client.Status := text
    if IsSet(SessionStatus)
        SessionStatus.Text := text
    UpdateGameStatusTooltip()
}

; UI-only refresh: follows the game and hides immediately when another window is active.
; Recovery decisions remain exclusively in ClientTick.
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
        ; The game's login prompt is centered. Keep feedback just above it.
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
                    ; SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE preserves game focus.
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
    ; A console sharing tes3mp.exe's PID does not prove the game is running.
    for hwnd in WinGetList("ahk_pid " pid)
    {
        className := WinGetClass("ahk_id " hwnd)
        if className = "ConsoleWindowClass" || InStr(className, "Terminal")
            continue
        if !(WinGetStyle("ahk_id " hwnd) & 0x10000000)
            continue
        ; TES3MP/OpenMW uses SDL for its rendered game window.
        if !InStr(className, "SDL")
            continue
        return hwnd
    }
    return 0
}

RetryClient(reason)
{
    global Client
    if Client.PID && ProcessExist(Client.PID)
    {
        try ProcessClose(Client.PID)
    }
    if !Client.AutoReconnect
    {
        if IsObject(Client.Queue)
        {
            ; A batch skips this failed character instead of reconnecting it.
            Client.Phase := "closing"
            Client.Deadline := A_TickCount
            SetClientStatus(reason " — auto reconnect disabled; continuing the list.")
        }
        else
        {
            StopClient()
            SetClientStatus(reason " — auto reconnect disabled.")
        }
        return
    }
    Client.PID := 0
    Client.HWND := 0
    Client.Phase := "retry"
    Client.Deadline := A_TickCount + AppConfig.RetryMs
    SetClientStatus(reason " — retrying in 5 seconds.")
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
            SplitPath(Client.Executable, , &workingDirectory)
            Run('"' Client.Executable '" --connect=' AppConfig.Server, workingDirectory, , &pid)
            Client.PID := pid
            Client.Phase := "window"
            Client.Deadline := A_TickCount + AppConfig.GameWindowWaitMs
        }
        if Client.Phase = "retry"
        {
            remaining := Max(0, Ceil((Client.Deadline - A_TickCount) / 1000))
            SetClientStatus("Restarting client in " remaining " seconds.")
            if remaining = 0
                Client.Phase := "launch"
            return
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
                StartProfileSession(profile, Client.Executable, queue)
            }
            else
            {
                StopClient()
                SetClientStatus("All characters completed. Game clients closed.")
            }
            return
        }
        if !ProcessExist(Client.PID)
        {
            RetryClient("Game process closed")
            return
        }
        hwnd := FindGameWindow(Client.PID)
        if Client.Phase = "window"
        {
            if hwnd
            {
                Client.HWND := hwnd
                if !IsObject(Client.Profile)
                {
                    Client.Phase := "playing"
                    SetClientStatus("Game running. Create your character in-game.")
                }
                else
                {
                    Client.Phase := "username"
                    Client.Deadline := A_TickCount + Client.UsernameDelay * 1000
                    SetClientStatus("Waiting for username screen — " Client.UsernameDelay " seconds.")
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
            WinClose("ahk_id " hwnd)
            return
        }
        if Client.Phase = "loading" && IsObject(Client.Queue)
        {
            Client.Phase := "claim"
            Client.Deadline := A_TickCount + AppConfig.ClaimWaitMs
            SetClientStatus("Waiting 10 seconds for " Client.Profile.Name " before closing.")
            return
        }
        if Client.Phase = "loading"
        {
            Client.Phase := "playing"
            SetClientStatus(Client.AutoReconnect ? "Login inputs completed. Auto reconnect is on." : "Login inputs completed. Auto reconnect is off.")
            return
        }
        ; Activate only for credential entry; watchdog checks do not steal focus.
        WinActivate("ahk_id " hwnd)
        if !WinWaitActive("ahk_id " hwnd, , 2)
            throw Error("Could not focus game window")
        if Client.Phase = "username"
        {
            SetClientStatus("Entering username...")
            SendText(Client.Profile.Name)
            Send("{Enter}")
            Client.Phase := "password"
            Client.Deadline := A_TickCount + Client.PasswordDelay * 1000
            SetClientStatus("Waiting for password screen — " Client.PasswordDelay " seconds.")
        }
        else if Client.Phase = "password"
        {
            SetClientStatus("Entering password...")
            SendText(Client.Profile.Password)
            Send("{Enter}")
            Client.Phase := "loading"
            Client.Deadline := A_TickCount + Client.LoadDelay * 1000
            SetClientStatus("Loading character — " Client.LoadDelay " seconds.")
        }
        else
        {
            Client.Phase := "playing"
            SetClientStatus(Client.AutoReconnect ? "Login inputs completed. Auto reconnect is on." : "Login inputs completed. Auto reconnect is off.")
        }
    }
    catch Error as err
        RetryClient("Client launch or login failed")
}

StartNewAdventure(*)
{
    if !CanUseNPLauncher()
        return
    global Client, DataFile
    if Client.Enabled
    {
        MsgBox("A game session is already being monitored. Use the tray menu to stop recovery before starting another.", "tes3np")
        return
    }
    executable := IniRead(DataFile, "Launch", "Executable", "")
    SplitPath(executable, &filename)
    if !FileExist(executable) || StrLower(filename) != "tes3mp.exe"
        executable := FileSelect(1, , "Select tes3mp.exe to start your adventure", "Applications (*.exe)")
    if executable = ""
        return
    SplitPath(executable, &filename)
    if StrLower(filename) != "tes3mp.exe" || !FileExist(executable)
    {
        MsgBox("Select an existing tes3mp.exe.", "tes3np")
        return
    }
    DirCreate(AppDataDirectory)
    IniWrite(executable, DataFile, "Launch", "Executable")
    SplitPath(executable, , &workingDirectory)
    try Run('"' executable '" --connect=' AppConfig.Server, workingDirectory)
    catch Error as err
        MsgBox("Could not launch TES3MP. Check the selected executable and try again.", "tes3np")
}

