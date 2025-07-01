-- ChatMessage.lua: Handles sending quest progress and completion messages to chat, party, and addon channels for QuestProgressShare.
-- Provides message formatting, coloring, and robust party/addon communication logic.

local QPS = QuestProgressShare
QPS.chatMessage = {}

-- Helper function to determine if an objective is complete
local function IsObjectiveComplete(text, finished, objectiveFinished)
    if objectiveFinished == true then
        return true
    end
    
    local current, required = StringLib.SafeExtractNumbers(text or "")
    if current and required then
        current = tonumber(current)
        required = tonumber(required)
        if current and required and current >= required then
            return true
        end
    end
    
    -- If finished is true (whole quest complete), always complete
    if finished then 
        return true 
    end
    
    return false
end

-- Sends a quest progress message to chat, party, and/or addon channels based on config.
function QPS.chatMessage.Send(title, text, finished, objectiveIndex, objectiveFinished)
    LogVerboseDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] QPS.chatMessage.Send called: title=" .. tostring(title) .. ", text=" .. tostring(text) .. ", finished=" .. tostring(finished) .. ", objectiveIndex=" .. tostring(objectiveIndex) .. ", objectiveFinished=" .. tostring(objectiveFinished))
    if QuestProgressShareConfig then
        LogVerboseDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] sendSelf=" .. tostring(QuestProgressShareConfig.sendSelf) .. ", sendPublic=" .. tostring(QuestProgressShareConfig.sendPublic) .. ", sendInParty=" .. tostring(QuestProgressShareConfig.sendInParty))
    else
        LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] QuestProgressShareConfig is nil!")
    end

    local message = title .. " - " .. text

    -- Determine color using helper function
    local isObjectiveComplete = IsObjectiveComplete(text, finished, objectiveFinished)

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
    LogVerboseDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] QPS.chatMessage.SendLink called: title=" .. tostring(title) .. ", text=" .. tostring(text) .. ", finished=" .. tostring(finished) .. ", objectiveIndex=" .. tostring(objectiveIndex) .. ", objectiveFinished=" .. tostring(objectiveFinished))
    if not QuestProgressShareConfig or QuestProgressShareConfig.enabled ~= 1 then
        LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] SendLink: config missing or disabled! enabled=" .. tostring(QuestProgressShareConfig and QuestProgressShareConfig.enabled))
        return
    end
    LogVerboseDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] sendSelf=" .. tostring(QuestProgressShareConfig.sendSelf) .. ", sendPublic=" .. tostring(QuestProgressShareConfig.sendPublic) .. ", sendInParty=" .. tostring(QuestProgressShareConfig.sendInParty))

    local message
    local isObjectiveComplete = IsObjectiveComplete(text, finished, objectiveFinished)

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