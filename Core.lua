-- Reference to main addon table
local QPS = QuestProgressShare
-- Core.lua - Main logic for QuestProgressShare

QPS.suppressQuestLogUpdate = false -- prevent recursive or premature quest log updates
local lastProgress = {} -- last known progress for each quest objective
local completedQuestTitle = nil -- quest being turned in (for completion detection)
local delayedQuestScanPending = false -- is a delayed scan scheduled
local delayedQuestScanFrame = CreateFrame("Frame") -- frame for delayed quest log scan
local firstProgressScan = true -- is this the first scan after login/reload
local getQuestIDs = pfDatabase and pfDatabase.GetQuestIDs -- Reference to pfQuest's GetQuestIDs function if available
local pfDB = pfDB -- Reference to pfQuest's database table if available

delayedQuestScanFrame:Hide()

-- Schedules a delayed scan of the quest log, used to handle header state issues
local function DelayedQuestLogScan()
    delayedQuestScanFrame:Hide()
    delayedQuestScanPending = false
    OnEvent("QUEST_LOG_UPDATE")
end

-- OnUpdate handler for the delayed quest scan frame
local function DelayedQuestScanOnUpdate()
    delayedQuestScanFrame.elapsed = (delayedQuestScanFrame.elapsed or 0) + arg1
    if delayedQuestScanFrame.elapsed >= 0.3 then
        delayedQuestScanFrame.elapsed = 0
        DelayedQuestLogScan()
    end
end

delayedQuestScanFrame:SetScript("OnUpdate", DelayedQuestScanOnUpdate)

-- Returns a clickable quest link for chat, using pfQuest data if available
local function GetClickableQuestLink(questID, title)
    local qid = tostring(questID)
    local qid_num = tonumber(questID)
    local locale = GetLocale and GetLocale() or "enUS"
    local pfquests = pfDB and pfDB["quests"]
    local pfdbs = {
        { data = pfquests and pfquests["data"], loc = pfquests and pfquests["loc"] }, -- pfQuest legacy
        { data = pfquests and pfquests["data-turtle"], loc = pfquests and pfquests[locale.."-turtle"] }, -- pfQuest-turtle
        { data = pfquests and pfquests["data"], loc = pfquests and pfquests[locale] } -- pfQuest modern locale
    }
    local foundData, foundLoc, foundType
    for i, db in ipairs(pfdbs) do
        if db.data and db.loc then
            local data = db.data[qid] or (qid_num and db.data[qid_num])
            local loc = db.loc[qid] or (qid_num and db.loc[qid_num])
            if data or loc then
                foundData, foundLoc = data, loc
                foundType = (i == 1 and "pfQuest-loc") or (i == 2 and "pfQuest-turtle") or (i == 3 and "pfQuest-locale")
                break
            end
        end
    end
    local link
    if foundData or foundLoc then
        local level = foundData and foundData["lvl"] or 0
        local name = foundLoc and foundLoc["T"] or (foundData and foundData["T"] or ("Quest "..qid))
        local hex = "|cffffff00"
        if pfUI and pfUI.api and pfUI.api.rgbhex and pfQuestCompat and pfQuestCompat.GetDifficultyColor then
            hex = pfUI.api.rgbhex(pfQuestCompat.GetDifficultyColor(level))
        end
        link = hex .. "|Hquest:"..qid..":"..level.."|h["..name.."]|h|r"
    elseif questID and tonumber(questID) then
        local safeTitle = (type(title) == "string" and title) or ("Quest "..tostring(questID))
        local cleanTitle = StringLib.Gsub(safeTitle, "|", "")
        local hex = "|cffffff00"
        if pfUI and pfUI.api and pfUI.api.rgbhex and pfQuestCompat and pfQuestCompat.GetDifficultyColor then
            hex = pfUI.api.rgbhex(pfQuestCompat.GetDifficultyColor(0))
        end
        link = hex .. "|Hquest:"..tostring(questID)..":0|h["..cleanTitle.."]|h|r"
    elseif type(title) == "string" and StringLib.Sub(title, 1, 8) == "|Hquest:" then
        if StringLib.Sub(title, 1, 10) ~= "|cffffff00" then
            link = "|cffffff00" .. title .. "|r"
        else
            link = title
        end
    elseif type(title) == "string" then
        local safeTitle = StringLib.Gsub(title, "|", "")
        link = "[" .. safeTitle .. "]"
    else
        link = qid
    end
    if type(link) == "string" and StringLib.Sub(link, 1, 8) == "|Hquest:" then
        if StringLib.Sub(link, 1, 10) ~= "|cffffff00" then
            link = "|cffffff00" .. link .. "|r"
        end
    end
    return link
end

-- Checks if a quest log index is valid and points to a real quest
local function IsValidQuestLogIndex(index)
    if type(index) ~= "number" or index < 1 or index > GetNumQuestLogEntries() then return false end
    local title, _, _, isHeader = GetQuestLogTitle(index)
    return (not isHeader) and title and title ~= ""
end

-- Cache for SafeGetQuestIDs results per scan
local questIDCache = {} -- [questLogIndex] = {questIDs}

-- Safely retrieves quest IDs using pfQuest, with fallback and caching
local function SafeGetQuestIDs(index, title)
    if questIDCache[index] ~= nil then
        return questIDCache[index]
    end
    if not IsValidQuestLogIndex(index) then
        questIDCache[index] = nil
        return nil
    end
    if getQuestIDs then
        local ok, ids = pcall(getQuestIDs, index)
        if ok and ids and ids[1] then
            questIDCache[index] = ids
            return ids
        else
            local logTitle = GetQuestLogTitle(index)
            if title and logTitle and logTitle == title and pfDB and pfDB["quests"] and pfDB["quests"]["loc"] then
                for id, data in pairs(pfDB["quests"]["loc"]) do
                    if data.T == title then
                        questIDCache[index] = { tonumber(id) }
                        return questIDCache[index]
                    end
                end
            end
        end
    end
    questIDCache[index] = nil
    return nil
end

-- Scans the quest log and updates lastProgress without sending messages
local function DummyQuestProgressScan()
    for questIndex = 1, GetNumQuestLogEntries() do
        local title, _, _, isHeader, _, _, isComplete = GetQuestLogTitle(questIndex)
        if not isHeader and title and IsValidQuestLogIndex(questIndex) then
            if pfDB then
                local ids = SafeGetQuestIDs(questIndex, title)
                local questID = ids and ids[1] and tonumber(ids[1])
                if questID then
                    SelectQuestLogEntry(questIndex)
                end
            else
                SelectQuestLogEntry(questIndex)
            end
            local objectives = GetNumQuestLeaderBoards()
            -- Handle turn-in only quests (no objectives)
            if objectives == 0 and isComplete then
                local questKey = title .. "-COMPLETE"
                lastProgress[questKey] = "Quest completed"
            end
            for i = 1, objectives do
                local text = GetQuestLogLeaderBoard(i)
                local questKey = title .. "-" .. i
                lastProgress[questKey] = text
            end
            if objectives > 0 then
                local questKey = title .. "-COMPLETE"
                if isComplete then
                    lastProgress[questKey] = "Quest completed"
                end
            end
        end
    end
end

-- Extracts the quest title from a progress key string
local function ExtractQuestTitleFromKey(key)
    local len = StringLib.Len(key)
    for i = 1, len do
        if StringLib.Sub(key, i, i) == "-" then
            return StringLib.Sub(key, 1, i - 1)
        end
    end
    return nil
end

-- Finds a quest ID by its title using pfQuest DB
local function FindQuestIDByTitle(title)
    if pfDB and pfDB.quests and pfDB.quests.loc then
        for id, data in pairs(pfDB.quests.loc) do
            if data.T == title then
                return tonumber(id)
            end
        end
    end
    return nil
end

-- Sends a quest progress or completion message, using clickable links if possible
local function SendQuestMessage(title, text, finished, questIndex)
    local questID = nil
    if pfDB then
        if questIndex then
            local ids = SafeGetQuestIDs(questIndex, title)
            if ids and ids[1] then
                questID = ids[1]
                -- Double-check: only send if the quest title for this questIndex matches pfQuest DB for this questID
                local pfTitle = nil
                if pfDB.quests and pfDB.quests.loc and pfDB.quests.loc[tostring(questID)] then
                    pfTitle = pfDB.quests.loc[tostring(questID)].T
                end
                local logTitle = GetQuestLogTitle(questIndex)
                if pfTitle and logTitle and pfTitle ~= logTitle then
                    -- Mismatch: do not send
                    return
                end
            else
                questID = FindQuestIDByTitle(title)
            end
        else
            questID = FindQuestIDByTitle(title)
        end
    elseif getQuestIDs then
        local ids = getQuestIDs(title)
        if ids and ids[1] then questID = ids[1] end
    end
    if pfDB and questID then
        local link = GetClickableQuestLink(questID, title)
        -- Accept any link containing |Hquest: as a clickable quest link
        if link and type(link) == "string" and StringLib.Find(link, "|Hquest:") then
            QPS.chatMessage.SendLink(link, text, finished)
            return
        end
    end
    QPS.chatMessage.Send(title, text, finished)
end

-- Returns true if this is the first time the addon has ever loaded for this character
local function IsFirstLoadEver()
    return QPS_SavedLoadCount == 1
end

-- Main event handler for all registered events
function OnEvent()
    -- Handles quest completion (quest turn-in window opened)
    if event == "QUEST_COMPLETE" then
        if GetTitleText then
            completedQuestTitle = GetTitleText()
        end
        return

    -- Handles player login: initializes known quests and prints loaded message
    elseif event == "PLAYER_LOGIN" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffb48affQuestProgressShare|r loaded.")
        end
        if pfDB then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffb48affQuestProgressShare: pfQuest integration enabled!|r")
            end
        end

        -- Initialize known quests from SavedVariables
        if not QPS_SavedKnownQuests then QPS_SavedKnownQuests = {} end
        QPS.knownQuests = {}
        for k, v in pairs(QPS_SavedKnownQuests) do QPS.knownQuests[k] = v end

        -- Loads last progress from SavedVariables
        if not QPS_SavedProgress then QPS_SavedProgress = {} end
        for k, v in pairs(QPS_SavedProgress) do lastProgress[k] = v end
        firstProgressScan = true

        -- Robust load count increment: only increment after login, and print for debugging
        if QPS_SavedLoadCount == nil then QPS_SavedLoadCount = 0 end
        QPS_SavedLoadCount = QPS_SavedLoadCount + 1

        -- If first load ever, do a dummy scan and update saved variables, but do not send messages
        QPS._didFirstLoadInit = false
        if IsFirstLoadEver() then
            QPS._didFirstLoadInit = true
        end
        return

    -- Handles addon load: sets default config and updates config UI
    elseif event == "ADDON_LOADED" and arg1 == "QuestProgressShare" then
        QPS.config.SetDefaultConfigValues()
        UpdateConfigFrame()
        return

    -- Handles entering world: delays quest log scanning until fully loaded
    elseif event == "PLAYER_ENTERING_WORLD" then
        QPS.ready = false
        if not QPS.delayFrame then
            QPS.delayFrame = CreateFrame("Frame")
        end
        QPS.delayFrame.elapsed = 0
        QPS.delayFrame.startTime = time()
        QPS.delayFrame:SetScript("OnUpdate", function()
            local now = time()
            if (now - QPS.delayFrame.startTime) >= 3 then
                QPS.ready = true
                QPS.delayFrame:SetScript("OnUpdate", nil)

                -- If first load ever, do a dummy scan and update saved variables, but do not send messages
                if QPS._didFirstLoadInit then
                    DummyQuestProgressScan()

                    -- Save lastProgress to SavedVariables (clear old data first)
                    if QPS_SavedProgress then
                        for k in pairs(QPS_SavedProgress) do QPS_SavedProgress[k] = nil end
                    else
                        QPS_SavedProgress = {}
                    end
                    for k, v in pairs(lastProgress) do
                        QPS_SavedProgress[k] = v
                    end

                    -- Also update known quests
                    for questIndex = 1, GetNumQuestLogEntries() do
                        local title, _, _, isHeader = GetQuestLogTitle(questIndex)
                        if not isHeader and title then
                            QPS.knownQuests[title] = true
                        end
                    end

                    if QPS_SavedKnownQuests then
                        for k in pairs(QPS_SavedKnownQuests) do QPS_SavedKnownQuests[k] = nil end
                    else
                        QPS_SavedKnownQuests = {}
                    end
                    for k, v in pairs(QPS.knownQuests) do
                        QPS_SavedKnownQuests[k] = v
                    end

                    -- Mark first-load initialization as complete
                    QPS._didFirstLoadInit = false
                else
                    DummyQuestProgressScan() -- Populates lastProgress for any new quests
                end
            end
        end)
        return

    -- Handles quest log updates: detects quest accept, completion, and progress
    elseif event == "QUEST_LOG_UPDATE" and QuestProgressShareConfig.enabled then
        -- Prevent recursive or premature updates
        if QPS.suppressQuestLogUpdate then return end
        if not QPS.ready then return end
        if not QPS.knownQuests then QPS.knownQuests = {} end

        -- Save header (category) states and expand all for scanning
        local numEntries = GetNumQuestLogEntries()
        local headerStates = {} -- stores header collapsed state
        QPS.suppressQuestLogUpdate = true
        for i = 1, numEntries do
            local title, _, _, isHeader, isCollapsed = GetQuestLogTitle(i)
            if isHeader then
                headerStates[i] = isCollapsed
                if isCollapsed then
                    ExpandQuestHeader(i)
                end
            end
        end
        QPS.suppressQuestLogUpdate = false

        -- Track quests that were in the previous log BEFORE updating knownQuests
        local previousQuests = {} -- previous quest titles
        local previousCount = 0
        for k, v in pairs(QPS.knownQuests or {}) do
            previousQuests[k] = v
            previousCount = previousCount + 1
        end

        local currentQuests = {} -- current quest titles
        local currentCount = 0
        local foundNewQuest = false

        -- Scan current quest log and detect new quests
        for questIndex = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader = GetQuestLogTitle(questIndex)
            if not isHeader and title then
                currentQuests[title] = true
                currentCount = currentCount + 1
                if not previousQuests[title] then
                    foundNewQuest = true
                    SendQuestMessage(title, "Quest accepted", false)
                end
            end
        end

        -- If a new quest is expected but not found (likely due to collapsed headers), schedule a delayed rescan
        if previousCount < currentCount and not foundNewQuest and not delayedQuestScanPending then
            delayedQuestScanPending = true
            delayedQuestScanFrame.time = 0
            delayedQuestScanFrame:Show()
        end

        -- Check for removed quests that were just completed (not abandoned)
        for prevTitle in pairs(QPS.knownQuests or {}) do
            if not currentQuests[prevTitle] then
                if completedQuestTitle == prevTitle then
                    local questKey = prevTitle .. "-COMPLETE"
                    if lastProgress[questKey] ~= "Quest completed" then
                        lastProgress[questKey] = "Quest completed"
                        SendQuestMessage(prevTitle, "Quest completed", true)
                    end
                    completedQuestTitle = nil
                end
            end
        end

        QPS.knownQuests = currentQuests

        -- Update the SavedVariable table in-place
        if QPS_SavedKnownQuests then
            for k in pairs(QPS_SavedKnownQuests) do QPS_SavedKnownQuests[k] = nil end
        else
            QPS_SavedKnownQuests = {}
        end
        for k, v in pairs(currentQuests) do QPS_SavedKnownQuests[k] = v end

        -- Iterate through the quest log entries and announce progress/completion
        if pfDB then
            -- pfQuest enabled: only call SelectQuestLogEntry if we have a valid questID and valid index
            for questIndex = 1, GetNumQuestLogEntries() do
                local title, _, _, isHeader, _, _, isComplete = GetQuestLogTitle(questIndex)
                if not isHeader and title and IsValidQuestLogIndex(questIndex) then
                    local ids = SafeGetQuestIDs(questIndex, title)
                    local questID = ids and ids[1] and tonumber(ids[1])
                    if questID then
                        SelectQuestLogEntry(questIndex)
                    end
                    local objectives = GetNumQuestLeaderBoards()
                    -- Handle turn-in only quests (no objectives)
                    if objectives == 0 and isComplete then
                        local questKey = title .. "-COMPLETE"
                        if lastProgress[questKey] ~= "Quest completed" then
                            lastProgress[questKey] = "Quest completed"
                            SendQuestMessage(title, "Quest completed", true, questIndex)
                        end
                    end
                    local completedObjectives = 0
                    local totalObjectives = objectives
                    -- Check each quest objective for progress
                    for i = 1, objectives do
                        local text, objType, finished = GetQuestLogLeaderBoard(i)
                        local questKey = title .. "-" .. i
                        local isMeaningless = false
                        if type(text) ~= "string" then
                            isMeaningless = true
                        else
                            local current, total = StringLib.SafeExtractNumbers(text, QPS_Debug)
                            if not current or tonumber(current) == 0 then
                                isMeaningless = true
                            end
                        end
                        if isComplete then
                            if lastProgress[questKey] ~= "Quest completed" then
                                lastProgress[questKey] = "Quest completed"
                            end
                        else
                            if (lastProgress[questKey] == nil or lastProgress[questKey] == "") then
                                if not isMeaningless and (QuestProgressShareConfig.sendStartingQuests or (type(text) == "string" and StringLib.Sub(text, 1, 3) ~= " : ")) then
                                    lastProgress[questKey] = text
                                    -- Only send if not first scan, or if changed since last session
                                    if (not firstProgressScan) or (QPS_SavedProgress[questKey] ~= text) then
                                        if (finished or not QuestProgressShareConfig.sendOnlyFinished) and (not completedQuestTitle or completedQuestTitle ~= title) then
                                            SendQuestMessage(title, text, finished, questIndex)
                                        end
                                    end
                                end
                            elseif lastProgress[questKey] ~= text then
                                lastProgress[questKey] = text
                                if not isMeaningless and (finished or not QuestProgressShareConfig.sendOnlyFinished) and (not completedQuestTitle or completedQuestTitle ~= title) then
                                    SendQuestMessage(title, text, finished, questIndex)
                                end
                            end
                        end
                        if finished then completedObjectives = completedObjectives + 1 end
                    end
                    -- Send 'Quest completed' for all quest types (with or without objectives)
                    if objectives > 0 then
                        local questKey = title .. "-COMPLETE"
                        if isComplete and lastProgress[questKey] ~= "Quest completed" then
                            lastProgress[questKey] = "Quest completed"
                            SendQuestMessage(title, "Quest completed", true, questIndex)
                        end
                    end
                end
            end
        else
            -- pfQuest not enabled: original logic
            for questIndex = 1, GetNumQuestLogEntries() do
                local title, _, _, isHeader, _, _, isComplete = GetQuestLogTitle(questIndex)
                if not isHeader then
                    SelectQuestLogEntry(questIndex)
                    local objectives = GetNumQuestLeaderBoards()
                    -- Handle turn-in only quests (no objectives)
                    if objectives == 0 and isComplete then
                        local questKey = title .. "-COMPLETE"
                        if lastProgress[questKey] ~= "Quest completed" then
                            lastProgress[questKey] = "Quest completed"
                            SendQuestMessage(title, "Quest completed", true)
                        end
                    end
                    local completedObjectives = 0
                    local totalObjectives = objectives
                    -- Check each quest objective for progress
                    for i = 1, objectives do
                        local text, objType, finished = GetQuestLogLeaderBoard(i)
                        local questKey = title .. "-" .. i
                        local isMeaningless = false
                        if type(text) ~= "string" then
                            isMeaningless = true
                        else
                            local current, total = StringLib.SafeExtractNumbers(text, QPS_Debug)
                            if not current or tonumber(current) == 0 then
                                isMeaningless = true
                            end
                        end
                        if isComplete then
                            if lastProgress[questKey] ~= "Quest completed" then
                                lastProgress[questKey] = "Quest completed"
                            end
                        else
                            if (lastProgress[questKey] == nil or lastProgress[questKey] == "") then
                                if not isMeaningless and (QuestProgressShareConfig.sendStartingQuests or (type(text) == "string" and StringLib.Sub(text, 1, 3) ~= " : ")) then
                                    lastProgress[questKey] = text
                                    -- Only send if not first scan, or if changed since last session
                                    if (not firstProgressScan) or (QPS_SavedProgress[questKey] ~= text) then
                                        if (finished or not QuestProgressShareConfig.sendOnlyFinished) and (not completedQuestTitle or completedQuestTitle ~= title) then
                                            SendQuestMessage(title, text, finished)
                                        end
                                    end
                                end
                            elseif lastProgress[questKey] ~= text then
                                lastProgress[questKey] = text
                                if not isMeaningless and (finished or not QuestProgressShareConfig.sendOnlyFinished) and (not completedQuestTitle or completedQuestTitle ~= title) then
                                    SendQuestMessage(title, text, finished)
                                end
                            end
                        end
                        if finished then completedObjectives = completedObjectives + 1 end
                    end
                    -- Send 'Quest completed' for all quest types (with or without objectives)
                    if objectives > 0 then
                        local questKey = title .. "-COMPLETE"
                        if isComplete and lastProgress[questKey] ~= "Quest completed" then
                            lastProgress[questKey] = "Quest completed"
                            SendQuestMessage(title, "Quest completed", true)
                        end
                    end
                end
            end
        end

        -- Save lastProgress to SavedVariables and clean up progress for quests no longer in the log
        local activeQuestTitles = {}
        for questIndex = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader = GetQuestLogTitle(questIndex)
            if not isHeader and title then
                activeQuestTitles[title] = true
            end
        end

        for k in pairs(lastProgress) do
            local questTitle = ExtractQuestTitleFromKey(k)
            if questTitle and not activeQuestTitles[questTitle] then
                lastProgress[k] = nil
            end
        end

        if QPS_SavedProgress then
            for k in pairs(QPS_SavedProgress) do QPS_SavedProgress[k] = nil end
        else
            QPS_SavedProgress = {}
        end
        for k, v in pairs(lastProgress) do QPS_SavedProgress[k] = v end

        -- After first scan, set flag to false
        if firstProgressScan then firstProgressScan = false end

        -- Restores header (category) collapsed states
        QPS.suppressQuestLogUpdate = true
        for i = 1, numEntries do
            if headerStates[i] then CollapseQuestHeader(i) end
        end
        QPS.suppressQuestLogUpdate = false

    end
end

-- Registers for all relevant quest and addon events
QPS:RegisterEvent("QUEST_LOG_UPDATE")
QPS:RegisterEvent("PLAYER_LOGIN")
QPS:RegisterEvent("ADDON_LOADED")
QPS:RegisterEvent("PLAYER_ENTERING_WORLD")
QPS:RegisterEvent("QUEST_COMPLETE")
QPS:SetScript("OnEvent", OnEvent)

