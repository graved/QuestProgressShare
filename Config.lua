-- Config.lua: Manages configuration UI and default settings for QuestProgressShare.
-- Handles creation of the config frame, checkboxes, and saving/loading of user preferences.

local QPS = QuestProgressShare
QPS.config = {}

-- Sets default values for the QuestProgressShareConfig table if not already set.
function QPS.config.SetDefaultConfigValues()
    -- Only set defaults if the config table does not exist
    if type(QuestProgressShareConfig) ~= "table" then
        QuestProgressShareConfig = {}
    end

    -- Only set to true if the value is nil (first install)
    if QuestProgressShareConfig.enabled == nil then
        QuestProgressShareConfig.enabled = 1
    end
    if QuestProgressShareConfig.sendInParty == nil then
        QuestProgressShareConfig.sendInParty = 1
    end

    -- The rest of the config options
    if QuestProgressShareConfig.sendSelf == nil then
        QuestProgressShareConfig.sendSelf = false
    end
    if QuestProgressShareConfig.sendPublic == nil then
        QuestProgressShareConfig.sendPublic = false
    end
    if QuestProgressShareConfig.sendOnlyFinished == nil then
        QuestProgressShareConfig.sendOnlyFinished = false
    end
    if QuestProgressShareConfig.sendStartingQuests == nil then
        QuestProgressShareConfig.sendStartingQuests = false
    end
    if QuestProgressShareConfig.debugEnabled == nil then
        QuestProgressShareConfig.debugEnabled = false
    end
    if QuestProgressShareConfig.verboseDebugEnabled == nil then
        QuestProgressShareConfig.verboseDebugEnabled = false
    end
    if QuestProgressShareConfig.sendAbandoned == nil then
        QuestProgressShareConfig.sendAbandoned = false
    end
end

-- Create the config frame
QPS.configFrame = CreateFrame("Frame", "QuestProgressShareConfigFrame", UIParent)
QPS.configFrame:SetWidth(300)
QPS.configFrame:SetHeight(350)
QPS.configFrame:SetPoint("CENTER", 0, 0)

-- Apply pfUI styling if pfUI is available, otherwise use default styling
if pfUI and pfUI.api and pfUI.api.CreateBackdrop then
    -- Use pfUI styling
    pfUI.api.CreateBackdrop(QPS.configFrame, nil, true, 0.8)
else
    -- Use default WoW styling
    QPS.configFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    QPS.configFrame:SetBackdropColor(0, 0, 0, 1)
end

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
checkboxSendSelf:SetChecked(QuestProgressShareConfig.sendSelf)
checkboxSendSelf:SetScript("OnClick", function()
    QuestProgressShareConfig.sendSelf = checkboxSendSelf:GetChecked()
end)

-- Label for the "Send to Self" checkbox
local labelSendSelf = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendSelfLabel", "OVERLAY", "GameFontNormal")
labelSendSelf:SetPoint("LEFT", checkboxSendSelf, "RIGHT", 10, 0)
labelSendSelf:SetText("Send to Self")

-- Checkbox for sending the messages to the public chat
local checkboxSendPublic = CreateFrame("CheckButton", "QuestProgressShareConfigSendPublicCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendPublic:SetPoint("TOPLEFT", 20, -130)
checkboxSendPublic:SetChecked(QuestProgressShareConfig.sendPublic)
checkboxSendPublic:SetScript("OnClick", function()
    QuestProgressShareConfig.sendPublic = checkboxSendPublic:GetChecked()
end)

-- Label for the "Send to Public" checkbox
local labelSendPublic = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendPublicLabel", "OVERLAY", "GameFontNormal")
labelSendPublic:SetPoint("LEFT", checkboxSendPublic, "RIGHT", 10, 0)
labelSendPublic:SetText("Send to Public")

-- Checkbox for sending only finished objectives
local checkboxSendOnlyFinished = CreateFrame("CheckButton", "QuestProgressShareConfigSendOnlyFinishedCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendOnlyFinished:SetPoint("TOPLEFT", 20, -160)
checkboxSendOnlyFinished:SetChecked(QuestProgressShareConfig.sendOnlyFinished)
checkboxSendOnlyFinished:SetScript("OnClick", function()
    QuestProgressShareConfig.sendOnlyFinished = checkboxSendOnlyFinished:GetChecked()
end)

-- Label for the "Send only finished" checkbox
local labelSendOnlyFinished = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendOnlyFinishedLabel", "OVERLAY", "GameFontNormal")
labelSendOnlyFinished:SetPoint("LEFT", checkboxSendOnlyFinished, "RIGHT", 10, 0)
labelSendOnlyFinished:SetText("Send only finished")

-- Checkbox for sending starting quests
local checkboxSendStartingQuests = CreateFrame("CheckButton", "QuestProgressShareConfigSendStartingQuestsCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendStartingQuests:SetPoint("TOPLEFT", 20, -190)
checkboxSendStartingQuests:SetChecked(QuestProgressShareConfig.sendStartingQuests)
checkboxSendStartingQuests:SetScript("OnClick", function()
    QuestProgressShareConfig.sendStartingQuests = checkboxSendStartingQuests:GetChecked()
end)

-- Label for the "Send starting quests" checkbox
local labelSendStartingQuests = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendStartingQuestsLabel", "OVERLAY", "GameFontNormal")
labelSendStartingQuests:SetPoint("LEFT", checkboxSendStartingQuests, "RIGHT", 10, 0)
labelSendStartingQuests:SetText("Send starting quests")

-- Checkbox for sending abandoned quests
local checkboxSendAbandoned = CreateFrame("CheckButton", "QuestProgressShareConfigSendAbandonedCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxSendAbandoned:SetPoint("TOPLEFT", 20, -220)
checkboxSendAbandoned:SetChecked(QuestProgressShareConfig.sendAbandoned)
checkboxSendAbandoned:SetScript("OnClick", function()
    QuestProgressShareConfig.sendAbandoned = checkboxSendAbandoned:GetChecked()
end)

-- Label for the "Send abandoned quests" checkbox
local labelSendAbandoned = QPS.configFrame:CreateFontString("QuestProgressShareConfigSendAbandonedLabel", "OVERLAY", "GameFontNormal")
labelSendAbandoned:SetPoint("LEFT", checkboxSendAbandoned, "RIGHT", 10, 0)
labelSendAbandoned:SetText("Send abandoned quests")

-- Checkbox for debug output
local checkboxDebugEnabled = CreateFrame("CheckButton", "QuestProgressShareConfigDebugEnabledCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxDebugEnabled:SetPoint("TOPLEFT", 20, -250)
checkboxDebugEnabled:SetChecked(QuestProgressShareConfig.debugEnabled)
checkboxDebugEnabled:SetScript("OnClick", function()
    QuestProgressShareConfig.debugEnabled = checkboxDebugEnabled:GetChecked()
    -- Update verbose debug checkbox state when debug is toggled
    UpdateVerboseDebugState()
end)

local labelDebugEnabled = QPS.configFrame:CreateFontString("QuestProgressShareConfigDebugEnabledLabel", "OVERLAY", "GameFontNormal")
labelDebugEnabled:SetPoint("LEFT", checkboxDebugEnabled, "RIGHT", 10, 0)
labelDebugEnabled:SetText("Enable debug logging")

-- Checkbox for verbose debug output
local checkboxVerboseDebugEnabled = CreateFrame("CheckButton", "QuestProgressShareConfigVerboseDebugEnabledCheckbox", QPS.configFrame, "UICheckButtonTemplate")
checkboxVerboseDebugEnabled:SetPoint("TOPLEFT", 40, -280)
checkboxVerboseDebugEnabled:SetChecked(QuestProgressShareConfig.verboseDebugEnabled)
checkboxVerboseDebugEnabled:SetScript("OnClick", function()
    QuestProgressShareConfig.verboseDebugEnabled = checkboxVerboseDebugEnabled:GetChecked()
end)

local labelVerboseDebugEnabled = QPS.configFrame:CreateFontString("QuestProgressShareConfigVerboseDebugEnabledLabel", "OVERLAY", "GameFontNormal")
labelVerboseDebugEnabled:SetPoint("LEFT", checkboxVerboseDebugEnabled, "RIGHT", 10, 0)
labelVerboseDebugEnabled:SetText("Enable verbose debug logging")

-- Function to update verbose debug checkbox state based on debug enabled
function UpdateVerboseDebugState()
    local isDebugEnabled = QuestProgressShareConfig.debugEnabled
    if isDebugEnabled then
        checkboxVerboseDebugEnabled:Enable()
        labelVerboseDebugEnabled:SetTextColor(1, 0.82, 0) -- Yellow text when enabled and debug is on (same as other labels)
    else
        checkboxVerboseDebugEnabled:Disable()
        checkboxVerboseDebugEnabled:SetChecked(false)
        QuestProgressShareConfig.verboseDebugEnabled = false
        labelVerboseDebugEnabled:SetTextColor(0.5, 0.5, 0.5) -- Gray text when disabled
    end
end

-- Update the config options when the frame is shown
QPS.configFrame:SetScript("OnShow", function()
    UpdateConfigFrame()
end)

-- Updates the state of all config checkboxes to match the current values in QuestProgressShareConfig.
function UpdateConfigFrame()
    checkboxAddonEnabled:SetChecked(QuestProgressShareConfig.enabled == 1)
    checkboxSendInParty:SetChecked(QuestProgressShareConfig.sendInParty == 1)
    checkboxSendSelf:SetChecked(QuestProgressShareConfig.sendSelf)
    checkboxSendPublic:SetChecked(QuestProgressShareConfig.sendPublic)
    checkboxSendOnlyFinished:SetChecked(QuestProgressShareConfig.sendOnlyFinished)
    checkboxSendStartingQuests:SetChecked(QuestProgressShareConfig.sendStartingQuests)
    checkboxSendAbandoned:SetChecked(QuestProgressShareConfig.sendAbandoned)
    checkboxDebugEnabled:SetChecked(QuestProgressShareConfig.debugEnabled)
    checkboxVerboseDebugEnabled:SetChecked(QuestProgressShareConfig.verboseDebugEnabled)
    -- Update verbose debug state based on debug enabled
    UpdateVerboseDebugState()
end

-- Creates and configures the Close button for the config frame.
local closeButton = CreateFrame("Button", nil, QPS.configFrame, "UIPanelButtonTemplate")
closeButton:SetWidth(80)
closeButton:SetHeight(22)
closeButton:SetPoint("BOTTOM", 0, 10)
closeButton:SetText("Close")

-- Apply pfUI styling to the close button if pfUI is available
if pfUI and pfUI.api and pfUI.api.SkinButton then
    pfUI.api.SkinButton(closeButton)
end

closeButton:SetScript("OnClick", function()    
    QPS.configFrame:Hide()
    -- ReloadUI()
end)