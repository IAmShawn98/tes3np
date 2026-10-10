; October-only Jack raid alert prototype. Uses the existing archived Game Chat log.
global JackPanel := 0
global JackFields := Map()
global JackExpanded := false
global JackCollapseAt := 0
global JackLogSize := -1
global JackLastTimeTick := 0
global JackGameMinutes := 0
global JackRaidState := "Awaiting evidence"
global JackPortalState := "Closed"
global JackPortalLocation := "Balmora"
global JackPlayers := Map()
global JackPlayerReported := Map()
global JackPortalReported := 0
global JackRaidReported := 0
global JackClockReported := 0
global JackRaidEnded := false
global JackCombatTick := 0
global JackVictoryHints := Map()
global JackClockDay := -1
global JackPortalEvidence := false
global JackLastPortalWindow := false
global JackLastClockMinute := -1
; Event panels are registered bottom-to-top. Each can expand independently.
global RaidEventStack := Map()
global RaidEventOrder := []
global JackLayoutWidth := 0
global JackTrackerVisible := false

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
    JackFields["portalBg"] := JackPanel.Add("Text", "x476 y68 w472 h118 Background292118")
    JackFields["statusBg"] := JackPanel.Add("Text", "x12 y68 w452 h118 Background292118")
    JackFields["playersBg"] := JackPanel.Add("Text", "x12 y196 w936 h84 Background292118")
    JackPanel.SetFont("s10 Bold cE9C78D", "Segoe UI")
    JackFields["portalHeading"] := JackPanel.Add("Text", "x490 y79 w440 h25 BackgroundTrans", "PORTAL LOCATION")
    JackFields["statusHeading"] := JackPanel.Add("Text", "x26 y79 w420 h25 BackgroundTrans", "RAID STATUS")
    JackFields["playersHeading"] := JackPanel.Add("Text", "x26 y207 w450 h25 BackgroundTrans", "SUSPECTED PARTICIPANTS")
    JackPanel.SetFont("s13 Bold cF0D5A3", "Segoe UI")
    JackFields["location"] := JackPanel.Add("Text", "x490 y111 w440 h30 BackgroundTrans", "")
    JackFields["raid"] := JackPanel.Add("Text", "x26 y111 w420 h30 BackgroundTrans", "")
    JackPanel.SetFont("s10 Norm cD5C2A7", "Segoe UI")
    JackFields["access"] := JackPanel.Add("Text", "x490 y164 w440 h21 BackgroundTrans", "")
    JackFields["countdown"] := JackPanel.Add("Text", "x26 y164 w420 h21 BackgroundTrans", "")
    JackFields["players"] := JackPanel.Add("Text", "x26 y239 w905 h33 BackgroundTrans", "")
    JackFields["raidReported"] := JackPanel.Add("Text", "x26 y144 w420 h18 BackgroundTrans", "")
    JackFields["portalReported"] := JackPanel.Add("Text", "x490 y144 w440 h18 BackgroundTrans", "")
    for key in ["portalBg", "statusBg", "playersBg", "portalHeading", "statusHeading", "playersHeading", "location", "raid", "access", "countdown", "players", "raidReported", "portalReported"]
        JackFields[key].Visible := false
    JackPanel.Show("NoActivate w960 h65")
    RegisterRaidEventPanel("jack", JackPanel, 65, 292)
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
    global LauncherGui, RaidEventStack, RaidEventOrder, JackTrackerVisible
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
            if id = "jack" && !JackTrackerVisible {
                entry.gui.Hide()
                continue
            }
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
    JackFields["portalBg"].Move(rightX, 68, rightW, 118)
    JackFields["statusBg"].Move(leftX, 68, half, 118)
    JackFields["playersBg"].Move(12, 196, width - 24, 84)
    for key in ["portalHeading", "location", "access", "portalReported"] {
        ; Preserve each control's vertical coordinate and height.
        JackFields[key].GetPos(, &cy, , &ch)
        JackFields[key].Move(rightX + 14, cy, rightW - 28, ch)
    }
    for key in ["statusHeading", "raid", "countdown", "raidReported"] {
        JackFields[key].GetPos(, &cy, , &ch)
        JackFields[key].Move(leftX + 14, cy, half - 28, ch)
    }
    JackFields["players"].Move(26, 239, width - 52, 33)
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
                for line in StrSplit(chunk, "`n", "`r") {
                    ; Chat Host can append previously fetched Discord history in a batch.
                    ; Only process messages whose chat timestamp is actually recent.
                    if JackChatLineIsFresh(line)
                        ProcessJackChatLine(line)
                }
            }
        }
    }
    if JackExpanded && JackCollapseAt && A_TickCount >= JackCollapseAt {
        JackExpanded := false
        JackCollapseAt := 0
    }
    RefreshJackTracker()
}

JackChatLineIsFresh(line)
{
    ; Ignore date headings, old history backfills and incomplete lines.
    ; Discord Game Chat timestamps use the same local clock as A_Now.
    if !RegExMatch(line, "^\[(\d{2}):(\d{2}):(\d{2}) (AM|PM)\] ", &stamp)
        return false
    hour := Mod(Integer(stamp[1]), 12) + (stamp[4] = "PM" ? 12 : 0)
    msgSeconds := hour * 3600 + Integer(stamp[2]) * 60 + Integer(stamp[3])
    nowSeconds := Integer(FormatTime(, "H")) * 3600 + Integer(FormatTime(, "m")) * 60 + Integer(FormatTime(, "s"))
    age := Mod(nowSeconds - msgSeconds + 86400, 86400)
    ; Allow minor delivery delays and midnight rollover, but never hours-old replay.
    return age <= 180
}

ProcessJackChatLine(line)
{
    global JackLastTimeTick, JackGameMinutes, JackRaidState, JackPortalState
    global JackPortalLocation, JackPlayers, JackRaidEnded, JackExpanded, JackCollapseAt
    global JackPlayerReported, JackPortalReported, JackRaidReported, JackClockReported
    global JackCombatTick, JackVictoryHints, JackClockDay, JackPortalEvidence, JackLastClockMinute
    if RegExMatch(line, "i)The current in-game time is\s+(\d{1,2}):(\d{2})\s*(AM|PM)", &m) {
        hour := Mod(Integer(m[1]), 12) + (StrUpper(m[3]) = "PM" ? 12 : 0)
        newMinute := hour * 60 + Integer(m[2])
        ; A fresh !time may jump past 6 AM without a timer tick at the boundary.
        if JackLastTimeTick && JackLastClockMinute >= 0 && JackLastClockMinute < 360 && newMinute >= 360 && newMinute < 1260
            ResetJackEncounter("Clock resynchronized beyond 6 AM")
        JackGameMinutes := newMinute
        JackLastTimeTick := A_TickCount
        JackClockReported := A_TickCount
        return
    }
    if !RegExMatch(line, "^\[\d\d:\d\d:\d\d [AP]M\] ([^:]+):\s*(.*)$", &msg)
        return
    sender := Trim(msg[1]), body := Trim(msg[2])
    if RegExMatch(body, "i)\b(.+?)\s*\(\d+\) was (?:honorably )?killed by Jack\.", &death) {
        ; System/Yagrum relay messages are authoritative Jack boss evidence.
        ; An honorable kill is not a boss death message. Do not
        ; silently discard them when !time has not yet been observed or when
        ; the estimated clock drifted. Ignore ordinary player-authored claims.
        if sender != "System" && sender != "Yagrum"
            return
        if InStr(body, "honorably killed by Jack")
            return
        if !JackLastTimeTick
            JackTrackerLog("Jack kill detected before clock sync: " body)
        else {
            gameNow := Mod(JackGameMinutes + (A_TickCount - JackLastTimeTick) / 2000, 1440)
            if !(gameNow >= 1260 || gameNow < 360)
                JackTrackerLog("Jack kill detected outside estimated raid window: " body)
        }
        JackPlayers[Trim(death[1])] := "Fighting"
        JackPlayerReported[Trim(death[1])] := A_TickCount
        JackRaidReported := A_TickCount
        JackPortalReported := A_TickCount
        JackRaidState := "Active"
        JackTrackerLog("Combat evidence: " body)
        JackCombatTick := A_TickCount
        JackVictoryHints.Clear()
        JackPortalState := "Open"
        JackPortalEvidence := true
        JackPortalReported := A_TickCount
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
        return
    }
    if RegExMatch(body, "i)\b(jack is dead|jack(?:'s| is)? down|we killed jack|jack has been defeated)\b") && JackCombatTick && A_TickCount - JackCombatTick <= 12 * 60 * 1000 {
        JackRaidState := "Likely defeated"
        JackRaidReported := A_TickCount
        JackPortalState := "Likely Closed"
        JackPortalEvidence := true
        JackPortalReported := A_TickCount
        JackTrackerLog("Likely portal closure: explicit Jack defeat report")
        InvalidateJackClock("Jack defeat reported")
        ; Do not reset on a single unverified player claim.
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
    }
    ; A victory phrase alone is ambiguous. Require recent Jack combat, and
    ; either an explicit Jack victory or two distinct contextual hints.
    ; Examples from real chat: "there we go", "we wrecked his shiz", "OWNED".
    if JackCombatTick && A_TickCount - JackCombatTick <= 12 * 60 * 1000 {
        explicitWin := RegExMatch(body, "i)\b(?:jack (?:kill|dead|defeated)|(?:killed|beat|defeated) jack|jack(?:'s| is)? down|mostly solo jack kill)\b")
        contextualWin := RegExMatch(body, "i)\b(?:we won|we (?:wrecked|got|beat) (?:him|his)|there we go|owned|gg(?:s)?|got him)\b")
        if explicitWin || contextualWin {
            JackVictoryHints[sender] := A_TickCount
            if explicitWin || JackVictoryHints.Count >= 2 {
                JackRaidState := "Likely defeated"
                JackTrackerLog("Likely defeated: " sender " | " body)
                JackRaidReported := A_TickCount
                JackPortalState := "Likely Closed"
                JackPortalEvidence := true
                JackPortalReported := A_TickCount
                InvalidateJackClock("Jack victory inferred")
                JackExpanded := true
                JackCollapseAt := A_TickCount + 14000
            }
        }
    }
    ; Phase announcements are strong evidence of a live Jack encounter.
    if RegExMatch(body, "i)\bjack\s+phase\s*[1-9]\b") {
        JackRaidState := "Active"
        JackCombatTick := A_TickCount
        JackVictoryHints.Clear()
        JackPortalState := "Open"
        JackPortalEvidence := true
        JackPlayers[sender] := "Fighting"
        JackPlayerReported[sender] := A_TickCount
        JackRaidReported := A_TickCount
        JackPortalReported := A_TickCount
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
    }
    if RegExMatch(body, "i)\b(portal (?:is )?(?:gone|disappeared)|balmora (?:cell )?reset|cell reset)\b") {
        JackPortalState := "Disappeared"
        JackPortalEvidence := true
        JackPortalReported := A_TickCount
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
    } else if RegExMatch(body, "i)\b(portal (?:is )?(?:open|still up)|portal's still up)\b") {
        JackPortalState := "Open"
        JackPortalEvidence := true
        JackPortalReported := A_TickCount
        JackExpanded := true
        JackCollapseAt := A_TickCount + 14000
    }
    if RegExMatch(body, "i)\b(?:i(?:'m| am) (?:coming|going) to jack|omw to jack)\b")
    {
        JackPlayers[sender] := "Likely"
        JackPlayerReported[sender] := A_TickCount
    }
    if RegExMatch(body, "i)\b(?:not (?:going|coming) to jack|can't make (?:it|jack)|leaving jack)\b") && JackPlayers.Has(sender)
    {
        JackPlayers.Delete(sender)
        JackPlayerReported.Delete(sender)
    }
}

RefreshJackTracker()
{
    global JackPanel, JackFields, JackLastTimeTick, JackGameMinutes
    global JackRaidState, JackPortalState, JackPortalLocation, JackPlayers, JackExpanded, JackTrackerVisible, JackLastClockMinute
    global JackPlayerReported, JackPortalReported, JackRaidReported, JackClockReported
    global JackCombatTick, JackVictoryHints, JackPortalEvidence, JackLastPortalWindow
    if !IsObject(JackPanel)
        return
    countdown := "Waiting for server time"
    remaining := 999999
    if JackLastTimeTick {
        gameNow := Mod(JackGameMinutes + (A_TickCount - JackLastTimeTick) / 2000, 1440)
        ; Reset stale encounter evidence once the in-game clock reaches 6 AM.
        ; Track the clock crossing, not just the hour, to avoid repeat resets.
        if JackLastClockMinute >= 0 && JackLastClockMinute < 360 && gameNow >= 360 && gameNow < 1260 {
            ResetJackEncounter("Passed 6 AM")
        }
        if !JackLastTimeTick
            gameNow := -1
        else
            JackLastClockMinute := gameNow
        if JackLastTimeTick {
            remaining := Mod(1260 - gameNow + 1440, 1440) * 2
            countdown := "Next 9 PM: ~" Ceil(remaining / 60) " min"
        }
    }
    ; Status and portal location are already displayed in the detail cards.
    JackFields["summary"].Visible := false
    ; !time synchronizes an internal clock. The 9 PM–6 AM window is
    ; scheduled activity, not proof Jack is alive or the portal is open.
    inRaidWindow := JackLastTimeTick && (gameNow >= 1260 || gameNow < 360)
    ; The portal opens at 9 PM and closes at 6 AM unless Jack dies first.
    ; A cell-reset disappearance requires explicit player evidence.
    if JackLastTimeTick {
        if inRaidWindow && !JackLastPortalWindow {
            JackPortalState := "Open"
            JackPortalEvidence := true
            JackPortalReported := A_TickCount
            JackTrackerLog("Scheduled 9 PM portal opening")
        } else if !inRaidWindow && JackLastPortalWindow {
            JackPortalState := "Closed"
            JackPortalEvidence := true
            JackPortalReported := A_TickCount
            JackTrackerLog("Scheduled 6 AM portal closure")
        }
        JackLastPortalWindow := inRaidWindow
    }
    displayState := "Inactive"
    if JackRaidState = "Active" && JackCombatTick && A_TickCount - JackCombatTick <= 12 * 60 * 1000
        displayState := "Active"
    else if inRaidWindow && JackRaidState != "Likely defeated"
        displayState := "Scheduled"
    else if JackLastTimeTick && remaining <= 5 * 60 && JackRaidState != "Likely defeated"
        displayState := "Starting Soon"
    JackTrackerVisible := displayState = "Active" || displayState = "Starting Soon" || displayState = "Scheduled" || (JackRaidState = "Likely defeated" && JackRaidReported && A_TickCount - JackRaidReported < 12 * 60 * 1000)
    JackFields["badge"].Text := displayState
    ; Live color coding: green for active, amber for imminent, muted brown otherwise.
    if displayState = "Active" {
        JackFields["badge"].SetFont("cA8E6B1")
        JackFields["badge"].Opt("Background214B32")
    } else if displayState = "Starting Soon" || displayState = "Scheduled" {
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
        names .= (names = "" ? "" : "    •    ") name " (" status ", " JackReportedAgo(JackPlayerReported.Has(name) ? JackPlayerReported[name] : 0) ")"
    JackFields["location"].Text := JackPortalLocation
    JackFields["raid"].Text := inRaidWindow && JackRaidState = "Awaiting evidence" ? "Scheduled window (unconfirmed)" : JackRaidState
    JackFields["access"].Text := "Portal Status: " (JackPortalEvidence ? JackPortalState : "Unconfirmed")
    JackFields["portalReported"].Text := "Last reported: " JackReportedAgo(JackPortalReported)
    JackFields["raidReported"].Text := "Last reported: " JackReportedAgo(JackRaidReported)
    JackFields["countdown"].Text := countdown
    JackFields["playersHeading"].Text := "SUSPECTED PARTICIPANTS (" JackPlayers.Count ")"
    JackFields["players"].Text := names = "" ? "No participants detected yet." : names
    for key in ["portalBg", "statusBg", "playersBg", "portalHeading", "statusHeading", "playersHeading", "location", "raid", "access", "countdown", "players", "raidReported", "portalReported"]
        JackFields[key].Visible := JackExpanded
    JackFields["toggle"].Text := JackExpanded ? "Collapse  ▴" : "Expand  ▾"
    SetRaidEventExpanded("jack", JackExpanded)
}

ResetJackEncounter(reason)
{
    global JackRaidState, JackPortalState, JackPlayers, JackPlayerReported
    global JackRaidReported, JackPortalReported, JackCombatTick, JackVictoryHints
    global JackExpanded, JackPortalEvidence
    InvalidateJackClock("Encounter reset")
    JackRaidState := "Awaiting evidence"
    JackPortalState := "Closed"
    JackPortalEvidence := true
    JackPlayers.Clear()
    JackPlayerReported.Clear()
    JackRaidReported := 0
    JackPortalReported := A_TickCount
    JackCombatTick := 0
    JackVictoryHints.Clear()
    JackExpanded := false
    JackTrackerLog("Reset: " reason)
}

InvalidateJackClock(reason)
{
    global JackLastTimeTick, JackGameMinutes, JackLastClockMinute, JackLastPortalWindow, JackClockReported
    JackLastTimeTick := 0
    JackGameMinutes := 0
    JackLastClockMinute := -1
    JackLastPortalWindow := false
    JackClockReported := 0
    JackTrackerLog("Clock invalidated: " reason)
}

JackTrackerLog(message)
{
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " | " message "`n", A_AppData "\\TES3NP\\Logs\\jack-tracker.log", "UTF-8")
}

JackReportedAgo(tick)
{
    if !tick
        return "No report yet"
    seconds := Max(0, Floor((A_TickCount - tick) / 1000))
    if seconds < 60
        return seconds "s ago"
    if seconds < 3600
        return Floor(seconds / 60) "m ago"
    return Floor(seconds / 3600) "h " Mod(Floor(seconds / 60), 60) "m ago"
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
