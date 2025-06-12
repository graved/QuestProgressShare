local QPS = QuestProgressShare
QPS.config = {}

function QPS.config.SetDefaultConfigValues()
    -- Always assign all config keys, so they are always present in the SavedVariables file
    if QuestProgressShareConfig.enabled == nil then
        QuestProgressShareConfig.enabled = 1
    end
    if QuestProgressShareConfig.sendInParty == nil then
        QuestProgressShareConfig.sendInParty = 1 -- Default to enabled for new installs
    end
    if QuestProgressShareConfig.sendSelf == nil then
        QuestProgressShareConfig.sendSelf = 0
    end
    if QuestProgressShareConfig.sendPublic == nil then
        QuestProgressShareConfig.sendPublic = 0
    end
    if QuestProgressShareConfig.sendOnlyFinished == nil then
        QuestProgressShareConfig.sendOnlyFinished = 0
    end
    if QuestProgressShareConfig.sendStartingQuests == nil then
        QuestProgressShareConfig.sendStartingQuests = 0
    end
end

-- Create the config frame
QPS.configFrame = CreateFrame("Frame", "QuestProgressShareConfigFrame", UIParent)
QPS.configFrame:SetWidth(300)
QPS.configFrame:SetHeight(270)
QPS.configFrame:SetPoint("CENTER", 0, 0)
QPS.configFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
})
QPS.configFrame:SetBackdropColor(0, 0, 0, 1)
QPS.configFrame:SetMovable(true)
QPS.configFrame:EnableMouse(true)
QPS.configFrame:Hide()

QPS.configFrame:SetScript("OnMouseDown", function()
    this:StartMoving()
end)
  
QPS.configFrame:SetScript("OnMouseUp", function()
    this:StopMovingOrSizing()
end)  

-- Title for the config frame
local configTitle = QPS.configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
configTitle:SetPoint("TOP", 0, -10)
configTitle:SetText("Quest Progress Share - Settings")

-- Checkbox for enabling/disabling the addon
local checkboxAddonEnabled = CreateFrame("CheckButton", "QuestProgressShareConfigAddonEnabledCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxAddonEnabled:SetPoint("TOPLEFT", 20, -40)
checkboxAddonEnabled:SetChecked(QuestProgressShareConfig.enabled == 1)
checkboxAddonEnabled:SetScript("OnClick", function()
    QuestProgressShareConfig.enabled = checkboxAddonEnabled:GetChecked() and 1 or 0
end)

-- Label for the "Enabled" checkbox
local labelAddonEnabled = QPS.configFrame:CreateFontString("QuestProgressShareConfigAddonEnabledLabel", "OVERLAY", "GameFontNormal")
labelAddonEnabled:SetPoint("LEFT", checkboxAddonEnabled, "RIGHT", 10, 0)
labelAddonEnabled:SetText("Enabled")

-- Checkbox for sending the messages in party chat
local checkboxSendInParty = CreateFrame("CheckButton", "QuestProgressShareConfigSendInPartyCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendInParty:SetPoint("TOPLEFT", 20, -70)
checkboxSendInParty:SetChecked(QuestProgressShareConfig.sendInParty == 1)
checkboxSendInParty:SetScript("OnClick", function()
    QuestProgressShareConfig.sendInParty = checkboxSendInParty:GetChecked() and 1 or 0
end)

-- Label for the "Send in Party" checkbox
local labelSendInParty = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendInPartyLabel", "OVERLAY", "GameFontNormal")
labelSendInParty:SetPoint("LEFT", checkboxSendInParty, "RIGHT", 10, 0)
labelSendInParty:SetText("Send in Party")

-- Checkbox for sending the messages to the player
local checkboxSendSelf = CreateFrame("CheckButton", "QuestProgressShareConfigSendSelfCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendSelf:SetPoint("TOPLEFT", 20, -100)
checkboxSendSelf:SetChecked(QuestProgressShareConfig.sendSelf == 1)
checkboxSendSelf:SetScript("OnClick", function()
    QuestProgressShareConfig.sendSelf = checkboxSendSelf:GetChecked() and 1 or 0
end)

-- Label for the "Send to Self" checkbox
local labelSendSelf = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendSelfLabel", "OVERLAY", "GameFontNormal")
labelSendSelf:SetPoint("LEFT", checkboxSendSelf, "RIGHT", 10, 0)
labelSendSelf:SetText("Send to Self")

-- Checkbox for sending the messages to the public chat
local checkboxSendPublic = CreateFrame("CheckButton", "QuestProgressShareConfigSendPublicCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendPublic:SetPoint("TOPLEFT", 20, -130)
checkboxSendPublic:SetChecked(QuestProgressShareConfig.sendPublic == 1)
checkboxSendPublic:SetScript("OnClick", function()
    QuestProgressShareConfig.sendPublic = checkboxSendPublic:GetChecked() and 1 or 0
end)

-- Label for the "Send to Public" checkbox
local labelSendPublic = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendPublicLabel", "OVERLAY", "GameFontNormal")
labelSendPublic:SetPoint("LEFT", checkboxSendPublic, "RIGHT", 10, 0)
labelSendPublic:SetText("Send to Public")

-- Checkbox for sending only finished objectives
local checkboxSendOnlyFinished = CreateFrame("CheckButton", "QuestProgressShareConfigSendOnlyFinishedCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendOnlyFinished:SetPoint("TOPLEFT", 20, -160)
checkboxSendOnlyFinished:SetChecked(QuestProgressShareConfig.sendOnlyFinished == 1)
checkboxSendOnlyFinished:SetScript("OnClick", function()
    QuestProgressShareConfig.sendOnlyFinished = checkboxSendOnlyFinished:GetChecked() and 1 or 0
end)

-- Label for the "Send only finished" checkbox
local labelSendOnlyFinished = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendOnlyFinishedLabel", "OVERLAY", "GameFontNormal")
labelSendOnlyFinished:SetPoint("LEFT", checkboxSendOnlyFinished, "RIGHT", 10, 0)
labelSendOnlyFinished:SetText("Send only finished")

-- Checkbox for sending starting quests
local checkboxSendStartingQuests = CreateFrame("CheckButton", "QuestProgressShareConfigSendStartingQuestsCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendStartingQuests:SetPoint("TOPLEFT", 20, -190)
checkboxSendStartingQuests:SetChecked(QuestProgressShareConfig.sendStartingQuests == 1)
checkboxSendStartingQuests:SetScript("OnClick", function()
    QuestProgressShareConfig.sendStartingQuests = checkboxSendStartingQuests:GetChecked() and 1 or 0
end)

-- Label for the "Send starting quests" checkbox
local labelSendStartingQuests = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendStartingQuestsLabel", "OVERLAY", "GameFontNormal")
labelSendStartingQuests:SetPoint("LEFT", checkboxSendStartingQuests, "RIGHT", 10, 0)
labelSendStartingQuests:SetText("Send starting quests")

-- Update the config options when the frame is shown
QPS.configFrame:SetScript("OnShow", function()
    UpdateConfigFrame()
end)

function UpdateConfigFrame()
    checkboxAddonEnabled:SetChecked(QuestProgressShareConfig.enabled == 1)
    checkboxSendInParty:SetChecked(QuestProgressShareConfig.sendInParty == 1)
    checkboxSendSelf:SetChecked(QuestProgressShareConfig.sendSelf == 1)
    checkboxSendPublic:SetChecked(QuestProgressShareConfig.sendPublic == 1)
    checkboxSendOnlyFinished:SetChecked(QuestProgressShareConfig.sendOnlyFinished == 1)
    checkboxSendStartingQuests:SetChecked(QuestProgressShareConfig.sendStartingQuests == 1)
end

-- Close-Button
local closeButton = CreateFrame("Button", nil, QPS.configFrame, "UIPanelButtonTemplate")
closeButton:SetWidth(80)
closeButton:SetHeight(22)
closeButton:SetPoint("BOTTOM", 0, 20)
closeButton:SetText("Close")
closeButton:SetScript("OnClick", function()    
    QPS.configFrame:Hide()
    -- ReloadUI()
end)