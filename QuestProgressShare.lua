QuestProgressShareConfig = {}

-- Register the addon frame
local addonFrame = CreateFrame("FRAME", "QuestProgressShareFrame")

-- Save the last quest progress to avoid double messages
local lastProgress = {}

-- Event-Handler function
local function OnEvent(...)
    if event == "PLAYER_LOGIN" then
        DEFAULT_CHAT_FRAME:AddMessage("QuestProgressShare loaded")
    elseif event == "ADDON_LOADED" and arg1 == "QuestProgressShare" then
        -- Set default values for the config options
        if QuestProgressShareConfig.enabled == nil then
            QuestProgressShareConfig.enabled = true
        end

        if QuestProgressShareConfig.sendInParty == nil then
            QuestProgressShareConfig.sendInParty = true
        end

        if QuestProgressShareConfig.sendSelf == nil then
            QuestProgressShareConfig.sendSelf = false
        end

        if QuestProgressShareConfig.sendPublic == nil then
            QuestProgressShareConfig.sendPublic = false
        end

        if QuestProgressShareConfig.sendOnlyFinished == nil then
            QuestProgressShareConfig.sendOnlyFinished = false
        end
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
                        lastProgress[questKey] = text
                    elseif lastProgress[questKey] ~= text then
                        lastProgress[questKey] = text

                        -- Send the message to the party chat
                        if (QuestProgressShareConfig.sendInParty and GetNumPartyMembers() > 0) then
                            if finished then
                                SendChatMessage("|cff00ff00" .. title .. " - " .. text .. "|r", "PARTY")
                            elseif not QuestProgressShareConfig.sendOnlyFinished then
                                SendChatMessage("|cffff0000" .. title .. " - " .. text .. "|r", "PARTY")
                            end
                        end

                        -- Send the message to the default chatframe
                        if (QuestProgressShareConfig.sendSelf) then                            
                            if finished then
                                DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. title .. " - " .. text, 0, 1, 0)
                            elseif not QuestProgressShareConfig.sendOnlyFinished then
                                DEFAULT_CHAT_FRAME:AddMessage("[" .. UnitName("player") .. "]: " .. title .. " - " .. text, 1, 0, 0)
                            end
                        end

                        -- Send the message to the public chat
                        if (QuestProgressShareConfig.sendPublic) then
                            if finished then
                                SendChatMessage("|cff00ff00" .. title .. " - " .. text .. "|r", "SAY")
                            elseif not QuestProgressShareConfig.sendOnlyFinished then
                                SendChatMessage("|cffff0000" .. title .. " - " .. text .. "|r", "SAY")
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Register events
addonFrame:RegisterEvent("QUEST_LOG_UPDATE")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:SetScript("OnEvent", OnEvent)

-- Create the config frame
local configFrame = CreateFrame("Frame", "QuestProgressShareConfigFrame", UIParent)
configFrame:SetWidth(300)
configFrame:SetHeight(250)
configFrame:SetPoint("CENTER", 0, 0)
configFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
configFrame:SetBackdropColor(0, 0, 0, 1)
configFrame:SetMovable(true)
configFrame:EnableMouse(true)
configFrame:Hide()

configFrame:SetScript("OnMouseDown", function()
    this:StartMoving()
end)
  
configFrame:SetScript("OnMouseUp", function()
    this:StopMovingOrSizing()
end)  

-- Title for the config frame
local configTitle = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
configTitle:SetPoint("TOP", 0, -10)
configTitle:SetText("Quest Progress Share - Settings")

-- Checkbox for enabling/disabling the addon
local checkboxAddonEnabled = CreateFrame("CheckButton", "QuestProgressShareConfigAddonEnabledCheckbox", configFrame, "UICheckButtonTemplate")
checkboxAddonEnabled:SetPoint("TOPLEFT", 20, -40)
checkboxAddonEnabled:SetChecked(QuestProgressShareConfig.enabled)
checkboxAddonEnabled:SetScript("OnClick", function()
    QuestProgressShareConfig.enabled = checkboxAddonEnabled:GetChecked()
end)

-- Label for the "Enabled" checkbox
local labelAddonEnabled = configFrame:CreateFontString("QuestProgressShareConfigAddonEnabledLabel", "OVERLAY", "GameFontNormal")
labelAddonEnabled:SetPoint("LEFT", checkboxAddonEnabled, "RIGHT", 10, 0)
labelAddonEnabled:SetText("Enabled")

-- Checkbox for sending the messages in party chat
local checkboxSendInParty = CreateFrame("CheckButton", "QuestProgressShareConfigSendInPartyCheckbox", configFrame, "UICheckButtonTemplate")
checkboxSendInParty:SetPoint("TOPLEFT", 20, -70)
checkboxSendInParty:SetChecked(QuestProgressShareConfig.sendInParty)
checkboxSendInParty:SetScript("OnClick", function()
    QuestProgressShareConfig.sendInParty = checkboxSendInParty:GetChecked()
end)

-- Label for the "Send in Party" checkbox
local labelSendInParty = configFrame:CreateFontString("QuestProgressShareConfigSendInPartyLabel", "OVERLAY", "GameFontNormal")
labelSendInParty:SetPoint("LEFT", checkboxSendInParty, "RIGHT", 10, 0)
labelSendInParty:SetText("Send in Party")

-- Checkbox for sending the messages to the player
local checkboxSendSelf = CreateFrame("CheckButton", "QuestProgressShareConfigSendSelfCheckbox", configFrame, "UICheckButtonTemplate")
checkboxSendSelf:SetPoint("TOPLEFT", 20, -100)
checkboxSendSelf:SetChecked(QuestProgressShareConfig.sendSelf)
checkboxSendSelf:SetScript("OnClick", function()
    QuestProgressShareConfig.sendSelf = checkboxSendSelf:GetChecked()
end)

-- Label for the "Send to Self" checkbox
local labelSendSelf = configFrame:CreateFontString("QuestProgressShareConfigSendSelfLabel", "OVERLAY", "GameFontNormal")
labelSendSelf:SetPoint("LEFT", checkboxSendSelf, "RIGHT", 10, 0)
labelSendSelf:SetText("Send to Self")

-- Checkbox for sending the messages to the public chat
local checkboxSendPublic = CreateFrame("CheckButton", "QuestProgressShareConfigSendPublicCheckbox", configFrame, "UICheckButtonTemplate")
checkboxSendPublic:SetPoint("TOPLEFT", 20, -130)
checkboxSendPublic:SetChecked(QuestProgressShareConfig.sendPublic)
checkboxSendPublic:SetScript("OnClick", function()
    QuestProgressShareConfig.sendPublic = checkboxSendPublic:GetChecked()
end)

-- Label for the "Send to Public" checkbox
local labelSendPublic = configFrame:CreateFontString("QuestProgressShareConfigSendPublicLabel", "OVERLAY", "GameFontNormal")
labelSendPublic:SetPoint("LEFT", checkboxSendPublic, "RIGHT", 10, 0)
labelSendPublic:SetText("Send to Public")

-- Checkbox for sending only finished objectives
local checkboxSendOnlyFinished = CreateFrame("CheckButton", "QuestProgressShareConfigSendOnlyFinishedCheckbox", configFrame, "UICheckButtonTemplate")
checkboxSendOnlyFinished:SetPoint("TOPLEFT", 20, -160)
checkboxSendOnlyFinished:SetChecked(QuestProgressShareConfig.sendOnlyFinished)
checkboxSendOnlyFinished:SetScript("OnClick", function()
    QuestProgressShareConfig.sendOnlyFinished = checkboxSendOnlyFinished:GetChecked()
end)

-- Label for the "Send only finished" checkbox
local labelSendOnlyFinished = configFrame:CreateFontString("QuestProgressShareConfigSendOnlyFinishedLabel", "OVERLAY", "GameFontNormal")
labelSendOnlyFinished:SetPoint("LEFT", checkboxSendOnlyFinished, "RIGHT", 10, 0)
labelSendOnlyFinished:SetText("Send only finished")

-- Update the config options when the frame is shown
configFrame:SetScript("OnShow", function()
    UpdateConfigFrame()
end)

function UpdateConfigFrame()
    checkboxAddonEnabled:SetChecked(QuestProgressShareConfig.enabled)
    checkboxSendInParty:SetChecked(QuestProgressShareConfig.sendInParty)
    checkboxSendSelf:SetChecked(QuestProgressShareConfig.sendSelf)
    checkboxSendPublic:SetChecked(QuestProgressShareConfig.sendPublic)
    checkboxSendOnlyFinished:SetChecked(QuestProgressShareConfig.sendOnlyFinished)
end

-- Close-Button
local closeButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
closeButton:SetWidth(80)
closeButton:SetHeight(22)
closeButton:SetPoint("BOTTOM", 0, 20)
closeButton:SetText("Close")
closeButton:SetScript("OnClick", function()    
    configFrame:Hide()
    ReloadUI()
end)

-- minimap icon
local minimapIcon = CreateFrame('Button', "minimapIcon", Minimap)
minimapIcon:SetClampedToScreen(true)
minimapIcon:SetMovable(true)
minimapIcon:EnableMouse(true)
minimapIcon:RegisterForDrag('LeftButton')
minimapIcon:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
minimapIcon:SetScript("OnDragStart", function()
  if IsShiftKeyDown() then
    this:StartMoving()
  end
end)
minimapIcon:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
minimapIcon:SetScript("OnClick", function()  
    if configFrame:IsShown() then configFrame:Hide() else configFrame:Show() end
end)


minimapIcon:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, ANCHOR_BOTTOMLEFT)
    GameTooltip:SetText("QuestProgressShare")
    GameTooltip:AddDoubleLine("Left-Click", "Open Config", 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Shift-Click", "Move Button", 1, 1, 1, 1, 1, 1)
    GameTooltip:Show()
end)
  
minimapIcon:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

minimapIcon:SetWidth(31)
minimapIcon:SetHeight(31)
minimapIcon:SetFrameLevel(9)
minimapIcon:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
minimapIcon:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)

minimapIcon.overlay = minimapIcon:CreateTexture(nil, 'OVERLAY')
minimapIcon.overlay:SetWidth(53)
minimapIcon.overlay:SetHeight(53)
minimapIcon.overlay:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
minimapIcon.overlay:SetPoint('TOPLEFT', 0,0)

minimapIcon.icon = minimapIcon:CreateTexture(nil, 'BACKGROUND')
minimapIcon.icon:SetWidth(20)
minimapIcon.icon:SetHeight(20)
minimapIcon.icon:SetTexture("Interface\\AddOns\\QuestProgressShare\\img\\logo")
minimapIcon.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
minimapIcon.icon:SetPoint('CENTER',1,1)


-- Slash command to open the config frame
SLASH_QUESTPROGRESSSHARE1 = "/qps"
SlashCmdList["QUESTPROGRESSSHARE"] = function()
    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
end