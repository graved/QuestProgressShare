-- QuestStringHelpers.lua: Utility functions for parsing and manipulating quest-related strings in QuestProgressShare.
-- Provides helpers for extracting, normalizing, and comparing quest objective text and progress values.

-- Extracts the quest title from a WoW quest link string (e.g. |cff...|Hquest:...|h[Title]|h|r)
function ExtractQuestTitle(str)
    if type(str) ~= "string" then return str end
    local hIdx = nil
    local len = StringLib.Len(str)
    for i = len, 1, -1 do
        if StringLib.Sub(str, i, i+2) == "|h[" then
            hIdx = i
            break
        end
    end
    if hIdx then
        local closeIdx = nil
        for j = hIdx+3, len do
            if StringLib.Sub(str, j, j) == "]" then
                closeIdx = j
                break
            end
        end
        if closeIdx then
            return StringLib.Sub(str, hIdx+3, closeIdx-1)
        end
    end
    return str
end

-- Extracts progress numbers and label from objective text (e.g. 'Undead Ravager slain: 30/30')
function ExtractProgress(str)
    if type(str) ~= "string" then return str end
    local colon = StringLib.Find(str, ":")
    if colon then
        local label = StringLib.Sub(str, 1, colon-1)
        local n1, n2 = StringLib.SafeExtractNumbers(str)
        if n1 and n2 then
            return label .. ": " .. n1 .. "/" .. n2
        end
    end
    return str
end

-- Cleans up objective text for stable comparison (removes color codes and trims whitespace)
function NormalizeObjectiveText(text)
    if not text then return "" end
    text = StringLib.Gsub(text, "|c%x%x%x%x%x%x%x%x", "")
    text = StringLib.Gsub(text, "|r", "")
    text = StringLib.Gsub(text, "^%s+", "")
    text = StringLib.Gsub(text, "%s+$", "")
    return text
end

-- Strict sanitizer for addon channel: extract quest title and progress, fallback to safe text
function SanitizeAddonMessage(title, text)
    local safeTitle = ExtractQuestTitle(title)
    local safeText = ExtractProgress(text)
    if StringLib.Find(safeTitle, "|") then safeTitle = StringLib.Gsub(safeTitle, "|", "") end
    if StringLib.Find(safeText, "|") then safeText = StringLib.Gsub(safeText, "|", "") end
    if QPS_DebugLog then
        table.insert(QPS_DebugLog, "SanitizeAddonMessage: title_before='"..tostring(title).."' title_after='"..tostring(safeTitle).."' text_before='"..tostring(text).."' text_after='"..tostring(safeText).."'")
    end
    return safeTitle, safeText
end

-- Returns a clickable quest link for chat, using pfQuest data if available
function GetClickableQuestLink(questID, title, pfDB, pfUI, pfQuestCompat, StringLib)
    local qid = tostring(questID)
    local qid_num = tonumber(questID)
    local locale = GetLocale and GetLocale() or "enUS"
    local pfquests = pfDB and pfDB["quests"]
    local pfdbs = {
        { data = pfquests and pfquests["data"], loc = pfquests and pfquests["loc"] }, -- pfQuest legacy
        { data = pfquests and pfquests["data-turtle"], loc = pfquests and pfquests[locale.."-turtle"] }, -- pfQuest-turtle
        { data = pfquests and pfquests["data"], loc = pfquests and pfquests[locale] } -- pfQuest with locale
    }
    local foundData, foundLoc, foundType
    for i, db in ipairs(pfdbs) do
        if db.data and db.loc then
            local data = db.data[qid] or (qid_num and db.data[qid_num])
            local loc = db.loc[qid] or (qid_num and db.loc[qid_num])
            if data or loc then
                foundData, foundLoc = data, loc
                foundType = (i == 1 and "pfQuest-loc") or (i == 2 and "pfQuest-turtle") or (i == 3 and "pfQuest-locale")
                break
            end
        end
    end
    local link
    if foundData or foundLoc then
        local level = foundData and foundData["lvl"] or 0
        local name = foundLoc and foundLoc["T"] or (foundData and foundData["T"] or ("Quest "..qid))
        local hex = "|cffffff00"
        if pfUI and pfUI.api and pfUI.api.rgbhex and pfQuestCompat and pfQuestCompat.GetDifficultyColor then
            hex = pfUI.api.rgbhex(pfQuestCompat.GetDifficultyColor(level))
        end
        link = hex .. "|Hquest:"..qid..":"..level.."|h["..name.."]|h|r"
    elseif questID and tonumber(questID) then
        local safeTitle = (type(title) == "string" and title) or ("Quest "..tostring(questID))
        local cleanTitle = StringLib.Gsub(safeTitle, "|", "")
        local hex = "|cffffff00"
        if pfUI and pfUI.api and pfUI.api.rgbhex and pfQuestCompat and pfQuestCompat.GetDifficultyColor then
            hex = pfUI.api.rgbhex(pfQuestCompat.GetDifficultyColor(0))
        end
        link = hex .. "|Hquest:"..tostring(questID)..":0|h["..cleanTitle.."]|h|r"
    elseif type(title) == "string" and StringLib.Sub(title, 1, 8) == "|Hquest:" then
        if StringLib.Sub(title, 1, 10) ~= "|cffffff00" then
            link = "|cffffff00" .. title .. "|r"
        else
            link = title
        end
    elseif type(title) == "string" then
        local safeTitle = StringLib.Gsub(title, "|", "")
        link = "[" .. safeTitle .. "]"
    else
        link = qid
    end
    if type(link) == "string" and StringLib.Sub(link, 1, 8) == "|Hquest:" then
        if StringLib.Sub(link, 1, 10) ~= "|cffffff00" then
            link = "|cffffff00" .. link .. "|r"
        end
    end
    return link
end
