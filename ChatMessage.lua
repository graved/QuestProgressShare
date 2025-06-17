local QPS = QuestProgressShare
QPS.chatMessage = {}

function QPS.chatMessage.Send(title, text, finished)
    local message = title .. " - " .. text

    -- Send the message to the default chatframe
    if (QuestProgressShareConfig.sendSelf) then                            
        if finished then
            DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. message, 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. message, 1, 0, 0)
        end
    end

    -- Color the message green if the objective is finished, red otherwise
    if finished then
        message = "|cff00ff00" .. message .. "|r"
    else
        message = "|cffff0000" .. message .. "|r"
    end

    -- Send the message to the public chat
    if (QuestProgressShareConfig.sendPublic) then
        SendChatMessage(message, "SAY")
    end
    
    -- Send the message to the party chat
    if (QuestProgressShareConfig.sendInParty and GetNumPartyMembers() > 0) then
        SendChatMessage(message, "PARTY")
    end
end

function QPS.chatMessage.SendLink(title, text, finished)
    if not QuestProgressShareConfig or not QuestProgressShareConfig.enabled then return end
    local message
    if text and text ~= "" then
        -- Color the message green if the objective is finished, red otherwise
        if finished then
            message = title .. " - " .. "|cff00ff00" .. text .. "|r"
        else
            message = title .. " - " .. "|cffff0000" .. text .. "|r"
        end
    else
        message = title
    end
    -- Send to party
    if QuestProgressShareConfig.sendInParty and (GetNumPartyMembers() > 0) then
        if ChatThrottleLib and ChatThrottleLib.SendChatMessage then
            ChatThrottleLib:SendChatMessage("NORMAL", "QPS", message, "PARTY")
        else
            SendChatMessage(message, "PARTY")
        end
    end
    -- Send to self (show in local chat frame, not whisper)
    if QuestProgressShareConfig.sendSelf then
        if finished then
            DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. message, 0, 1, 0)
        else
            DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. message, 1, 0, 0)
        end
    end
    -- Send to public (SAY)
    if QuestProgressShareConfig.sendPublic then
        if ChatThrottleLib and ChatThrottleLib.SendChatMessage then
            ChatThrottleLib:SendChatMessage("NORMAL", "QPS", message, "SAY")
        else
            SendChatMessage(message, "SAY")
        end
    end
end