-- Main.lua: Entry point for QuestProgressShare addon initialization.
-- Handles addon loading, global setup, and initial event registration.

QuestProgressShare = CreateFrame('Frame', 'QuestProgressShare', UIParent)

if not QuestProgressShareConfig then
    QuestProgressShareConfig = {}
end
