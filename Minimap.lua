-- Minimap.lua: Handles minimap button and related UI for QuestProgressShare.
-- Provides user access to config and quick actions from the minimap.

local QPS = QuestProgressShare
QPS.minimap = {}

QPS.minimap.frame = CreateFrame('Button', "QuestProgressShareMinimapIcon", Minimap)
QPS.minimap.frame:SetClampedToScreen(true)
QPS.minimap.frame:SetMovable(true)
QPS.minimap.frame:EnableMouse(true)
QPS.minimap.frame:RegisterForDrag('LeftButton')
QPS.minimap.frame:RegisterForClicks('LeftButtonUp', 'RightButtonUp')
QPS.minimap.frame:SetScript("OnDragStart", function()
  if IsShiftKeyDown() then
    this:StartMoving()
  end
end)
QPS.minimap.frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
QPS.minimap.frame:SetScript("OnClick", function()  
    if QPS.configFrame:IsShown() then QPS.configFrame:Hide() else QPS.configFrame:Show() end
end)


QPS.minimap.frame:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, ANCHOR_BOTTOMLEFT)
    GameTooltip:SetText("QuestProgressShare")
    GameTooltip:AddDoubleLine("Left-Click", "Open Config", 1, 1, 1, 1, 1, 1)
    GameTooltip:AddDoubleLine("Shift-Click", "Move Button", 1, 1, 1, 1, 1, 1)
    GameTooltip:Show()
end)
  
QPS.minimap.frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

QPS.minimap.frame:SetWidth(31)
QPS.minimap.frame:SetHeight(31)
QPS.minimap.frame:SetFrameLevel(9)
QPS.minimap.frame:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
QPS.minimap.frame:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 0, 0)

QPS.minimap.overlay = QPS.minimap.frame:CreateTexture(nil, 'OVERLAY')
QPS.minimap.overlay:SetWidth(53)
QPS.minimap.overlay:SetHeight(53)
QPS.minimap.overlay:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
QPS.minimap.overlay:SetPoint('TOPLEFT', 0,0)

QPS.minimap.icon = QPS.minimap.frame:CreateTexture(nil, 'BACKGROUND')
QPS.minimap.icon:SetWidth(20)
QPS.minimap.icon:SetHeight(20)
QPS.minimap.icon:SetTexture("Interface\\AddOns\\QuestProgressShare\\img\\logo")
QPS.minimap.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
QPS.minimap.icon:SetPoint('CENTER',1,1)