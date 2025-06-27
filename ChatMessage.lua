-- ChatMessage.lua: Handles sending quest progress and completion messages to chat, party, and addon channels for QuestProgressShare.
-- Provides message formatting, coloring, and robust party/addon communication logic.

local QPS = QuestProgressShare
QPS.chatMessage = {}

-- Sends a quest progress message to chat, party, and/or addon channels based on config.
function QPS.chatMessage.Send(title, text, finished, objectiveIndex, objectiveFinished)
    LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] QPS.chatMessage.Send called: title=" .. tostring(title) .. ", text=" .. tostring(text) .. ", finished=" .. tostring(finished) .. ", objectiveIndex=" .. tostring(objectiveIndex) .. ", objectiveFinished=" .. tostring(objectiveFinished))
    if QuestProgressShareConfig then
        LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] sendSelf=" .. tostring(QuestProgressShareConfig.sendSelf) .. ", sendPublic=" .. tostring(QuestProgressShareConfig.sendPublic) .. ", sendInParty=" .. tostring(QuestProgressShareConfig.sendInParty))
    else
        LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] QuestProgressShareConfig is nil!")
    end

    local message = title .. " - " .. text

    -- Determine color: green if objective is complete or over-complete, red otherwise
    local isObjectiveComplete = false
    if objectiveFinished == true then
        isObjectiveComplete = true
    else
        local current, required = StringLib.SafeExtractNumbers(text or "")
        if current and required then
            current = tonumber(current)
            required = tonumber(required)
            if current and required and current >= required then
                isObjectiveComplete = true
            end
        end
        -- If finished is true (whole quest complete), always green
        if finished then isObjectiveComplete = true end
    end

    -- Send the message to the default chatframe
    if (QuestProgressShareConfig.sendSelf) then
        if isObjectiveComplete then
            DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. message, 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. message, 1, 0, 0)
        end
    end

    -- Color the message green if the objective is complete/over-complete, red otherwise
    if isObjectiveComplete then
        message = "|cff00ff00" .. message .. "|r"
    else
        message = "|cffff0000" .. message .. "|r"
    end

    -- Send the message to the public chat
    if (QuestProgressShareConfig.sendPublic) then
        ChatThrottleLib:SendChatMessage("NORMAL", "QPS", message, "SAY")
    end
    
    -- Send the message to the party chat
    if (QuestProgressShareConfig.sendInParty == 1 and GetNumPartyMembers() > 0) then
        ChatThrottleLib:SendChatMessage("NORMAL", "QPS", message, "PARTY")
    end
end

-- Sends a quest progress message with a clickable link to chat, party, and/or addon channels based on config.
function QPS.chatMessage.SendLink(title, text, finished, objectiveIndex, objectiveFinished)
    LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] QPS.chatMessage.SendLink called: title=" .. tostring(title) .. ", text=" .. tostring(text) .. ", finished=" .. tostring(finished) .. ", objectiveIndex=" .. tostring(objectiveIndex) .. ", objectiveFinished=" .. tostring(objectiveFinished))
    if not QuestProgressShareConfig or QuestProgressShareConfig.enabled ~= 1 then
        LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] SendLink: config missing or disabled! enabled=" .. tostring(QuestProgressShareConfig and QuestProgressShareConfig.enabled))
        return
    end
    LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] sendSelf=" .. tostring(QuestProgressShareConfig.sendSelf) .. ", sendPublic=" .. tostring(QuestProgressShareConfig.sendPublic) .. ", sendInParty=" .. tostring(QuestProgressShareConfig.sendInParty))

    local message
    local isObjectiveComplete = false
    if objectiveFinished == true then
        isObjectiveComplete = true
    else
        local current, required = StringLib.SafeExtractNumbers(text or "")
        if current and required then
            current = tonumber(current)
            required = tonumber(required)
            if current and required and current >= required then
                isObjectiveComplete = true
            end
        end
        if finished then isObjectiveComplete = true end
    end

    if text and text ~= "" then
        if isObjectiveComplete then
            message = title .. " |cff00ff00- " .. text .. "|r"
        else
            message = title .. " |cffff0000- " .. text .. "|r"
        end
    else
        message = title
    end

    -- Send the message to the default chatframe
    if (QuestProgressShareConfig.sendSelf) then
        DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. message)
    end
    -- Send the message to the public chat
    if (QuestProgressShareConfig.sendPublic) then
        ChatThrottleLib:SendChatMessage("NORMAL", "QPS", message, "SAY")
    end
    -- Send the message to the party chat
    if (QuestProgressShareConfig.sendInParty == 1 and GetNumPartyMembers() > 0) then
        ChatThrottleLib:SendChatMessage("NORMAL", "QPS", message, "PARTY")
    end
end