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
    JackPanel := Gui("-DPIScale -Caption +ToolWindow +Owner" LauncherGui.Hwnd, "TES3NP Jack Raid")
    JackPanel.BackColor := "18130F"
    JackPanel.SetFont("s14 Bold cE9C78D", "Georgia")
    heading := JackPanel.Add("Text", "x16 y8 w520 h27 +0x100 BackgroundTrans", "JACK — RAID BOSS")
    heading.OnEvent("Click", ToggleJackTracker)
    JackPanel.SetFont("s10 Bold cE9C78D", "Segoe UI")
    JackFields["toggle"] := JackPanel.Add("Text", "x844 y11 w98 h25 Right +0x100 BackgroundTrans", "Expand  ▾")
    JackFields["toggle"].OnEvent("Click", ToggleJackTracker)
    JackPanel.SetFont("s10 Norm cD5C2A7", "Segoe UI")
    JackFields["summary"] := JackPanel.Add("Text", "x16 y36 w918 h20 +0x100 BackgroundTrans", "")
    JackFields["summary"].OnEvent("Click", ToggleJackTracker)

    ; Dark inset cards and gold headings give each type of information its own
    ; readable area. The background panels are added before their labels.
    JackFields["portalBg"] := JackPanel.Add("Text", "x12 y66 w452 h98 Background292118")
    JackFields["statusBg"] := JackPanel.Add("Text", "x476 y66 w472 h98 Background292118")
    JackFields["playersBg"] := JackPanel.Add("Text", "x12 y174 w936 h77 Background292118")
    JackPanel.SetFont("s10 Bold cE9C78D", "Segoe UI")
    JackFields["portalHeading"] := JackPanel.Add("Text", "x26 y76 w420 h23 BackgroundTrans", "PORTAL LOCATION")
    JackFields["statusHeading"] := JackPanel.Add("Text", "x490 y76 w440 h23 BackgroundTrans", "RAID STATUS")
    JackFields["playersHeading"] := JackPanel.Add("Text", "x26 y182 w450 h22 BackgroundTrans", "SUSPECTED PARTICIPANTS")
    JackPanel.SetFont("s13 Bold cF0D5A3", "Segoe UI")
    JackFields["location"] := JackPanel.Add("Text", "x26 y106 w420 h27 BackgroundTrans", "")
    JackFields["raid"] := JackPanel.Add("Text", "x490 y106 w440 h27 BackgroundTrans", "")
    JackPanel.SetFont("s10 Norm cD5C2A7", "Segoe UI")
    JackFields["access"] := JackPanel.Add("Text", "x26 y140 w420 h18 BackgroundTrans", "")
    JackFields["countdown"] := JackPanel.Add("Text", "x490 y140 w440 h18 BackgroundTrans", "")
    JackFields["players"] := JackPanel.Add("Text", "x26 y207 w905 h37 BackgroundTrans", "")
    for key in ["portalBg", "statusBg", "playersBg", "portalHeading", "statusHeading", "playersHeading", "location", "raid", "access", "countdown", "players"]
        JackFields[key].Visible := false
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
    flags := NumGet(lParam, A_PtrSize * 2 + 16, "UInt")
    if flags & 0x0002 { ; SWP_NOMOVE: coordinates are not valid
        PositionJackTracker()
        return
    }
    PositionJackTracker(x, y)
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
        ; Always take the actual launcher width, not WINDOWPOS.cx (which
        ; can be undefined for SWP_NOSIZE).
        ; Keep the bar aligned with the launcher without resizing the launcher.
        barWidth := w
        ; Keep the alert compact: its GUI content is laid out in fixed
        ; logical pixels and should not grow vertically with launcher scale.
        barHeight := JackExpanded ? 260 : 59
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
    JackFields["summary"].Text := JackRaidState "   |   " JackPortalLocation "   |   Portal: " JackPortalState "   |   " countdown
    names := ""
    for name, status in JackPlayers
        names .= (names = "" ? "" : "    •    ") name " (" status ")"
    JackFields["location"].Text := JackPortalLocation
    JackFields["raid"].Text := JackRaidState
    JackFields["access"].Text := "Accessibility: " JackPortalState
    JackFields["countdown"].Text := countdown
    JackFields["playersHeading"].Text := "SUSPECTED PARTICIPANTS (" JackPlayers.Count ")"
    JackFields["players"].Text := names = "" ? "No participants detected yet." : names
    for key in ["portalBg", "statusBg", "playersBg", "portalHeading", "statusHeading", "playersHeading", "location", "raid", "access", "countdown", "players"]
        JackFields[key].Visible := JackExpanded
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
