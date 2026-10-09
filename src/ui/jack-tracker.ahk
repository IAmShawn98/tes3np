; October-only Jack raid alert prototype. Uses the existing archived Game Chat log.
global JackPanel := 0
global JackFields := Map()
global JackExpanded := false
global JackCollapseAt := 0
global JackLogSize := -1
global JackLastTimeTick := 0
global JackGameMinutes := 0
global JackRaidState := "Awaiting evidence"
global JackPortalState := "Unknown"
global JackPortalLocation := "Balmora Portal"
global JackPlayers := Map()
global JackRaidEnded := false

StartJackTracker()
{
    global JackPanel, JackLogSize, JackFields, LauncherGui
    if Integer(FormatTime(, "M")) != 10
        return
    log := A_AppData "\TES3NP\Logs\game-chat.log"
    JackLogSize := FileExist(log) ? FileGetSize(log) : 0
    ; Owner relationship keeps the panel with the launcher in Z-order,
    ; including minimize/restore, without changing launcher dimensions.
    JackPanel := Gui("-Caption +ToolWindow +Owner" LauncherGui.Hwnd, "TES3NP Jack Raid")
    JackPanel.BackColor := "18130F"
    JackPanel.SetFont("s11 Bold cE9C78D", "Georgia")
    heading := JackPanel.Add("Text", "x14 y8 w685 h26 +0x100", "JACK — RAID BOSS")
    heading.OnEvent("Click", ToggleJackTracker)
    JackPanel.SetFont("s9 Norm cB7A38C", "Segoe UI")
    JackFields["summary"] := JackPanel.Add("Text", "x14 y35 w790 h19 +0x100", "Balmora Portal  |  Portal: Unknown  |  Waiting for server time")
    JackFields["summary"].OnEvent("Click", ToggleJackTracker)
    JackFields["detail"] := JackPanel.Add("Text", "x14 y61 w790 h105", "")
    JackPanel.SetFont("s9 Bold cE9C78D", "Segoe UI")
    toggle := JackPanel.Add("Text", "x736 y9 w74 h24 Right +0x100", "Expand  ▾")
    toggle.OnEvent("Click", ToggleJackTracker)
    JackFields["toggle"] := toggle
    JackPanel.Show("NoActivate w960 h59")
    PositionJackTracker()
    ; WM_MOVING supplies the live proposed launcher rectangle while dragging.
    ; WM_WINDOWPOSCHANGED handles moves from scaling and other code paths.
    OnMessage(0x0216, JackFollowLauncherMoving)
    OnMessage(0x0047, JackFollowLauncherWindowPos)
    SetTimer(JackTrackerTick, 1000)
    RefreshJackTracker()
}

ToggleJackTracker(*)
{
    global JackExpanded, JackCollapseAt
    JackExpanded := !JackExpanded
    JackCollapseAt := JackExpanded ? A_TickCount + 14000 : 0
    RefreshJackTracker()
}

JackFollowLauncherMoving(wParam, lParam, msg, hwnd)
{
    global LauncherGui
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd || !lParam
        return
    ; RECT: left, top, right, bottom (four signed 32-bit integers).
    x := NumGet(lParam, 0, "Int"), y := NumGet(lParam, 4, "Int")
    w := NumGet(lParam, 8, "Int") - x
    PositionJackTracker(x, y, w)
}

JackFollowLauncherWindowPos(wParam, lParam, msg, hwnd)
{
    global LauncherGui
    if !IsObject(LauncherGui) || hwnd != LauncherGui.Hwnd || !lParam
        return
    ; WINDOWPOS: hwnd, hwndInsertAfter, x, y, cx, cy, flags.
    x := NumGet(lParam, A_PtrSize * 2, "Int")
    y := NumGet(lParam, A_PtrSize * 2 + 4, "Int")
    w := NumGet(lParam, A_PtrSize * 2 + 8, "Int")
    flags := NumGet(lParam, A_PtrSize * 2 + 16, "UInt")
    if flags & 0x0002 { ; SWP_NOMOVE: coordinates are not valid
        PositionJackTracker()
        return
    }
    PositionJackTracker(x, y, w)
}

PositionJackTracker(forcedX := "", forcedY := "", forcedW := "")
{
    global JackPanel, LauncherGui, JackExpanded
    if !IsObject(JackPanel) || !IsObject(LauncherGui)
        return
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " LauncherGui.Hwnd)
        if forcedX != ""
            x := forcedX
        if forcedY != ""
            y := forcedY
        if forcedW != "" && forcedW > 0
            w := forcedW
        ; Keep the bar aligned with the launcher without resizing the launcher.
        barWidth := w
        ; Keep the alert compact: its GUI content is laid out in fixed
        ; logical pixels and should not grow vertically with launcher scale.
        barHeight := JackExpanded ? 172 : 59
        JackPanel.Show("NoActivate x" x " y" Max(0, y - barHeight) " w" barWidth " h" barHeight)
    }
}

JackTrackerTick()
{
    global JackPanel, JackExpanded, JackCollapseAt, JackLogSize
    if Integer(FormatTime(, "M")) != 10 {
        if IsObject(JackPanel)
            JackPanel.Hide()
        SetTimer(JackTrackerTick, 0)
        return
    }
    log := A_AppData "\TES3NP\Logs\game-chat.log"
    if FileExist(log) {
        size := FileGetSize(log)
        if JackLogSize < 0 || size < JackLogSize
            JackLogSize := size
        if size > JackLogSize {
            ; Read only appended lines, never replay historical logs at startup.
            try {
                f := FileOpen(log, "r", "UTF-8")
                f.Pos := JackLogSize
                chunk := f.Read()
                f.Close()
                JackLogSize := size
                for line in StrSplit(chunk, "`n", "`r")
                    ProcessJackChatLine(line)
            }
        }
    }
    if JackExpanded && JackCollapseAt && A_TickCount >= JackCollapseAt {
        JackExpanded := false
        JackCollapseAt := 0
    }
    RefreshJackTracker()
}

ProcessJackChatLine(line)
{
    global JackLastTimeTick, JackGameMinutes, JackRaidState, JackPortalState
    global JackPortalLocation, JackPlayers, JackRaidEnded, JackExpanded, JackCollapseAt
    if RegExMatch(line, "i)The current in-game time is\s+(\d{1,2}):(\d{2})\s*(AM|PM)", &m) {
        hour := Mod(Integer(m[1]), 12) + (StrUpper(m[3]) = "PM" ? 12 : 0)
        JackGameMinutes := hour * 60 + Integer(m[2])
        JackLastTimeTick := A_TickCount
        return
    }
    if !RegExMatch(line, "^\[\d\d:\d\d:\d\d [AP]M\] ([^:]+):\s*(.*)$", &msg)
        return
    sender := Trim(msg[1]), body := Trim(msg[2])
    if RegExMatch(body, "i)\b(.+?)\s*\(\d+\) was (?:honorably )?killed by Jack\.", &death) {
        JackPlayers[Trim(death[1])] := "Fighting"
        JackRaidState := "Active"
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
        return
    }
    if RegExMatch(body, "i)\b(jack is dead|jack(?:'s| is)? down|we killed jack|jack has been defeated)\b") {
        JackRaidState := "Likely defeated"
        ; Do not reset on a single unverified player claim.
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
    }
    if RegExMatch(body, "i)\b(portal (?:is )?(?:gone|closed|disappeared)|balmora reset)\b") {
        JackPortalState := "Likely closed"
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
    } else if RegExMatch(body, "i)\b(portal (?:is )?(?:open|still up)|portal's still up)\b") {
        JackPortalState := "Reported open"
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
    }
    if RegExMatch(body, "i)\b(?:i(?:'m| am) (?:coming|going) to jack|omw to jack)\b")
        JackPlayers[sender] := "Likely"
    if RegExMatch(body, "i)\b(?:not (?:going|coming) to jack|can't make (?:it|jack)|leaving jack)\b") && JackPlayers.Has(sender)
        JackPlayers.Delete(sender)
}

RefreshJackTracker()
{
    global JackPanel, JackFields, JackLastTimeTick, JackGameMinutes
    global JackRaidState, JackPortalState, JackPortalLocation, JackPlayers, JackExpanded
    if !IsObject(JackPanel)
        return
    countdown := "Waiting for server time"
    if JackLastTimeTick {
        gameNow := Mod(JackGameMinutes + (A_TickCount - JackLastTimeTick) / 2000, 1440)
        remaining := Mod(1260 - gameNow + 1440, 1440) * 2
        countdown := "Next 9 PM: ~" Ceil(remaining / 60) " min"
    }
    JackFields["summary"].Text := JackRaidState "  |  " JackPortalLocation "  |  Portal: " JackPortalState "  |  " countdown
    names := ""
    for name, status in JackPlayers
        names .= (names = "" ? "" : ", ") name " (" status ")"
    JackFields["detail"].Text := "Portal accessibility: " JackPortalState
        . "`nEstimated participants (" JackPlayers.Count "): " (names = "" ? "None detected" : names)
        . "`nRaid status: " JackRaidState
        . "`nBased on recent Game Chat clues — estimates only."
    JackFields["detail"].Visible := JackExpanded
    JackFields["toggle"].Text := JackExpanded ? "Collapse  ▴" : "Expand  ▾"
    PositionJackTracker()
}

StopJackTracker()
{
    global JackPanel
    SetTimer(JackTrackerTick, 0)
    OnMessage(0x0216, JackFollowLauncherMoving, 0)
    OnMessage(0x0047, JackFollowLauncherWindowPos, 0)
    if IsObject(JackPanel)
        JackPanel.Destroy()
    JackPanel := 0
}
