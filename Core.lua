-- Core.lua - Main logic for QuestProgressShare

local QPS = QuestProgressShare -- main addon table

QPS.suppressQuestLogUpdate = false -- prevent recursive or premature quest log updates

local lastProgress = {} -- last known progress for each quest objective
local completedQuestTitle = nil -- quest being turned in (for completion detection)
local delayedQuestScanPending = false -- is a delayed scan scheduled
local delayedQuestScanFrame = CreateFrame("Frame") -- frame for delayed quest log scan
local firstProgressScan = true -- is this the first scan after login/reload

delayedQuestScanFrame:Hide()

-- Triggers a delayed scan of the quest log (used when headers may be collapsed)
local function DelayedQuestLogScan()
    delayedQuestScanFrame:Hide()
    delayedQuestScanPending = false
    OnEvent("QUEST_LOG_UPDATE")
end

-- OnUpdate handler for delayed quest log scan
local function DelayedQuestScanOnUpdate()
    delayedQuestScanFrame.elapsed = (delayedQuestScanFrame.elapsed or 0) + arg1
    if delayedQuestScanFrame.elapsed >= 0.3 then
        delayedQuestScanFrame.elapsed = 0
        DelayedQuestLogScan()
    end
end

delayedQuestScanFrame:SetScript("OnUpdate", DelayedQuestScanOnUpdate)

-- Dummy scan to populate lastProgress without sending messages
local function DummyQuestProgressScan()
    for questIndex = 1, GetNumQuestLogEntries() do
        local title, _, _, isHeader, _, _, isComplete = GetQuestLogTitle(questIndex)
        if not isHeader then
            SelectQuestLogEntry(questIndex)
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

-- Helper to extract quest title from progress key using StringLib
local function ExtractQuestTitleFromKey(key)
    local len = StringLib.Len(key)
    for i = 1, len do
        if StringLib.Sub(key, i, i) == "-" then
            return StringLib.Sub(key, 1, i - 1)
        end
    end
    return nil
end

-- Handles quest progress tracking and event logic
function OnEvent()
    -- Handles quest completion (quest turn-in window opened)
    if event == "QUEST_COMPLETE" then
        if GetTitleText then
            completedQuestTitle = GetTitleText()
        end
        return

    -- Handles player login: initializes known quests and prints loaded message
    elseif event == "PLAYER_LOGIN" then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffb48affQuestProgressShare|r loaded.") end
        if not QPS_SavedKnownQuests then QPS_SavedKnownQuests = {} end
        QPS.knownQuests = {}
        for k, v in pairs(QPS_SavedKnownQuests) do QPS.knownQuests[k] = v end
        -- Loads last progress from SavedVariables
        if not QPS_SavedProgress then QPS_SavedProgress = {} end
        for k, v in pairs(QPS_SavedProgress) do lastProgress[k] = v end
        firstProgressScan = true
        DummyQuestProgressScan() -- Populates lastProgress for any new quests
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
                    QPS.chatMessage.Send(title, "Quest accepted", false)
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
                        QPS.chatMessage.Send(prevTitle, "Quest completed", true)
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
                        QPS.chatMessage.Send(title, "Quest completed", true)
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
                                        QPS.chatMessage.Send(title, text, finished)
                                    end
                                end
                            end
                        elseif lastProgress[questKey] ~= text then
                            lastProgress[questKey] = text
                            if not isMeaningless and (finished or not QuestProgressShareConfig.sendOnlyFinished) and (not completedQuestTitle or completedQuestTitle ~= title) then
                                QPS.chatMessage.Send(title, text, finished)
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
                        QPS.chatMessage.Send(title, "Quest completed", true)
                    end
                end
            end
        end

        -- Save lastProgress to SavedVariables after each scan
        -- Clean up progress for quests no longer in the log
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