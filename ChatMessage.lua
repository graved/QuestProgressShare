local QPS = QuestProgressShare
QPS.chatMessage = {}

function QPS.chatMessage.Send(message, finished)    

    -- Send the message to the default chatframe
    if (QuestProgressShareConfig.sendSelf) then                            
        if finished then
            DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. message, 0, 1, 0)
        elseif not QuestProgressShareConfig.sendOnlyFinished then
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
    
    -- Send the message to the public chat
    if (QuestProgressShareConfig.sendInParty and GetNumPartyMembers() > 0) then
        SendChatMessage(message, "PARTY")
    end
end