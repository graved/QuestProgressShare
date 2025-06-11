local QPS = QuestProgressShare

-- Save the last quest progress to avoid double messages
local lastProgress = {}

-- Use WoW SavedVariables for known quests
-- In your QuestProgressShare.toc, add: QPS_SavedKnownQuests = {}

-- Event-Handler function
local completedQuestTitle = nil

function OnEvent()
    if event == "QUEST_COMPLETE" then
        -- The quest turn-in window is open, get the quest title
        if GetTitleText then
            completedQuestTitle = GetTitleText()
        end
        return
    elseif event == "PLAYER_LOGIN" then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffb48affQuestProgressShare|r loaded.") end
        if not QPS_SavedKnownQuests then QPS_SavedKnownQuests = {} end
        -- Always assign a new table for per-character variable to avoid reference issues
        QPS.knownQuests = {}
        for k, v in pairs(QPS_SavedKnownQuests) do QPS.knownQuests[k] = v end
        return
    elseif event == "ADDON_LOADED" and arg1 == "QuestProgressShare" then
        QPS.config.SetDefaultConfigValues()
        UpdateConfigFrame()
        return
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
    elseif event == "QUEST_LOG_UPDATE" and QuestProgressShareConfig.enabled then
        if not QPS.ready then return end
        if not QPS.knownQuests then QPS.knownQuests = {} end
        -- Track quests that were in the previous log BEFORE updating knownQuests
        local previousQuests = {}
        for k, v in pairs(QPS.knownQuests or {}) do previousQuests[k] = v end
        local currentQuests = {}
        for questIndex = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader = GetQuestLogTitle(questIndex)
            if not isHeader and title then
                currentQuests[title] = true
                if not QPS.knownQuests[title] then
                    QPS.chatMessage.Send(title, "Quest accepted", false)
                end
            end
        end
        -- After processing all current quests, check for removed quests that were complete
        for prevTitle in pairs(QPS.knownQuests or {}) do
            if not currentQuests[prevTitle] then
                -- Only send 'Quest completed' if this quest was just completed (not abandoned)
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
        -- Properly update the SavedVariable table in-place
        if QPS_SavedKnownQuests then
            for k in pairs(QPS_SavedKnownQuests) do QPS_SavedKnownQuests[k] = nil end
        else
            QPS_SavedKnownQuests = {}
        end
        for k, v in pairs(currentQuests) do QPS_SavedKnownQuests[k] = v end
        -- Iterate through the quest log entries
        for questIndex = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, _, isComplete = GetQuestLogTitle(questIndex)
            if not isHeader then
                local objectives = GetNumQuestLeaderBoards(questIndex)
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
                for i = 1, objectives do
                    local text, objType, finished = GetQuestLogLeaderBoard(i, questIndex)
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
    end
end

-- Register events
QPS:RegisterEvent("QUEST_LOG_UPDATE")
QPS:RegisterEvent("PLAYER_LOGIN")
QPS:RegisterEvent("ADDON_LOADED")
QPS:RegisterEvent("PLAYER_ENTERING_WORLD")
QPS:RegisterEvent("QUEST_COMPLETE")
QPS:SetScript("OnEvent", OnEvent)