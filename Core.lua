local QPS = QuestProgressShare

-- Save the last quest progress to avoid double messages
local lastProgress = {}

-- Event-Handler function
local function OnEvent(...)
    if event == "PLAYER_LOGIN" then
        DEFAULT_CHAT_FRAME:AddMessage("QuestProgressShare loaded")
    elseif event == "ADDON_LOADED" and arg1 == "QuestProgressShare" then
        QPS.config.SetDefaultConfigValues()
        UpdateConfigFrame()
    elseif event == "QUEST_LOG_UPDATE" and QuestProgressShareConfig.enabled then
        -- Iterate through the quest log entries
        for questIndex = 1, GetNumQuestLogEntries() do
            local title, _, _, isHeader, _, _, isComplete = GetQuestLogTitle(questIndex)

            -- Skip header entries
            if not isHeader then
                -- Get the quest progress
                local objectives = GetNumQuestLeaderBoards(questIndex)
                for i = 1, objectives do
                    local text, type, finished = GetQuestLogLeaderBoard(i, questIndex)

                    if finished then
                        text = text .. " (finished)"
                    end

                    -- Avoid double messages
                    local questKey = title .. "-" .. i

                    if lastProgress[questKey] == nil or lastProgress[questKey] == "" then
                        if text ~= "" and (QuestProgressShareConfig.sendStartingQuests or string.sub(text, 1, 3) ~= " : ") then
                            lastProgress[questKey] = text
                        end                        
                    elseif lastProgress[questKey] ~= text then
                        lastProgress[questKey] = text

                        local message = title .. " - " .. text                        
                        QPS.centerMessage.ShowMessage(message, 5)
                        QPS.chatMessage.Send(message, finished)                     
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
QPS:SetScript("OnEvent", OnEvent)
