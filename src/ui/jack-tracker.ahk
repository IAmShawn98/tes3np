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
global JackPortalLocation := "Balmora"
global JackPlayers := Map()
global JackRaidEnded := false
; Event panels are registered bottom-to-top. Each can expand independently.
global RaidEventStack := Map()
global RaidEventOrder := []
global JackLayoutWidth := 0

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
    JackPanel.SetFont("s10 Bold cE9C78D", "Georgia")
    heading := JackPanel.Add("Text", "x16 y20 w450 h28 +0x100 BackgroundTrans", "JACK — RAID BOSS (Morroween Event)")
    heading.OnEvent("Click", ToggleJackTracker)
    JackFields["heading"] := heading
    JackPanel.SetFont("s10 Bold cE9C78D", "Segoe UI")
    JackFields["toggle"] := JackPanel.Add("Text", "x844 y20 w98 h27 Right +0x100 BackgroundTrans", "Expand  ▾")
    JackFields["toggle"].OnEvent("Click", ToggleJackTracker)
    JackPanel.SetFont("s10 Norm cD5C2A7", "Segoe UI")
    JackFields["summary"] := JackPanel.Add("Text", "x16 y37 w918 h31 +0x100 BackgroundTrans", "")
    JackFields["summary"].OnEvent("Click", ToggleJackTracker)
    JackFields["summary"].Visible := false
    ; Collapsed strip: a separate warm status pill, portal and next spawn.
    ; Keeping each field separate avoids overflowing one long text control.
    ; Single centered status control: no overlapping translucent layers.
    JackPanel.SetFont("s10 Norm cE9A25D", "Segoe UI")
    JackFields["badge"] := JackPanel.Add("Text", "x400 y17 w155 h31 Center +0x200 +0x100 Background3C2317", "")
    JackFields["badge"].OnEvent("Click", ToggleJackTracker)
    JackPanel.SetFont("s10 Norm cE9C78D", "Segoe UI")
    JackFields["portalGlance"] := JackPanel.Add("Text", "x490 y17 w205 h31 Center +0x200 +0x100 Background30261E", "")
    JackFields["portalGlance"].OnEvent("Click", ToggleJackTracker)

    ; Dark inset cards and gold headings give each type of information its own
    ; readable area. The background panels are added before their labels.
    JackFields["portalBg"] := JackPanel.Add("Text", "x12 y98 w452 h118 Background292118")
    JackFields["statusBg"] := JackPanel.Add("Text", "x476 y98 w472 h118 Background292118")
    JackFields["playersBg"] := JackPanel.Add("Text", "x12 y226 w936 h84 Background292118")
    JackPanel.SetFont("s10 Bold cE9C78D", "Segoe UI")
    JackFields["portalHeading"] := JackPanel.Add("Text", "x26 y109 w420 h25 BackgroundTrans", "PORTAL LOCATION")
    JackFields["statusHeading"] := JackPanel.Add("Text", "x490 y109 w440 h25 BackgroundTrans", "RAID STATUS")
    JackFields["playersHeading"] := JackPanel.Add("Text", "x26 y237 w450 h25 BackgroundTrans", "SUSPECTED PARTICIPANTS")
    JackPanel.SetFont("s13 Bold cF0D5A3", "Segoe UI")
    JackFields["location"] := JackPanel.Add("Text", "x26 y141 w420 h30 BackgroundTrans", "")
    JackFields["raid"] := JackPanel.Add("Text", "x490 y141 w440 h30 BackgroundTrans", "")
    JackPanel.SetFont("s10 Norm cD5C2A7", "Segoe UI")
    JackFields["access"] := JackPanel.Add("Text", "x26 y183 w420 h24 BackgroundTrans", "")
    JackFields["countdown"] := JackPanel.Add("Text", "x490 y183 w440 h24 BackgroundTrans", "")
    JackFields["players"] := JackPanel.Add("Text", "x26 y269 w905 h33 BackgroundTrans", "")
    for key in ["portalBg", "statusBg", "playersBg", "portalHeading", "statusHeading", "playersHeading", "location", "raid", "access", "countdown", "players"]
        JackFields[key].Visible := false
    JackPanel.Show("NoActivate w960 h65")
    RegisterRaidEventPanel("jack", JackPanel, 65, 322)
    PositionRaidEventStack()
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
    PositionRaidEventStack(x, y, w)
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
        PositionRaidEventStack()
        return
    }
    PositionRaidEventStack(x, y)
}

; Any future boss/event registers its own owned GUI here. The stack moves as
; one, grows upward from the unchanged launcher, and supports independent state.
RegisterRaidEventPanel(id, panel, collapsedHeight, expandedHeight)
{
    global RaidEventStack, RaidEventOrder
    if !RaidEventStack.Has(id)
        RaidEventOrder.Push(id)
    RaidEventStack[id] := {gui: panel, collapsed: collapsedHeight,
        expanded: expandedHeight, isExpanded: false}
    PositionRaidEventStack()
}

SetRaidEventExpanded(id, expanded)
{
    global RaidEventStack
    if !RaidEventStack.Has(id)
        return
    RaidEventStack[id].isExpanded := expanded
    PositionRaidEventStack()
}

UnregisterRaidEventPanel(id)
{
    global RaidEventStack, RaidEventOrder
    if !RaidEventStack.Has(id)
        return
    RaidEventStack.Delete(id)
    for i, key in RaidEventOrder {
        if key = id {
            RaidEventOrder.RemoveAt(i)
            break
        }
    }
    PositionRaidEventStack()
}

PositionRaidEventStack(forcedX := "", forcedY := "", forcedW := "")
{
    global LauncherGui, RaidEventStack, RaidEventOrder
    if !IsObject(LauncherGui)
        return
    try {
        WinGetPos(&x, &y, &w, &h, "ahk_id " LauncherGui.Hwnd)
        if forcedX != ""
            x := forcedX
        if forcedY != ""
            y := forcedY
        if forcedW != "" && forcedW > 0
            w := forcedW
        ; Anchor the lowest event directly to the launcher's top edge.
        ; Older registered events remain below newer ones.
        for id in RaidEventOrder {
            entry := RaidEventStack[id]
            height := entry.isExpanded ? entry.expanded : entry.collapsed
            y -= height
            entry.gui.Show("NoActivate x" x " y" y " w" w " h" height)
            if id = "jack"
                LayoutJackTracker(w)
        }
    }
}

; Layout is based on the real launcher width, not the original 960px
; mockup. Keep the toggle flush right and fill both card columns.
LayoutJackTracker(width)
{
    global JackFields, JackLayoutWidth
    if width < 500 || width = JackLayoutWidth || !JackFields.Has("toggle")
        return
    JackLayoutWidth := width
    right := width - 16
    JackFields["toggle"].Move(right - 115, 19, 115, 28)
    ; Four separate columns, with the action anchored at the far right.
    ; Reserve a fixed title column so the complete event name is visible.
    ; Keep these controls close to the rendered title, not the oversized
    ; 40%-wide title control that previously left a large blank gap.
    ; Full title needs its own measured-width region; do not overlap it.
    titleW := 430
    JackFields["heading"].Move(16, 20, titleW, 28)
    badgeW := 145
    badgeX := 16 + titleW + 18
    portalX := badgeX + badgeW + 16
    JackFields["badge"].Move(badgeX, 17, badgeW, 31)
    JackFields["portalGlance"].Move(portalX, 17, Max(90, Min(235, right - 125 - portalX)), 31)
    JackFields["summary"].Move(16, 48, width - 32, 31)
    half := Floor((width - 36) / 2)
    leftX := 12, rightX := leftX + half + 12
    rightW := width - rightX - 12
    JackFields["portalBg"].Move(leftX, 98, half, 118)
    JackFields["statusBg"].Move(rightX, 98, rightW, 118)
    JackFields["playersBg"].Move(12, 226, width - 24, 84)
    for key in ["portalHeading", "location", "access"] {
        ; Preserve each control's vertical coordinate and height.
        JackFields[key].GetPos(, &cy, , &ch)
        JackFields[key].Move(leftX + 14, cy, half - 28, ch)
    }
    for key in ["statusHeading", "raid", "countdown"] {
        JackFields[key].GetPos(, &cy, , &ch)
        JackFields[key].Move(rightX + 14, cy, rightW - 28, ch)
    }
    JackFields["players"].Move(26, 269, width - 52, 33)
}

PositionJackTracker(forcedX := "", forcedY := "", forcedW := "")
{
    PositionRaidEventStack(forcedX, forcedY, forcedW)
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
    remaining := 999999
    if JackLastTimeTick {
        gameNow := Mod(JackGameMinutes + (A_TickCount - JackLastTimeTick) / 2000, 1440)
        remaining := Mod(1260 - gameNow + 1440, 1440) * 2
        countdown := "Next 9 PM: ~" Ceil(remaining / 60) " min"
    }
    ; Expanded summary is a fixed event overview; portal details remain in the cards.
    expandedState := JackRaidState = "Active" ? "Active" : (JackLastTimeTick && remaining <= 300 && JackRaidState != "Likely defeated" ? "Starting Soon" : "Awaiting Evidence")
    JackFields["summary"].Text := expandedState "   |   Location: Balmora Eerie Portal"
    JackFields["summary"].Visible := JackExpanded
    ; A compact three-state indicator. Combat evidence overrides the clock;
    ; the clock alone can only predict an approaching spawn, not a live fight.
    displayState := "Inactive"
    if JackRaidState = "Active"
        displayState := "Active"
    else if JackLastTimeTick && remaining <= 5 * 60 && JackRaidState != "Likely defeated"
        displayState := "Starting Soon"
    JackFields["badge"].Text := displayState
    ; Live color coding: green for active, amber for imminent, muted brown otherwise.
    if displayState = "Active" {
        JackFields["badge"].SetFont("cA8E6B1")
        JackFields["badge"].Opt("Background214B32")
    } else if displayState = "Starting Soon" {
        JackFields["badge"].SetFont("cF5CF85")
        JackFields["badge"].Opt("Background54371B")
    } else {
        JackFields["badge"].SetFont("cE9A25D")
        JackFields["badge"].Opt("Background3C2317")
    }
    JackFields["portalGlance"].Text := JackPortalLocation = "Balmora" ? "Eerie Portal: Balmora" : "Balmora Portal: " JackPortalLocation
    for key in ["badge", "portalGlance"]
        JackFields[key].Visible := !JackExpanded
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
    SetRaidEventExpanded("jack", JackExpanded)
}

StopJackTracker()
{
    global JackPanel
    SetTimer(JackTrackerTick, 0)
    OnMessage(0x0216, JackFollowLauncherMoving, 0)
    OnMessage(0x0047, JackFollowLauncherWindowPos, 0)
    UnregisterRaidEventPanel("jack")
    if IsObject(JackPanel)
        JackPanel.Destroy()
    JackPanel := 0
}
