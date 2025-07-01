-- Tooltip.lua: Handles quest progress tooltips and party progress display for QuestProgressShare.
-- Manages tooltip integration, party sync, and robust display of quest progress for all group members.
--
-- TOOLTIP SYSTEM BEHAVIOR:
-- 1. Quest log and tracker tooltips: Always use PartyTooltip for consistency and to avoid conflicts
--    - When pfUI is enabled: PartyTooltip is styled to match pfUI appearance
--    - When pfUI is disabled: PartyTooltip uses clean default styling
-- 2. World object/mob tooltips: Always use GameTooltip integration for unified display
--    - Integrates seamlessly with pfQuest, pfUI, or vanilla tooltips
--    - Uses helper functions for consistent member progress display and coloring
-- 3. This approach avoids styling conflicts and ensures quest link functionality always works

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

-- Returns true if pfUI is enabled and available
local function IsPfUIEnabled()
    local pfUIEnabled = false
    if IsAddOnLoaded then
        pfUIEnabled = IsAddOnLoaded("pfUI") or IsAddOnLoaded("pfUI-turtle")
    end
    
    -- Also check if pfUI objects exist and are functional
    local pfUIObjectsExist = pfUI and pfUI.api and pfUI.api.CreateBackdrop and type(pfUI.api.CreateBackdrop) == "function"
    
    local enabled = pfUIEnabled and pfUIObjectsExist
    LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] IsPfUIEnabled check: pfUIEnabled=" .. tostring(pfUIEnabled) .. ", pfUIObjectsExist=" .. tostring(pfUIObjectsExist) .. ", enabled=" .. tostring(enabled))
    return enabled
end

-- Returns true if pfQuest is enabled and available
local function IsPfQuestEnabled()
    -- First check if pfQuest addon is actually enabled in the addon list
    local pfQuestAddonEnabled = false
    if IsAddOnLoaded then
        pfQuestAddonEnabled = IsAddOnLoaded("pfQuest") or IsAddOnLoaded("pfQuest-turtle") or IsAddOnLoaded("pfQuest-tbc") or IsAddOnLoaded("pfQuest-wotlk")
    end
    
    -- If pfUI is loaded but pfQuest is not, we should not use pfQuest tooltips
    local pfUIEnabled = false
    if IsAddOnLoaded then
        pfUIEnabled = IsAddOnLoaded("pfUI") or IsAddOnLoaded("pfUI-turtle")
    end
    
    -- If pfUI is enabled but pfQuest is not, force disable pfQuest functionality
    if pfUIEnabled and not pfQuestAddonEnabled then
        LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] pfUI is enabled but pfQuest is disabled, forcing pfQuest functionality OFF")
        return false
    end
    
    -- Also check if pfQuest objects exist and are functional
    local pfQuestObjectsExist = pfMap and pfMap.tooltip and type(pfMap.tooltip) == "table" and pfMap.tooltip.GetColor
    
    local enabled = pfQuestAddonEnabled and pfQuestObjectsExist
    LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] IsPfQuestEnabled check: pfQuestAddonEnabled=" .. tostring(pfQuestAddonEnabled) .. ", pfUIEnabled=" .. tostring(pfUIEnabled) .. ", pfQuestObjectsExist=" .. tostring(pfQuestObjectsExist) .. ", enabled=" .. tostring(enabled))
    return enabled
end

-- Helper function to get member class color consistently across all tooltip displays
local function GetMemberClassColor(member)
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
    
    return classColor
end

-- Helper function to process world tooltip objectives for a member
-- Used to determine completion status and filter objectives relevant to the current entity
local function ProcessWorldTooltipObjectives(progress, entityName)
    local allComplete = true
    local foundAnyObjective = false
    local relevantObjectives = {}
    
    for obj, text in pairs(progress) do
        if obj ~= "complete" and type(text) == "string" then
            local trimmedText = StringLib.Gsub(text, "^%s*(.-)%s*$", "%1")
            if StringLib.Lower(trimmedText) ~= "quest abandoned" then
                -- Check if this objective is related to the current entity
                if StringLib.Find(StringLib.Lower(trimmedText), StringLib.Lower(entityName)) then
                    foundAnyObjective = true
                    table.insert(relevantObjectives, trimmedText)
                    
                    if StringLib.Find(trimmedText, ": ") and StringLib.HasNumberSlashNumber(trimmedText) then
                        local x, y = StringLib.SafeExtractNumbers(trimmedText)
                        if not (x and y and tonumber(x) >= tonumber(y)) then
                            allComplete = false
                        end
                    else
                        allComplete = false
                    end
                end
            end
        end
    end
    
    -- Check if quest is marked complete
    if progress.complete then 
        allComplete = true 
    end
    
    return allComplete, foundAnyObjective, relevantObjectives
end

-- Helper function to add world tooltip party progress for a member
-- Unified logic for displaying member progress in world tooltips with proper coloring
local function AddWorldTooltipMemberProgress(tooltip, member, progress, entityName)
    if type(progress) ~= "table" then return end
    
    -- Get class color for member
    local classColor = GetMemberClassColor(member)
    
    -- Process objectives using helper function
    local allComplete, foundAnyObjective, relevantObjectives = ProcessWorldTooltipObjectives(progress, entityName)
    
    -- Only show members who have relevant objectives for this entity
    if foundAnyObjective then
        local line = classColor .. member .. "|r" .. (allComplete and " |cff00ff00(Complete)|r" or "")
        tooltip:AddLine(line)
        
        for _, text in pairs(relevantObjectives) do
            local color = allComplete and "|cff00ff00" or "|cffff8888"
            tooltip:AddLine("  - " .. color .. text .. "|r", 1, 1, 1)
        end
    end
end


-- Returns a set of all current party members who are online (including player)
local function GetCurrentOnlinePartyMembers()
    local members = {}
    local playerName = UnitName("player")
    if playerName then members[playerName] = true end
    for i = 1, GetNumPartyMembers() do
        local name = UnitName("party" .. i)
        if name and IsPartyMemberOnline(name) then 
            members[name] = true 
        end
    end
    local memberList = {}
    for n in pairs(members) do table.insert(memberList, n) end
    LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] GetCurrentOnlinePartyMembers: " .. table.concat(memberList, ", "))
    return members
end

-- Returns a table of party progress for a given quest title, filtered to current online party members
local function GetPartyProgress(questTitle)
    local result = {}
    local partySet = GetCurrentOnlinePartyMembers()  -- Only show online members
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
    -- Hide our custom PartyTooltip
    PartyTooltip:Hide()
    PartyTooltip:SetScript("OnUpdate", nil)
    -- Clear the party progress added flags for GameTooltip (used by world tooltips)
    if GameTooltip then
        GameTooltip.QPS_PartyProgressAdded = nil
    end
end

-- Hooks pfQuest tracker buttons to show party progress on hover
local function HookTrackerButtons(logOnce)
    if logOnce then LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] HookTrackerButtons called, IsPfQuestEnabled(): " .. tostring(IsPfQuestEnabled())) end
    local hookedAny = false
    if IsPfQuestEnabled() and pfQuest.tracker and pfQuest.tracker.buttons then
        for id, btn in pairs(pfQuest.tracker.buttons) do
            if btn then
                LogVerboseDebugMessage(QPS_DebugLog, "[QPS-DEBUG] Examining tracker button id: " .. tostring(id) .. ", btn: " .. tostring(btn) .. ", title: " .. tostring(btn.title))
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
        LogDebugMessage(QPS_DebugLog, "[QPS-WARN] pfQuest tracker not available or pfQuest is disabled")
    end
    return hookedAny
end

-- Checks for party roster changes and broadcasts progress if needed
local function CheckPartyChangesAndBroadcast()
    local currentRoster = {}
    local currentOnlineRoster = {}
    local playerName = UnitName("player")
    if playerName then 
        currentRoster[playerName] = true 
        currentOnlineRoster[playerName] = true
    end
    
    -- Build roster of all party members (online and offline)
    for i = 1, GetNumPartyMembers() do
        local name = UnitName("party"..i)
        if name then 
            currentRoster[name] = true 
            if IsPartyMemberOnline(name) then
                currentOnlineRoster[name] = true
            end
        end
    end
    
    -- Check for new members or members coming online
    for name in pairs(currentRoster) do
        if not QPS._lastPartyRoster[name] or (not QPS._lastPartyOnline[name] and IsPartyMemberOnline(name)) then
            if name == playerName then
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] CheckPartyChangesAndBroadcast: New member or member came online: " .. tostring(name))
                QPS.Tooltip.BroadcastPartyProgress()
            end
        end
        QPS._lastPartyOnline[name] = IsPartyMemberOnline(name)
    end
    
    -- Check for members who left the party
    for name in pairs(QPS._lastPartyRoster) do
        if not currentRoster[name] then
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] CheckPartyChangesAndBroadcast: Party member left: " .. tostring(name))
            QPS._lastPartyOnline[name] = nil
            -- Remove party progress data for member who left
            if QPS_PartyProgress[name] then
                QPS_PartyProgress[name] = nil
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Removed QPS_PartyProgress data for member who left: " .. tostring(name))
            end
        end
    end
    
    -- Check for members who went offline (but are still in party)
    for name in pairs(QPS._lastPartyOnline) do
        if QPS._lastPartyOnline[name] and currentRoster[name] and not currentOnlineRoster[name] then
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] CheckPartyChangesAndBroadcast: Party member went offline: " .. tostring(name))
            QPS._lastPartyOnline[name] = false
            -- Remove party progress data for offline member
            if QPS_PartyProgress[name] then
                QPS_PartyProgress[name] = nil
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Removed QPS_PartyProgress data for offline member: " .. tostring(name))
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
    local currentOnlineMembers = GetCurrentOnlinePartyMembers()
    for member in pairs(QPS_PartyProgress) do
        if not currentOnlineMembers[member] and member ~= UnitName("player") then
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

    -- Always use PartyTooltip for quest log/tracker tooltips for consistency
    LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] ShowPartyProgressTooltip: Using PartyTooltip" .. (IsPfUIEnabled() and " with pfUI styling" or " (clean style)"))
    PartyTooltip:ClearLines()
    PartyTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    PartyTooltip:ClearAllPoints()
    
    -- Apply pfUI styling if available
    if IsPfUIEnabled() then
        LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] Applying pfUI styling to PartyTooltip")
        
        -- Apply pfUI's backdrop styling to make PartyTooltip match pfUI's appearance
        local alpha = pfUI_config and pfUI_config.tooltip and pfUI_config.tooltip.alpha and tonumber(pfUI_config.tooltip.alpha) or 0.9
        
        -- Only apply styling if not already applied
        if not PartyTooltip.pfui_styled then
            pfUI.api.CreateBackdrop(PartyTooltip, nil, nil, alpha)
            if pfUI.api.CreateBackdropShadow then
                pfUI.api.CreateBackdropShadow(PartyTooltip)
            end
            PartyTooltip.pfui_styled = true
            LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] Successfully applied pfUI styling to PartyTooltip")
        end
    end
    
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
            local classColor = GetMemberClassColor(member)
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
                            -- Extract numbers for progress
                            local x, y = nil, nil
                            if StringLib.HasNumberSlashNumber(trimmedText) then
                                x, y = StringLib.SafeExtractNumbers(trimmedText)
                            end
                            local colorText = trimmedText
                            if x and y then
                                x = tonumber(x)
                                y = tonumber(y)
                                LogVerboseDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Extracted numbers for objective: x=" .. tostring(x) .. ", y=" .. tostring(y))
                                if x < y then
                                    colorText = "|cffff4040" .. trimmedText .. "|r" -- red if not done
                                    allComplete = false
                                    LogVerboseDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Objective not complete: x < y for '" .. tostring(trimmedText) .. "'")
                                else
                                    colorText = "|cff40ff40" .. trimmedText .. "|r" -- green if done or over
                                    LogVerboseDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Objective complete: x >= y for '" .. tostring(trimmedText) .. "'")
                                end
                            else
                                allComplete = false
                                LogVerboseDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Could not extract numbers for objective: '" .. tostring(trimmedText) .. "'")
                            end
                            LogVerboseDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Matched objective for " .. tostring(member) .. ": " .. tostring(trimmedText))
                            table.insert(matchingObjectives, colorText)
                        else
                            LogVerboseDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Skipped non-objective: " .. tostring(trimmedText))
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
    if btn then
        -- Call the original pfQuest handler first if it exists (only if pfQuest is enabled)
        if IsPfQuestEnabled() and btn.QPS_OrigEnter then
            btn.QPS_OrigEnter()
        end
        -- Then add our party progress (always uses PartyTooltip, styled for pfQuest when enabled)
        if btn.title then
            ShowPartyProgressTooltip(btn, btn.title)
        end
    end
end

function TrackerButtonOnLeave()
    local btn = this
    if btn and btn.QPS_OrigLeave then
        btn.QPS_OrigLeave()
    end
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

-- Hooks pfQuest tracker if available and enabled
local function SafeHookPfQuestTracker(logOnce)
    if IsPfQuestEnabled() and pfQuest.tracker and pfQuest.tracker.buttons then
        return HookTrackerButtons(logOnce)
    end
    return false
end

-- Initial hook on login
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
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Event: " .. tostring(currentEvent) .. ", party members: " .. tostring(partyCount))
            if partyCount > 0 then
                QPS_PartyProgress = {}
                RequestPartySync()
                QPS.Tooltip.BroadcastPartyProgress()
            end
        elseif (event == "PARTY_MEMBERS_CHANGED") then
            local partyCount = GetNumPartyMembers()
            local currentEvent = event or arg1 or "?"
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Event: " .. tostring(currentEvent) .. ", party members: " .. tostring(partyCount))
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
                LogVerboseDebugMessage(QPS_SyncDebugLog, "[QPS-DEBUG] Split message parts: " .. table.concat(parts, ", "))
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
                LogVerboseDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Storing progress: progressOwner='" .. tostring(progressOwner) .. "', quest='" .. tostring(quest) .. "', objIdx='" .. tostring(objIdx) .. "', text='" .. tostring(text) .. "', finished='" .. tostring(finished) .. "'")
                QPS_PartyProgress[progressOwner] = QPS_PartyProgress[progressOwner] or {}
                QPS_PartyProgress[progressOwner][quest] = QPS_PartyProgress[progressOwner][quest] or {}
                QPS_PartyProgress[progressOwner][quest][objIdx] = text
                QPS_PartyProgress[progressOwner][quest].complete = (finished == 1)
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Received quest progress: progressOwner='" .. tostring(progressOwner) .. "', quest='" .. tostring(quest) .. "', objIdx='" .. tostring(objIdx) .. "', text='" .. tostring(text) .. "', finished='" .. tostring(finished) .. "'")
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
                LogVerboseDebugMessage(QPS_DebugLog, dump)
            end
        end
    end)
    QPS._partyProgressAddonListener = true
end

--------------------------------------------------
-- WORLD OBJECT/MOB TOOLTIP INTEGRATION
--------------------------------------------------

-- Checks if a mob/object name is related to any quest that both player and party have
local function GetQuestRelatedToMobOrObject(entityName)
    if not entityName or entityName == "" then return nil end
    
    -- Get player's current quests and check which ones have objectives mentioning this entity
    local playerQuestsByEntity = {}
    for qid = 1, GetNumQuestLogEntries() do
        local qtitle, _, _, _, _, _ = GetQuestLogTitle(qid)
        if qtitle then
            local objectives = GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(qid)
            if objectives then
                for i = 1, objectives do
                    local text, type, finished = GetQuestLogLeaderBoard and GetQuestLogLeaderBoard(i, qid)
                    if text then
                        -- Check if this objective mentions the entity
                        -- Look for exact name matches and partial matches
                        local objectiveText = StringLib.Lower(text)
                        local entityLower = StringLib.Lower(entityName)
                        
                        if StringLib.Find(objectiveText, entityLower) then
                            playerQuestsByEntity[qtitle] = true
                            break
                        end
                    end
                end
            end
        end
    end
    
    -- Check if any online party member has progress for quests that involve this entity
    local partyMembers = GetCurrentOnlinePartyMembers()
    local relatedQuests = {}
    
    for member, quests in pairs(QPS_PartyProgress) do
        if partyMembers[member] then
            for questTitle, progress in pairs(quests) do
                if playerQuestsByEntity[questTitle] and type(progress) == "table" then
                    relatedQuests[questTitle] = true
                end
            end
        end
    end
    
    -- Return the first related quest found
    for questTitle in pairs(relatedQuests) do
        return questTitle
    end
    
    return nil
end

-- Shows party progress tooltip for world objects/mobs
local function ShowWorldTooltipPartyProgress(entityName)
    -- Remove party progress for offline/left members on every hover
    local currentOnlineMembers = GetCurrentOnlinePartyMembers()
    for member in pairs(QPS_PartyProgress) do
        if not currentOnlineMembers[member] and member ~= UnitName("player") then
            QPS_PartyProgress[member] = nil
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] World tooltip cleanup: Removed QPS_PartyProgress data for offline/left member: " .. tostring(member))
        end
    end
    
    local relatedQuest = GetQuestRelatedToMobOrObject(entityName)
    if not relatedQuest then
        return
    end
    
    -- Only show if there is at least one other party member
    if (GetNumPartyMembers and GetNumPartyMembers() == 0) then
        LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] Not showing world tooltip party progress: no party members.")
        return
    end
    
    local partyProgress = QPS.Tooltip.GetPartyProgress(relatedQuest)
    if not partyProgress or not next(partyProgress) then
        return
    end
    
    -- Always use GameTooltip integration for world tooltips - unified approach for all addon combinations
    local tooltip = GameTooltip
    LogDebugMessage(QPS_EventDebugLog, "[QPS-DEBUG] ShowWorldTooltipPartyProgress: Using GameTooltip integration")
    
    -- Check if we've already added party progress to this tooltip
    if not tooltip.QPS_PartyProgressAdded then
        -- Add party progress to existing GameTooltip (may be styled by pfUI/pfQuest)
        tooltip:AddLine(" ") -- Spacer
        tooltip:AddLine("|cffb48affParty Progress:|r")
        tooltip.QPS_PartyProgressAdded = true
    else
        -- Party progress already added, skip
        return
    end
    
    for member, progress in pairs(partyProgress) do
        AddWorldTooltipMemberProgress(tooltip, member, progress, entityName)
    end
    
    tooltip:Show()
end

-- Hook into world tooltips for mobs and objects using unified GameTooltip integration
if not QPS._worldTooltipHooked then
    -- Always hook GameTooltip OnShow for world objects/mobs
    -- Uses unified display logic with helper functions for consistent behavior
    local originalOnShow = GameTooltip:GetScript("OnShow")
    GameTooltip:SetScript("OnShow", function()
        -- Call original handler first (this may include pfUI styling)
        if originalOnShow then
            originalOnShow()
        end
        
        -- Skip if this is a pfQuest node or quest timer
        local focus = GetMouseFocus()
        if focus and focus.title then return end
        if focus and focus.GetName and StringLib.Sub((focus:GetName() or ""),0,10) == "QuestTimer" then return end
        
        -- Get the entity name from the tooltip
        local entityName = getglobal("GameTooltipTextLeft1") and getglobal("GameTooltipTextLeft1"):GetText() or nil
        if entityName then
            -- Remove color codes
            entityName = StringLib.Gsub(entityName, "|c%x%x%x%x%x%x%x%x", "")
            entityName = StringLib.Gsub(entityName, "|r", "")
            
            LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] World tooltip hook: Using GameTooltip for entity '" .. tostring(entityName) .. "', pfQuest enabled: " .. tostring(IsPfQuestEnabled()))
            ShowWorldTooltipPartyProgress(entityName)
        end
    end)
    
    -- Hook GameTooltip OnHide to hide our PartyTooltip when the main tooltip disappears
    local originalOnHide = GameTooltip:GetScript("OnHide")
    GameTooltip:SetScript("OnHide", function()
        -- Call original handler first
        if originalOnHide then
            originalOnHide()
        end
        
        -- Hide our PartyTooltip when GameTooltip hides
        HidePartyProgressTooltip()
        LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] GameTooltip OnHide: Hiding PartyTooltip")
    end)
    
    -- Only hook pfQuest tooltip if pfQuest is actually enabled (not just pfUI)
    local function TryHookPfQuestTooltip()
        if IsPfQuestEnabled() and pfMap and pfMap.tooltip then
            local originalPfShow = pfMap.tooltip:GetScript("OnShow")
            pfMap.tooltip:SetScript("OnShow", function()
                -- Call original handler first
                if originalPfShow then
                    originalPfShow()
                end
                
                -- Skip if this is a pfQuest node or quest timer
                local focus = GetMouseFocus()
                if focus and focus.title then return end
                if focus and focus.GetName and StringLib.Sub((focus:GetName() or ""),0,10) == "QuestTimer" then return end
                
                -- Get the entity name from the tooltip
                local entityName = getglobal("pfQuestTooltipTextLeft1") and getglobal("pfQuestTooltipTextLeft1"):GetText() or 
                                   getglobal("GameTooltipTextLeft1") and getglobal("GameTooltipTextLeft1"):GetText() or nil
                if entityName then
                    -- Remove color codes
                    entityName = StringLib.Gsub(entityName, "|c%x%x%x%x%x%x%x%x", "")
                    entityName = StringLib.Gsub(entityName, "|r", "")
                    
                    ShowWorldTooltipPartyProgress(entityName)
                end
            end)
            
            -- Also hook pfQuest tooltip OnHide to clean up party progress flags
            local originalPfHide = pfMap.tooltip:GetScript("OnHide")
            pfMap.tooltip:SetScript("OnHide", function()
                -- Call original handler first
                if originalPfHide then
                    originalPfHide()
                end
                
                -- Clear party progress flags when pfQuest tooltip hides
                if GameTooltip then
                    GameTooltip.QPS_PartyProgressAdded = nil
                end
                LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] pfQuest tooltip OnHide: Cleared party progress flags")
            end)
            
            LogDebugMessage(QPS_DebugLog, "[QPS-INFO] Successfully hooked pfQuest world tooltip system")
            return true
        else
            LogDebugMessage(QPS_DebugLog, "[QPS-DEBUG] Skipping pfQuest tooltip hook - pfQuest not enabled or pfMap.tooltip not available")
            return false
        end
    end
    
    -- Only try to hook pfQuest tooltip if pfQuest is actually enabled
    if IsPfQuestEnabled() then
        if not TryHookPfQuestTooltip() then
            local retryFrame = CreateFrame("Frame")
            retryFrame._qps_lastRetry = time()
            retryFrame:SetScript("OnUpdate", function()
                local now = time()
                if (now - retryFrame._qps_lastRetry) >= 2 then
                    if TryHookPfQuestTooltip() then
                        retryFrame:SetScript("OnUpdate", nil)
                    else
                        retryFrame._qps_lastRetry = now
                    end
                end
            end)
        end
    else
        LogDebugMessage(QPS_DebugLog, "[QPS-INFO] Skipping pfQuest tooltip hook setup - pfQuest not enabled")
    end
    
    QPS._worldTooltipHooked = true
    LogDebugMessage(QPS_DebugLog, "[QPS-INFO] Successfully hooked world tooltip systems - unified GameTooltip integration with helper functions")
end