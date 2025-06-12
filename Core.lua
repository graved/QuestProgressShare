local QPS = QuestProgressShare

-- Global state
QPS.suppressQuestLogUpdate = false

-- Local state
local lastProgress = {}
local completedQuestTitle = nil -- Stores the title of the quest being turned in
local delayedQuestScanPending = false -- Indicates if a delayed scan is scheduled
local delayedQuestScanFrame = CreateFrame("Frame")
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

-- Main event handler for all registered events
function OnEvent()
    -- Handle quest completion (quest turn-in window opened)
    if event == "QUEST_COMPLETE" then
        if GetTitleText then
            completedQuestTitle = GetTitleText()
        end
        return

    -- Handle player login: initialize known quests and print loaded message
    elseif event == "PLAYER_LOGIN" then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffb48affQuestProgressShare|r loaded.") end
        if not QPS_SavedKnownQuests then QPS_SavedKnownQuests = {} end
        -- Always assign a new table for per-character variable to avoid reference issues
        QPS.knownQuests = {}
        for k, v in pairs(QPS_SavedKnownQuests) do QPS.knownQuests[k] = v end
        return

    -- Handle addon load: set default config and update config UI
    elseif event == "ADDON_LOADED" and arg1 == "QuestProgressShare" then
        QPS.config.SetDefaultConfigValues()
        UpdateConfigFrame()
        return

    -- Handle entering world: delay quest log scanning until fully loaded
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
        
    -- Handle quest log updates: detect quest accept, completion, and progress
    elseif event == "QUEST_LOG_UPDATE" and QuestProgressShareConfig.enabled then
        -- Prevent recursive or premature updates
        if QPS.suppressQuestLogUpdate then return end
        if not QPS.ready then return end
        if not QPS.knownQuests then QPS.knownQuests = {} end

        -- Save header (category) states and expand all for scanning
        local numEntries = GetNumQuestLogEntries()
        local headerStates = {}
        QPS.suppressQuestLogUpdate = true
        for i = 1, numEntries do
            local title, _, _, isHeader, isCollapsed = GetQuestLogTitle(i)
            if isHeader then
                headerStates[i] = isCollapsed
                if isCollapsed then ExpandQuestHeader(i) end
            end
        end
        QPS.suppressQuestLogUpdate = false

        -- Track quests that were in the previous log BEFORE updating knownQuests
        local previousQuests = {}
        local previousCount = 0
        for k, v in pairs(QPS.knownQuests or {}) do
            previousQuests[k] = v
            previousCount = previousCount + 1
        end

        local currentQuests = {}
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
                        local current, total = string.match(text, "(%d+)%s*/%s*(%d+)")
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
                            if not isMeaningless and (QuestProgressShareConfig.sendStartingQuests or (type(text) == "string" and string.sub(text, 1, 3) ~= " : ")) then
                                lastProgress[questKey] = text
                                if (finished or not QuestProgressShareConfig.sendOnlyFinished) and (not completedQuestTitle or completedQuestTitle ~= title) then
                                    QPS.chatMessage.Send(title, text, finished)
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

        -- Restore header (category) collapsed states
        QPS.suppressQuestLogUpdate = true
        for i = 1, numEntries do
            if headerStates[i] then CollapseQuestHeader(i) end
        end
        QPS.suppressQuestLogUpdate = false
    end
end

-- Register for all relevant quest and addon events
QPS:RegisterEvent("QUEST_LOG_UPDATE")
QPS:RegisterEvent("PLAYER_LOGIN")
QPS:RegisterEvent("ADDON_LOADED")
QPS:RegisterEvent("PLAYER_ENTERING_WORLD")
QPS:RegisterEvent("QUEST_COMPLETE")
QPS:SetScript("OnEvent", OnEvent)