-- Tooltip.lua: Handles quest progress tooltips and party progress display for QuestProgressShare.
-- Manages tooltip integration, party sync, and robust display of quest progress for all group members.

--------------------------------------------------
-- GLOBALS & CONSTANTS
--------------------------------------------------
local QPS = QuestProgressShare
QPS_PartyProgress = QPS_PartyProgress or {}
-- Class color table for party member name coloring in tooltips
QPS_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    MAGE = { r = 0.41, g = 0.8,  b = 0.94 },
    ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
    DRUID = { r = 1.00, g = 0.49, b = 0.04 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    SHAMAN = { r = 0.00, g = 0.44, b = 0.87 },
    PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
}
QPS.Tooltip = QPS.Tooltip or {}
QPS._lastPartyRoster = QPS._lastPartyRoster or {}
QPS._lastPartyOnline = QPS._lastPartyOnline or {}

--------------------------------------------------
-- PARTY BROADCAST FUNCTIONS
--------------------------------------------------
-- Sends a party progress message using the QPS addon channel
function QPS.Tooltip.SendProgress(quest, objIdx, text, finished, progressOwner)
    if not quest or not text then
        LogDebugMessage(QPS_ProgressDebugLog, "[QPS-WARN] SendProgress: missing quest or text, aborting")
        return
    end
    objIdx = tostring(objIdx or "")
    if finished == nil then finished = 0 end
    finished = (finished == 1 or finished == "1") and 1 or 0
    if not progressOwner or progressOwner == "" then progressOwner = UnitName("player") end
    local msg = quest..":::"..objIdx..":::"..text..":::"..finished..":::"..progressOwner
    local msgLen = StringLib.Len(msg)
    if msgLen > 250 then
        LogDebugMessage(QPS_ProgressDebugLog, "[QPS-WARN] SendProgress: message too long (" .. tostring(msgLen) .. " bytes): " .. tostring(msg))
        return
    end
    if SendAddonMessage then
        local ok, err = pcall(function()
            SendAddonMessage("QPS", msg, "PARTY")
        end)
        if not ok then LogDebugMessage(QPS_ProgressDebugLog, "[QPS-ERROR] SendProgress: SendAddonMessage failed: " .. tostring(err)) end
    else
        LogDebugMessage(QPS_ProgressDebugLog, "[QPS-ERROR] SendProgress: SendAddonMessage not available, could not send progress message")
    end
end

-- Broadcasts a 'quest abandoned' message to the party for sync
function QPS.Tooltip.BroadcastQuestAbandoned(questTitle)
    QPS.Tooltip.SendProgress(questTitle, "", "quest abandoned", 0, UnitName("player"))
    LogDebugMessage(QPS_SyncDebugLog, "[QPS-INFO] Broadcasted 'quest abandoned' for '" .. tostring(questTitle) .. "'")
end

-- Broadcasts a 'quest completed' message to the party for sync
function QPS.Tooltip.BroadcastQuestCompleted(questTitle)
    QPS.Tooltip.SendProgress(questTitle, "", "quest completed", 1, UnitName("player"))
    LogDebugMessage(QPS_SyncDebugLog, "[QPS-INFO] Broadcasted 'quest completed' for '" .. tostring(questTitle) .. "'")
end

-- Broadcasts quest accepted or progress updates to the party for sync
function QPS.Tooltip.BroadcastQuestUpdate(title, text, finished, objectiveIndex, logLabel)
    local safeTitle, safeText = SanitizeAddonMessage(title, text)
    local safeObjectiveIndex = tostring(objectiveIndex or "")
    -- Use SendProgress for consistency (includes progressOwner and 5 fields)
    QPS.Tooltip.SendProgress(safeTitle, safeObjectiveIndex, safeText, finished and 1 or 0, UnitName("player"))
    local label = logLabel or "quest update"
    LogDebugMessage(QPS_SyncDebugLog, "[QPS-INFO] Broadcasted " .. label .. " for '" .. tostring(title) .. "' (SendProgress, 5 fields)")
end

-- Broadcasts all of the player's current quest progress to the party
function QPS.Tooltip.BroadcastPartyProgress()
    local playerName = UnitName("player")
    if not playerName or type(QPS_SavedProgress) ~= "table" then
        LogDebugMessage(QPS_ProgressDebugLog, "[QPS-WARN] BroadcastPartyProgress: QPS_SavedProgress not a table or playerName missing")
        return
    end
    for key, value in pairs(QPS_SavedProgress) do
        local quest, objIdx = StringLib.ExtractQuestAndObjIdx(key)
        if quest and objIdx and StringLib.HasNumberSlashNumber(value) then
            QPS.Tooltip.SendProgress(quest, objIdx, value)
        end
    end
    -- Optionally, send complete flag if all objectives are complete
    local questSet = {}
    for key, value in pairs(QPS_SavedProgress) do
        local quest, objIdx = StringLib.ExtractQuestAndObjIdx(key)
        if quest and objIdx then
            questSet[quest] = questSet[quest] or {}
            if StringLib.Find(value, ": ") and StringLib.HasNumberSlashNumber(value) then
                table.insert(questSet[quest], value)
            end
        end
    end
    for quest, objectives in pairs(questSet) do
        local allComplete = true
        local foundAny = false
        for _, text in pairs(objectives) do
            if StringLib.Find(text, ":%s*%d+/%d+") then
                local x, y = StringLib.SafeExtractNumbers(text)
                if not (x and y and tonumber(x) >= tonumber(y)) then
                    allComplete = false
                end
                foundAny = true
            else
                allComplete = false
            end
        end
        if foundAny and allComplete then
            LogDebugMessage(QPS_ProgressDebugLog, "[QPS-INFO] BroadcastPartyProgress: Sending COMPLETE for quest='" .. tostring(quest) .. "' (all objectives are complete)")
            QPS.Tooltip.SendProgress(quest, "complete", "1")
        end
    end
end

--------------------------------------------------
-- TOOLTIP FRAME SETUP
--------------------------------------------------
-- Custom tooltip for displaying party quest progress
local PartyTooltip = CreateFrame("GameTooltip", "QPSPartyTooltip", UIParent, "GameTooltipTemplate")
PartyTooltip:SetFrameStrata("TOOLTIP")
PartyTooltip:Hide()

--------------------------------------------------
-- PARTY SYNC AND UTILITY FUNCTIONS
--------------------------------------------------
-- Request a full party sync (used on login/party change)
local function RequestPartySync()
    LogDebugMessage(QPS_SyncDebugLog, "[QPS-DEBUG] Sending party resync request (RequestPartySync)")
    if SendAddonMessage then
        SendAddonMessage("QPS", "QPS_SYNC_REQUEST", "PARTY")
        LogDebugMessage(QPS_SyncDebugLog, "[QPS-DEBUG] Sent QPS_SYNC_REQUEST via addon channel only (RequestPartySync)")
    else
        LogDebugMessage(QPS_SyncDebugLog, "[QPS-DEBUG] SendAddonMessage not available, could not send QPS_SYNC_REQUEST")
    end
end

-- Returns true if the given party member is online
local function IsPartyMemberOnline(name)
    if not name then return false end
    if name == UnitName("player") then return true end
    for i = 1, GetNumPartyMembers() do
        local unit = "party" .. i
        if UnitName(unit) == name then
            return UnitIsConnected(unit)
        end
    end
    return false
end

-- Returns a set of all current party members (including player)
local function GetCurrentPartyMembers()
    local members = {}
    local playerName = UnitName("player")
    if playerName then members[playerName] = true end
    for i = 1, GetNumPartyMembers() do
        local name = UnitName("party" .. i)
        if name then members[name] = true end
    end
    local memberList = {}
    for n in pairs(members) do table.insert(memberList, n) end
    LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] GetCurrentPartyMembers: " .. table.concat(memberList, ", "))
    return members
end

-- Returns a table of party progress for a given quest title, filtered to current party
local function GetPartyProgress(questTitle)
    local result = {}
    local partySet = GetCurrentPartyMembers()
    for sender, quests in pairs(QPS_PartyProgress) do
        if partySet[sender] and quests[questTitle] then
            result[sender] = quests[questTitle]
        end
    end
    return result
end
QPS.Tooltip.GetPartyProgress = GetPartyProgress

-- Tooltip position update handler (follows cursor)
local function PartyTooltipOnUpdate()
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x = x / scale
    y = y / scale
    PartyTooltip:ClearAllPoints()
    PartyTooltip:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", x - 20, y)
end

-- Hides the party progress tooltip
local function HidePartyProgressTooltip()
    LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] HidePartyProgressTooltip called, tooltip hidden")
    PartyTooltip:Hide()
    PartyTooltip:SetScript("OnUpdate", nil)
end

-- Hooks pfQuest tracker buttons to show party progress on hover
local function HookTrackerButtons(logOnce)
    if logOnce then LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] HookTrackerButtons called, pfQuest.tracker.buttons: " .. tostring(pfQuest and pfQuest.tracker and pfQuest.tracker.buttons)) end
    local hookedAny = false
    if pfQuest and pfQuest.tracker and pfQuest.tracker.buttons then
        for id, btn in pairs(pfQuest.tracker.buttons) do
            if btn then
                LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] Examining tracker button id: " .. tostring(id) .. ", btn: " .. tostring(btn) .. ", title: " .. tostring(btn.title))
            end
            if btn and btn:GetScript("OnEnter") then
                if not btn.QPS_Hooked then
                    btn.QPS_OrigEnter = btn:GetScript("OnEnter")
                    btn:SetScript("OnEnter", TrackerButtonOnEnter)
                    btn.QPS_Hooked = true
                    LogDebugMessage(QPS_DebugLog, "[QPS-INFO] Set OnEnter hook for button id: " .. tostring(id))
                end
                hookedAny = true
            end
            if btn and btn:GetScript("OnLeave") then
                if not btn.QPS_HookedLeave then
                    btn.QPS_OrigLeave = btn:GetScript("OnLeave")
                    btn:SetScript("OnLeave", TrackerButtonOnLeave)
                    btn.QPS_HookedLeave = true
                    LogDebugMessage(QPS_DebugLog, "[QPS-INFO] Set OnLeave hook for button id: " .. tostring(id))
                end
                hookedAny = true
            end
        end
    else
        LogDebugMessage(QPS_DebugLog, "[QPS-WARN] pfQuest.tracker.buttons not available, pfQuest: " .. tostring(pfQuest) .. ", pfQuest.tracker: " .. tostring(pfQuest and pfQuest.tracker))
    end
    return hookedAny
end

-- Checks for party roster changes and broadcasts progress if needed
local function CheckPartyChangesAndBroadcast()
    local currentRoster = {}
    local playerName = UnitName("player")
    if playerName then currentRoster[playerName] = true end
    for i = 1, GetNumPartyMembers() do
        local name = UnitName("party"..i)
        if name then currentRoster[name] = true end
    end
    for name in pairs(currentRoster) do
        if not QPS._lastPartyRoster[name] or (not QPS._lastPartyOnline[name] and IsPartyMemberOnline(name)) then
            if name == playerName then
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] CheckPartyChangesAndBroadcast: New member or member came online: " .. tostring(name))
                QPS.Tooltip.BroadcastPartyProgress()
            end
        end
        QPS._lastPartyOnline[name] = IsPartyMemberOnline(name)
    end
    for name in pairs(QPS._lastPartyRoster) do
        if not currentRoster[name] then
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] CheckPartyChangesAndBroadcast: Party member left or offline: " .. tostring(name))
            QPS._lastPartyOnline[name] = nil
            -- Remove party progress data for offline/left member
            if QPS_PartyProgress[name] then
                QPS_PartyProgress[name] = nil
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Removed QPS_PartyProgress data for offline/left member: " .. tostring(name))
            end
        end
    end
    QPS._lastPartyRoster = currentRoster
end

--------------------------------------------------
-- PARTY PROGRESS TOOLTIP LOGIC
--------------------------------------------------
-- Shows the party progress tooltip for a given quest title
local function ShowPartyProgressTooltip(anchorFrame, questTitle)
    -- Remove party progress for offline/left members on every hover
    local currentMembers = GetCurrentPartyMembers()
    for member in pairs(QPS_PartyProgress) do
        if not currentMembers[member] and member ~= UnitName("player") then
            QPS_PartyProgress[member] = nil
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Hover cleanup: Removed QPS_PartyProgress data for offline/left member: " .. tostring(member))
        end
    end
    -- Always strip level tag from quest title for lookup
    local origTitle = questTitle
    if questTitle then
        -- Remove [level] or [level+] tag with optional leading spaces
        questTitle = StringLib.Gsub(questTitle, "^%s*%[%d+%+?%]%s*", "")
        -- Remove any remaining leading spaces
        questTitle = StringLib.Gsub(questTitle, "^%s+", "")
        if not questTitle or questTitle == "" then
            questTitle = origTitle -- fallback if stripping fails
        end
    end
    LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] ShowPartyProgressTooltip: Lookup using stripped questTitle='" .. tostring(questTitle) .. "' (original='" .. tostring(origTitle) .. "')")
    -- Only show if there is at least one other party member
    if (GetNumPartyMembers and GetNumPartyMembers() == 0) then
        LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Not showing party progress tooltip: no party members.")
        return
    end
    LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] ShowPartyProgressTooltip: Showing for quest: " .. tostring(questTitle))
    local partyProgress = QPS.Tooltip.GetPartyProgress(questTitle)
    if not partyProgress or not next(partyProgress) then
        LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] ShowPartyProgressTooltip: No party progress for: " .. tostring(questTitle))
        return
    end
    PartyTooltip:ClearLines()
    PartyTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    PartyTooltip:ClearAllPoints()
    -- Initial position, will be updated by OnUpdate
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x = x / scale
    y = y / scale
    PartyTooltip:SetPoint("RIGHT", UIParent, "BOTTOMLEFT", x - 20, y)
    PartyTooltip:AddLine("|cffb48affParty Progress:|r")
    for member, progress in pairs(partyProgress) do
        if type(progress) ~= "table" then
            LogDebugMessage(QPS_EventDebugLog, "[QPS-WARN] ShowPartyProgressTooltip: Skipping member " .. tostring(member) .. " because progress is not a table: " .. tostring(progress))
        end
        if type(progress) == "table" then
            -- Get class color for member
            local classColor = "|cffffff00" -- default yellow
            local class
            if member == UnitName("player") then
                class = UnitClass("player")
            else
                for i = 1, GetNumPartyMembers() do
                    if UnitName("party"..i) == member then
                        class = UnitClass("party"..i)
                        break
                    end
                end
            end
            -- Safe class color lookup
            if class then
                local classToken = StringLib.Upper(class)
                local c = QPS_CLASS_COLORS and QPS_CLASS_COLORS[classToken]
                if c and c.r and c.g and c.b then
                    classColor = "|cff"
                        .. StringLib.ByteToHex(math.floor(c.r*255))
                        .. StringLib.ByteToHex(math.floor(c.g*255))
                        .. StringLib.ByteToHex(math.floor(c.b*255))
                else
                    classColor = "|cffffff00" -- fallback yellow
                end
            else
                classColor = "|cffffff00" -- fallback yellow
            end
            -- Determine if all objectives are complete for this member
            local allComplete = true
            local foundAnyObjective = false
            local matchingObjectives = {}
            for obj, text in pairs(progress) do
                if obj ~= "complete" and type(text) == "string" then
                    local trimmedText = StringLib.Gsub(text, "^%s*(.-)%s*$", "%1")
                    if StringLib.Lower(trimmedText) == "quest abandoned" then
                        -- Do not display abandoned quests in the party progress tooltip
                        -- (Intentionally skip showing any progress for abandoned state)
                    else
                        if StringLib.Find(trimmedText, ": ") and StringLib.HasNumberSlashNumber(trimmedText) then
                            foundAnyObjective = true
                            -- Log byte values for debugging
                            if QPS_DebugLog then
                                local bytes = {}
                                for i = 1, StringLib.Len(trimmedText) do
                                    table.insert(bytes, StringLib.Byte(trimmedText, i))
                                end
                                LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] Bytes for '" .. tostring(trimmedText) .. "': " .. table.concat(bytes, ","))
                            end
                            -- Extract numbers for progress
                            local x, y = nil, nil
                            if StringLib.HasNumberSlashNumber(trimmedText) then
                                x, y = StringLib.SafeExtractNumbers(trimmedText)
                            end
                            local colorText = trimmedText
                            if x and y then
                                x = tonumber(x)
                                y = tonumber(y)
                                LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Extracted numbers for objective: x=" .. tostring(x) .. ", y=" .. tostring(y))
                                if x < y then
                                    colorText = "|cffff4040" .. trimmedText .. "|r" -- red if not done
                                    allComplete = false
                                    LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Objective not complete: x < y for '" .. tostring(trimmedText) .. "'")
                                else
                                    colorText = "|cff40ff40" .. trimmedText .. "|r" -- green if done or over
                                    LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Objective complete: x >= y for '" .. tostring(trimmedText) .. "'")
                                end
                            else
                                allComplete = false
                                LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Could not extract numbers for objective: '" .. tostring(trimmedText) .. "'")
                            end
                            LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Matched objective for " .. tostring(member) .. ": " .. tostring(trimmedText))
                            table.insert(matchingObjectives, colorText)
                        else
                            LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Skipped non-objective: " .. tostring(trimmedText))
                        end
                    end
                end
            end
            -- If no objectives found, don't show complete
            if not foundAnyObjective then allComplete = false end
            local showComplete = allComplete -- Always use local calculation for all members
            local line = classColor .. member .. "|r" .. (showComplete and " |cff00ff00(Complete)|r" or "")
            if foundAnyObjective then
                PartyTooltip:AddLine(line)
                for _, text in pairs(matchingObjectives) do
                    PartyTooltip:AddLine("    - " .. text, 1, 1, 1)
                end
            end
        end
    end
    PartyTooltip:Show()
    PartyTooltip:SetScript("OnUpdate", PartyTooltipOnUpdate)
end

--------------------------------------------------
-- EVENT HOOKS AND REGISTRATION
--------------------------------------------------
-- pfQuest tracker button hover handlers
function TrackerButtonOnEnter()
    local btn = this
    if btn and btn.title then
        ShowPartyProgressTooltip(btn, btn.title)
    end
end

function TrackerButtonOnLeave()
    HidePartyProgressTooltip()
end

-- Hooks Blizzard and pfUI/pfQuest quest log title buttons for party progress tooltips
local function HookQuestLogTitleButtons()
    local QUESTS_DISPLAYED = (type(QUESTS_DISPLAYED) == "number" and QUESTS_DISPLAYED) or 23
    for i = 1, QUESTS_DISPLAYED do
        local btn = nil
        if type(getglobal) == "function" then
            btn = getglobal("QuestLogTitle"..i)
        end
        if btn and not btn.QPS_QPSTooltipHooked then
            btn.QPS_QPSTooltipHooked = true
            local origOnEnter = btn.GetScript and btn:GetScript("OnEnter")
            btn:SetScript("OnEnter", function()
                if origOnEnter then origOnEnter() end
                local questTitle = btn:GetText()
                if questTitle then
                    questTitle = StringLib.Gsub(questTitle, "^%s*%[%d+%+?%]%s*", "")
                    questTitle = StringLib.Gsub(questTitle, "^%s+", "")
                    ShowPartyProgressTooltip(btn, questTitle)
                end
            end)
            local origOnLeave = btn.GetScript and btn:GetScript("OnLeave")
            btn:SetScript("OnLeave", function()
                if origOnLeave then origOnLeave() end
                HidePartyProgressTooltip()
            end)
        end
    end
end

-- Ensures hooks are set when the quest log is shown
local function HookQuestLogOnShow()
    local frame = nil
    if type(getglobal) == "function" then
        frame = getglobal("QuestLogFrame")
    end
    if frame and not frame.QPS_QPSTooltipOnShowHooked then
        frame.QPS_QPSTooltipOnShowHooked = true
        local origOnShow = frame.GetScript and frame:GetScript("OnShow")
        frame:SetScript("OnShow", function()
            if origOnShow then origOnShow() end
            HookQuestLogTitleButtons()
        end)
    end
end

-- Hooks pfQuest tracker if available
local function SafeHookPfQuestTracker(logOnce)
    if pfQuest and pfQuest.tracker and pfQuest.tracker.buttons then
        return HookTrackerButtons(logOnce)
    end
    return false
end

-- Initial hook on login and periodically
local QuestLogHookFrame = CreateFrame("Frame")
QuestLogHookFrame:RegisterEvent("PLAYER_LOGIN")
QuestLogHookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
QuestLogHookFrame:SetScript("OnEvent", function()
    HookQuestLogOnShow()
    HookQuestLogTitleButtons()
    SafeHookPfQuestTracker(true)
end)

-- Periodic re-hook to ensure all tracker buttons are always hooked
if not QPS._trackerRehookFrame then
    QPS._trackerRehookFrame = CreateFrame("Frame")
    QPS._trackerRehookFrame._qps_lastRehook = time()
    QPS._trackerRehookFrame:SetScript("OnUpdate", function()
        local now = time()
        if (now - QPS._trackerRehookFrame._qps_lastRehook) >= 5 then
            SafeHookPfQuestTracker(false)
            QPS._trackerRehookFrame._qps_lastRehook = now
        end
    end)
end

-- Party progress events (party changes, login, etc)
if not QPS._partyProgressEventsHooked then
    local PartyFrame = CreateFrame("Frame")
    PartyFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    PartyFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    PartyFrame:RegisterEvent("PLAYER_LOGIN")
    PartyFrame:RegisterEvent("PLAYER_ALIVE")
    PartyFrame._qps_lastPartySync = 0
    PartyFrame:SetScript("OnEvent", function()
        if (event == "PLAYER_ENTERING_WORLD") then
            local partyCount = GetNumPartyMembers()
            local currentEvent = event or arg1 or "?"
            if QPS_DebugLog then LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Event: " .. tostring(currentEvent) .. ", party members: " .. tostring(partyCount)) end
            if partyCount > 0 then
                QPS_PartyProgress = {}
                RequestPartySync()
                QPS.Tooltip.BroadcastPartyProgress()
            end
        elseif (event == "PARTY_MEMBERS_CHANGED") then
            local partyCount = GetNumPartyMembers()
            local currentEvent = event or arg1 or "?"
            if QPS_DebugLog then LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Event: " .. tostring(currentEvent) .. ", party members: " .. tostring(partyCount)) end
            if partyCount > 0 then
                RequestPartySync()
                QPS.Tooltip.BroadcastPartyProgress()
            end
        end
        CheckPartyChangesAndBroadcast()
    end)
    QPS._partyProgressEventsHooked = true
end

-- Party progress addon channel listener (handles incoming party sync messages)
if not QPS._partyProgressAddonListener then
    local AddonListener = CreateFrame("Frame")
    AddonListener:RegisterEvent("CHAT_MSG_ADDON")
    AddonListener:RegisterEvent("QUEST_LOG_UPDATE")
    QPS.AddonListener = AddonListener
    AddonListener:SetScript("OnEvent", function()
        if event == "CHAT_MSG_ADDON" then
            local prefix, message, channel, sender = arg1, arg2, arg3, arg4
            if prefix == "QPS" then
                if channel ~= "PARTY" then
                    LogDebugMessage(QPS_SyncDebugLog, "[QPS-DEBUG] Skipping non-PARTY addon message, channel: "..tostring(channel))
                    return
                end
                if sender == UnitName("player") then return end
                local parts = StringLib.Split(message, ":::")
                local quest, objIdx, text, finished, progressOwner = parts[1], parts[2], parts[3], parts[4], parts[5]
                if progressOwner and progressOwner == UnitName("player") then return end
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Received party progress: sender='" .. tostring(sender) .. "', quest='" .. tostring(quest) .. "'")
                if message == "QPS_SYNC_REQUEST" then
                    LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Received QPS_SYNC_REQUEST from " .. tostring(sender))
                    QPS.Tooltip.BroadcastPartyProgress()
                    return
                end
                -- Handle 'quest abandoned' and 'quest complete' messages
                local trimmedText = text and StringLib.Lower(StringLib.Gsub(text, "^%s*(.-)%s*$", "%1")) or nil
                if trimmedText == "quest abandoned" then
                    if QPS_PartyProgress[progressOwner or sender] then
                        QPS_PartyProgress[progressOwner or sender][quest] = nil
                        LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Removed QPS_PartyProgress for player '" .. tostring(progressOwner or sender) .. "', quest '" .. tostring(quest) .. "' due to abandon message")
                    end
                    return
                elseif trimmedText == "quest completed" then
                    if QPS_PartyProgress[progressOwner or sender] then
                        QPS_PartyProgress[progressOwner or sender][quest] = nil
                        LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Removed QPS_PartyProgress for player '" .. tostring(progressOwner or sender) .. "', quest '" .. tostring(quest) .. "' due to complete message")
                    end
                    return
                end
                -- Ignore our own progress messages to avoid polluting QPS_PartyProgress
                if sender == UnitName("player") then return end
                local parts = StringLib.Split(message, ":::")
                LogDebugMessage(QPS_SyncDebugLog, "[QPS-DEBUG] Split message parts: " .. table.concat(parts, ", "))
                local quest, objIdx, text, finished, progressOwner = parts[1], parts[2], parts[3], parts[4], parts[5]
                if not quest or not text then
                    LogDebugMessage(QPS_EventDebugLog, "[QPS-WARN] Skipping message: missing quest or text.")
                    return
                end
                objIdx = tonumber(objIdx) or 1
                finished = tonumber(finished) or 0
                if not progressOwner or progressOwner == "" then progressOwner = sender end
                if finished ~= 0 and finished ~= 1 then
                    LogDebugMessage(QPS_EventDebugLog, "[QPS-ERROR] Invalid 'finished' value received: '" .. tostring(finished) .. "' for quest '" .. tostring(quest) .. "' from '" .. tostring(sender) .. "'")
                end
                LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Storing progress: progressOwner='" .. tostring(progressOwner) .. "', quest='" .. tostring(quest) .. "', objIdx='" .. tostring(objIdx) .. "', text='" .. tostring(text) .. "', finished='" .. tostring(finished) .. "'")
                QPS_PartyProgress[progressOwner] = QPS_PartyProgress[progressOwner] or {}
                QPS_PartyProgress[progressOwner][quest] = QPS_PartyProgress[progressOwner][quest] or {}
                QPS_PartyProgress[progressOwner][quest][objIdx] = text
                QPS_PartyProgress[progressOwner][quest].complete = (finished == 1)
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Received quest progress: progressOwner='" .. tostring(progressOwner) .. "', quest='" .. tostring(quest) .. "', objIdx='" .. tostring(objIdx) .. "', text='" .. tostring(text) .. "', finished='" .. tostring(finished) .. "'")
                if QPS_DebugLog then
                    local dump = "[QPS-DEBUG] QPS_PartyProgress now: "
                    for member, quests in pairs(QPS_PartyProgress) do
                        dump = dump .. member .. "={"
                        for q, objs in pairs(quests) do
                            dump = dump .. q .. ":["
                            for o, v in pairs(objs) do
                                dump = dump .. tostring(o) .. "=" .. tostring(v) .. ","
                            end
                            dump = dump .. "] "
                        end
                        dump = dump .. "} "
                    end
                    LogDebugMessage(QPS_DebugLog, dump)
                end
            end
        end
    end)
    QPS._partyProgressAddonListener = true
end