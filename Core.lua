-- Core.lua: Main logic and event handling for QuestProgressShare
-- Centralizes quest progress tracking, event registration, pfQuest integration, debug logging, party sync, and robust quest state management.
-- This file orchestrates all core addon operations and data flow.

--------------------------------------------------
-- GLOBALS & CONSTANTS
--------------------------------------------------
-- Reference to main addon table
local QPS = QuestProgressShare
-- Core.lua - Main logic for QuestProgressShare

-- State variables for quest progress tracking
local lastProgress = {} -- Tracks the most recent progress for each quest objective (keyed by quest and objective)
local completedQuestTitle = nil -- Stores the title of the quest currently being turned in (for completion detection)
local sentCompleted = {} -- Remembers which quests have already had a completion message sent this session to avoid duplicates
local sentProgressThisSession = {} -- Remembers which progress updates have been sent in this session (per questKey)

-- Suppress progress messages during initial scan after login/reload
QPS._suppressInitialProgress = false

-- Local aliases for Blizzard quest log API
local QPSGet_QuestLogTitle = GetQuestLogTitle
local QPSGet_NumQuestLogEntries = GetNumQuestLogEntries
local QPSGet_QuestLogLeaderBoard = GetQuestLogLeaderBoard
local QPSSelect_QuestLogEntry = SelectQuestLogEntry
local QPSGet_QuestLogQuestText = GetQuestLogQuestText
local QPSGet_NumQuestLeaderBoards = GetNumQuestLeaderBoards

-- pfQuest integration (if available)
local getQuestIDs = pfDatabase and pfDatabase.GetQuestIDs -- pfQuest's GetQuestIDs function, if present
local pfDB = pfDB -- pfQuest's global database table, if present

-- Debug log tables by group
QPS_DebugLog = {}            -- General debug log
QPS_CoreDebugLog = {}        -- Core logic debug log
QPS_EventDebugLog = {}       -- Event handling debug log
QPS_ProgressDebugLog = {}    -- Quest progress tracking debug log
QPS_SyncDebugLog = {}        -- Data synchronization debug log
QPS_ConfigDebugLog = {}      -- UI/configuration debug log

--------------------------------------------------
-- DEBUG LOGGING
--------------------------------------------------
-- Unified debug logging function for all log groups
function LogDebugMessage(logTable, msg)
    if not (QuestProgressShareConfig and QuestProgressShareConfig.debugEnabled) then return end
    if not msg or not logTable then return end
    local timestamp = date("%Y-%m-%d %H:%M")
    local logMsg = "[" .. timestamp .. "] " .. tostring(msg)
    table.insert(logTable, logMsg)
end

--------------------------------------------------
-- QUEST LOG INDEX & ID HELPERS
--------------------------------------------------
-- Checks if a quest log index is valid and points to a real quest (not a header)
local function IsValidQuestLogIndex(index)
    if type(index) ~= "number" or index < 1 or index > QPSGet_NumQuestLogEntries() then return false end
    local title, _, _, isHeader = QPSGet_QuestLogTitle(index)
    return (not isHeader) and title and title ~= ""
end

-- Cache for SafeGetQuestIDs results per scan
local questIDCache = {} -- Caches quest IDs for each quest log index during a scan to avoid redundant lookups

-- Safely retrieves quest IDs using pfQuest, with fallback and caching
local function SafeGetQuestIDs(index, title)
    -- Returns a list of quest IDs for the given quest log index, using pfQuest if available. Falls back to title lookup if needed. Results are cached per scan.
    if questIDCache[index] ~= nil then
        return questIDCache[index]
    end
    if not IsValidQuestLogIndex(index) then
        questIDCache[index] = nil
        return nil
    end
    if getQuestIDs then
        local ok, ids = pcall(getQuestIDs, index)
        if ok and ids and ids[1] then
            questIDCache[index] = ids
            return ids
        else
            local logTitle = GetQuestLogTitle(index)
            if title and logTitle and logTitle == title and pfDB and pfDB["quests"] and pfDB["quests"]["loc"] then
                for id, data in pairs(pfDB["quests"]["loc"]) do
                    if data.T == title then
                        questIDCache[index] = { tonumber(id) }
                        return questIDCache[index]
                    end
                end
            end
        end
    end
    questIDCache[index] = nil
    return nil
end

--------------------------------------------------
-- QUEST PROGRESS SCANNING & SYNC
--------------------------------------------------
-- Scans the quest log and updates lastProgress without sending messages
local function DummyQuestProgressScan()
    LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: DummyQuestProgressScan start')
    for questIndex = 1, QPSGet_NumQuestLogEntries() do
        local title, _, _, isHeader, _, _, isComplete = QPSGet_QuestLogTitle(questIndex)
        if not isHeader and title and IsValidQuestLogIndex(questIndex) then
            if pfDB then
                local ids = SafeGetQuestIDs(questIndex, title)
                local questID = ids and ids[1] and tonumber(ids[1])
                if questID then
                    QPSSelect_QuestLogEntry(questIndex)
                end
            else
                QPSSelect_QuestLogEntry(questIndex)
            end
            local objectives = QPSGet_NumQuestLeaderBoards()
            -- If the quest has no objectives and is complete, mark as completed (for turn-in only quests)
            if objectives == 0 and isComplete then
                local questKey = title .. "-COMPLETE"
                lastProgress[questKey] = "Quest completed"
            end
            for i = 1, objectives do
                local text = QPSGet_QuestLogLeaderBoard(i)
                local questKey = title .. "-" .. i
                lastProgress[questKey] = text
                LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: DummyScan set ' .. questKey .. ' = ' .. tostring(text))
            end
            if objectives > 0 then
                local questKey = title .. "-COMPLETE"
                if isComplete then
                    lastProgress[questKey] = "Quest completed"
                end
            end
        end
    end
    LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: DummyQuestProgressScan end, lastProgress:')
    for k,v in pairs(lastProgress) do LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: lastProgress ' .. k .. ' = ' .. tostring(v)) end
end

-- Finds a quest ID by its title using pfQuest DB
local function FindQuestIDByTitle(title)
    -- Looks up a quest ID by its title in the pfQuest database, if available
    if pfDB and pfDB.quests and pfDB.quests.loc then
        for id, data in pairs(pfDB.quests.loc) do
            if data.T == title then
                return tonumber(id)
            end
        end
    end
    return nil
end

-- Sends a quest progress or completion message, using clickable links if possible
local function SendQuestMessage(title, text, finished, questIndex, objectiveIndex, forceSend)
    -- Sends a quest progress or completion message to chat and party, using clickable links if available. Handles duplicate suppression and session state.
    LogDebugMessage(QPS_CoreDebugLog, '[QPS-TRACE] SendQuestMessage called: title='..tostring(title)..', text='..tostring(text)..', finished='..tostring(finished)..', questIndex='..tostring(questIndex)..', objectiveIndex='..tostring(objectiveIndex)..', forceSend='..tostring(forceSend))
    local questKey = title
    if objectiveIndex then
        questKey = title .. '-' .. tostring(objectiveIndex)
    end
    LogDebugMessage(QPS_CoreDebugLog, '[QPS-TRACE] sentProgressThisSession['..questKey..']='..tostring(sentProgressThisSession[questKey]))
    -- Always send "Quest accepted" regardless of duplicate suppression
    if text == "Quest accepted" then
        LogDebugMessage(QPS_CoreDebugLog, '[QPS-FIX] SendQuestMessage: Forcing send for "Quest accepted" for '..tostring(title))
    else
        -- Prevent duplicate progress messages if already sent this session, unless forceSend is true
        if not finished and not forceSend and sentProgressThisSession[questKey] == text then
            LogDebugMessage(QPS_CoreDebugLog, '[QPS-FIX] SendQuestMessage: Suppressed duplicate for '..questKey..' text='..tostring(text))
            return
        end
        if finished and sentCompleted[title] then 
            LogDebugMessage(QPS_CoreDebugLog, '[QPS-TRACE] SendQuestMessage: Suppressed completed for '..title..' (already sent)')
            return 
        end
        if finished then sentCompleted[title] = true end
    end
    local questID = nil
    if pfDB then
        if questIndex then
            local ids = SafeGetQuestIDs(questIndex, title)
            if ids and ids[1] then
                questID = ids[1]
                -- Double-check: only send if the quest title for this questIndex matches pfQuest DB for this questID
                local pfTitle = nil
                if pfDB.quests and pfDB.quests.loc and pfDB.quests.loc[tostring(questID)] then
                    pfTitle = pfDB.quests.loc[tostring(questID)].T
                end
                local logTitle = GetQuestLogTitle(questIndex)
                if pfTitle and logTitle and pfTitle ~= logTitle then
                    -- If the pfQuest DB title and quest log title do not match, do not send
                    return
                end
            else
                questID = FindQuestIDByTitle(title)
            end
        else
            questID = FindQuestIDByTitle(title)
        end
    elseif getQuestIDs then
        local ids = getQuestIDs(title)
        if ids and ids[1] then questID = ids[1] end
    end
    if pfDB and questID then
        local link = GetClickableQuestLink(questID, title, pfDB, pfUI, pfQuestCompat, StringLib)
        -- Accept any link containing |Hquest: as a clickable quest link
        if link and type(link) == "string" and StringLib.Find(link, "|Hquest:") then
            QPS.chatMessage.SendLink(link, text, finished, objectiveIndex)
            if text ~= "Quest accepted" then
                local questKey = title
                if objectiveIndex then
                    questKey = title .. "-" .. tostring(objectiveIndex)
                end
                sentProgressThisSession[questKey] = text
            end
            return
        end
    end
    QPS.chatMessage.Send(title, text, finished, objectiveIndex)
    if text ~= "Quest accepted" then
        local questKey = title
        if objectiveIndex then
            questKey = title .. "-" .. tostring(objectiveIndex)
        end
        sentProgressThisSession[questKey] = text
    end
end

--------------------------------------------------
-- QUEST LOG SNAPSHOT & DIFF HELPERS
--------------------------------------------------
-- Returns true if this is the first time the addon has ever loaded for this character (based on load count)
local function IsFirstLoadEver()
    -- Checks if this is the first time the addon has loaded for this character (based on persistent load count)
    return QPS_SavedLoadCount == 1
end

-- In-memory cache of last known quest log state (used for diffing quest changes)
local questLogCache = {}

-- Quest hash function for robust quest identification (uses name and level)
local function GetQuestHash(name, level)
    -- Returns a unique hash for a quest using its name and level, to detect progress changes
    local hash = tostring(name or "") .. "|" .. tostring(level or "")
    return hash
end

-- Helper: Build a snapshot of the current quest log state (for diffing and cache)
local function BuildQuestLogSnapshot()
    -- Builds a table snapshot of the current quest log state, including objectives and completion, for diffing and cache
    local snapshot = {}
    local numEntries = QPSGet_NumQuestLogEntries()
    for questIndex = 1, numEntries do
        local title, level, _, isHeader, _, _, isComplete = QPSGet_QuestLogTitle(questIndex)
        if not isHeader and title then
            -- Always select the quest to ensure objectives are up-to-date (matches Questie logic)
            QPSSelect_QuestLogEntry(questIndex)
            local objectives = {}
            local numObjectives = QPSGet_NumQuestLeaderBoards()
            for i = 1, numObjectives do
                local text, objType, finished = QPSGet_QuestLogLeaderBoard(i)
                LogDebugMessage(QPS_CoreDebugLog, '[QPS-DEBUG] BuildQuestLogSnapshot: i='..tostring(i)..', text='..tostring(text)..', objType='..tostring(objType)..', finished='..tostring(finished))
                text = NormalizeObjectiveText(text)
                objectives[i] = { text = text, finished = finished }
            end
            local hash = GetQuestHash(title, level)
            snapshot[hash] = {
                title = title,
                level = level,
                isComplete = isComplete,
                objectives = objectives,
            }
        end
    end
    return snapshot
end

-- Helper: Returns true if any quest log headers are collapsed (prevents accurate scanning)
local function AnyQuestLogHeadersCollapsed()
    -- Returns true if any quest log headers are collapsed, which prevents accurate scanning
    local numEntries = QPSGet_NumQuestLogEntries()
    for i = 1, numEntries do
        local _, _, _, isHeader, isCollapsed = QPSGet_QuestLogTitle(i)
        if isHeader and isCollapsed then
            return true
        end
    end
    return false
end

-- Helper: Load questLogCache from QPS_SavedProgress (for silent cache refresh)
local function LoadCacheFromSavedProgress()
    -- Loads the in-memory questLogCache from QPS_SavedProgress, used for silent refresh when headers are collapsed
    for k in pairs(questLogCache) do questLogCache[k] = nil end
    if QPS_SavedProgress then
        for k, v in pairs(QPS_SavedProgress) do
            questLogCache[k] = v
        end
    end
end

-- Helper: Table length for associative or array tables (Vanilla WoW compatible)
local function GetTableLength(t)
    -- Returns the number of keys in a table (works for both arrays and associative tables)
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- Helper: Keep QPS_SavedProgress in sync with lastProgress in real time
local function SyncSavedProgress()
    -- Synchronizes QPS_SavedProgress with lastProgress, ensuring only valid progress strings are saved and completed states are handled correctly
    if not QPS_SavedProgress then QPS_SavedProgress = {} end
    LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: START')
    LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: QPS_SavedProgress BEFORE:')
    for k,v in pairs(QPS_SavedProgress) do LogDebugMessage(QPS_CoreDebugLog, 'QPS_SavedProgress['..tostring(k)..'] = '..tostring(v)) end
    LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: lastProgress:')
    for k,v in pairs(lastProgress) do LogDebugMessage(QPS_CoreDebugLog, 'lastProgress['..tostring(k)..'] = '..tostring(v)) end
    local prevSavedProgress = {}
    -- Remove keys not in lastProgress, and backup previous values in one loop
    for k in pairs(QPS_SavedProgress) do
        prevSavedProgress[k] = QPS_SavedProgress[k]
        if lastProgress[k] == nil then 
            LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: REMOVING key='..tostring(k)..' (not in lastProgress)')
            QPS_SavedProgress[k] = nil 
        end
    end
    -- Add/update keys from lastProgress
    for k, v in pairs(lastProgress) do
        LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: Checking key='..tostring(k)..' value='..tostring(v))
        if type(v) == "string" and StringLib.Find(v, "%d+/%d+") then
            QPS_SavedProgress[k] = v
            LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: SAVED key='..tostring(k)..' value='..tostring(v))
        elseif v == "Quest completed" then
            local prev = nil
            if type(prevSavedProgress[k]) == "string" and StringLib.Find(prevSavedProgress[k], "%d+/%d+") then
                prev = prevSavedProgress[k]
            end
            if prev then
                QPS_SavedProgress[k] = prev
                LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: RESTORED previous numeric for key='..tostring(k)..' value='..tostring(prev))
            else
                LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: SKIPPED completed key='..tostring(k)..' (no previous numeric)')
            end
        else
            LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: SKIPPED key='..tostring(k)..' value='..tostring(v))
        end
        -- Never store "Quest completed" in QPS_SavedProgress
    end
    LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: QPS_SavedProgress AFTER:')
    for k,v in pairs(QPS_SavedProgress) do LogDebugMessage(QPS_CoreDebugLog, 'QPS_SavedProgress['..tostring(k)..'] = '..tostring(v)) end
    LogDebugMessage(QPS_CoreDebugLog, 'SyncSavedProgress: END')
end

-- Removes all lastProgress and QPS_SavedProgress entries for a given quest (by title)
local function RemoveAllProgressForQuest(title)
    -- Removes all progress and session state for a given quest title from lastProgress, QPS_SavedProgress, and sentProgressThisSession
    if not title then return end
    local titleLen = StringLib.Len(title)
    -- Remove from lastProgress
    for k in pairs(lastProgress) do
        if StringLib.Sub(k, 1, titleLen + 1) == (title .. "-") or k == (title .. "-COMPLETE") then
            lastProgress[k] = nil
        end
    end
    -- Remove from QPS_SavedProgress
    if QPS_SavedProgress then
        for k in pairs(QPS_SavedProgress) do
            if StringLib.Sub(k, 1, titleLen + 1) == (title .. "-") or k == (title .. "-COMPLETE") then
                LogDebugMessage(QPS_CoreDebugLog, '[QPS-FIX] RemoveAllProgressForQuest: Removing QPS_SavedProgress['..k..'] for quest '..title)
                QPS_SavedProgress[k] = nil
            end
        end
    end
    -- Remove from sentProgressThisSession
    for k in pairs(sentProgressThisSession) do
        if StringLib.Sub(k, 1, titleLen + 1) == (title .. "-") or k == (title .. "-COMPLETE") then
            sentProgressThisSession[k] = nil
            LogDebugMessage(QPS_CoreDebugLog, '[QPS-FIX] RemoveAllProgressForQuest: Removing sentProgressThisSession['..k..'] for quest '..title)
        end
    end
    -- Remove completed suppression for this quest so re-accepting allows completion message again
    sentCompleted[title] = nil
end

--------------------------------------------------
-- QUEST LOG UPDATE & EVENT HANDLING
--------------------------------------------------
-- Helper: Quest log update logic, called from both QUEST_LOG_UPDATE and QUEST_ITEM_UPDATE
local function HandleQuestLogUpdate()
    -- Handles all quest log update logic, including progress/completion detection, silent refresh, and party sync. Called from both QUEST_LOG_UPDATE and QUEST_ITEM_UPDATE events.
    LogDebugMessage(QPS_CoreDebugLog, '[QPS-DEBUG]: HandleQuestLogUpdate start, lastProgress:')
    for k,v in pairs(lastProgress) do LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: lastProgress ' .. k .. ' = ' .. tostring(v)) end
    if AnyQuestLogHeadersCollapsed() then
        LogDebugMessage(QPS_EventDebugLog, "[QPS-WARN] Quest log headers are collapsed; progress tracking paused. User action required.")
        if not QPS._notifiedCollapsed then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cffb48affQuestProgressShare:|r Quest tracking paused. " ..
                "Please expand all quest log headers for accurate progress sharing!"
            )
            QPS._notifiedCollapsed = true
        end
        QPS._pendingSilentRefresh = true
        return
    else
        QPS._notifiedCollapsed = false
    end
    if QPS._suppressInitialProgress then
        LogDebugMessage(QPS_CoreDebugLog, '[QPS-FIX] Suppressing progress messages during initial scan (QPS._suppressInitialProgress = true)')
        -- Only update the cache, do not send progress messages
        local currentSnapshot = BuildQuestLogSnapshot()
        for k in pairs(questLogCache) do questLogCache[k] = nil end
        for k, v in pairs(currentSnapshot) do questLogCache[k] = v end
        -- Also update lastProgress to match snapshot
        DummyQuestProgressScan()
        return
    end
    -- If a silent refresh is pending, update cache and check for new quests
    local foundNewQuest = false
    if QPS._pendingSilentRefresh then
        LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Silent refresh triggered due to collapsed headers or entering world.")
        local currentSnapshot = BuildQuestLogSnapshot()
        LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: HandleQuestLogUpdate currentSnapshot:')
        for hash, data in pairs(currentSnapshot) do
            LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: currentSnapshot ' .. hash .. ' ' .. tostring(data.title) .. ' ' .. tostring(data.level))
            if data.objectives then
                for i, obj in ipairs(data.objectives) do
                    LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG:   obj ' .. i .. ' ' .. tostring(obj.text) .. ' ' .. tostring(obj.finished))
                end
            end
        end
        -- Compare current snapshot to QPS_SavedKnownQuests (from before headers were expanded)
        if QPS_SavedKnownQuests then
            for hash, data in pairs(currentSnapshot) do
                local debugMsg = "QPS Debug (SilentRefresh): Checking quest for 'accepted': "..(data.title or hash)
                if not QPS_SavedKnownQuests[data.title] then
                    if QuestProgressShareConfig.sendStartingQuests then
                        LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] "..debugMsg.." | Not in saved known quests: SENDING 'Quest accepted'")
                        SendQuestMessage(data.title, "Quest accepted", false)
                    else
                        LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] "..debugMsg.." | Not in saved known quests: SKIP due to config.sendStartingQuests=false")
                    end
                    foundNewQuest = true
                else
                    LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] "..debugMsg.." | In saved known quests: SKIP")
                end
            end
        end
        -- If a new quest was found, force update QPS_SavedKnownQuests
        if foundNewQuest then
            if QPS_SavedKnownQuests then
                for k in pairs(QPS_SavedKnownQuests) do QPS_SavedKnownQuests[k] = nil end
            else
                QPS_SavedKnownQuests = {}
            end
            for hash, data in pairs(currentSnapshot) do
                QPS_SavedKnownQuests[data.title] = true
            end
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] QPS_SavedKnownQuests force-updated after new quest detected.")
        end
        -- Update the cache as usual
        for k in pairs(questLogCache) do questLogCache[k] = nil end
        for k, v in pairs(currentSnapshot) do questLogCache[k] = v end
        QPS._pendingSilentRefresh = false
        LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Silent cache refresh after headers expanded (with new quest detection).")
        -- Ensure up-to-date progress is broadcast: update lastProgress and QPS_SavedProgress before broadcasting
        DummyQuestProgressScan()
        SyncSavedProgress()
        QPS.Tooltip.BroadcastPartyProgress()
        return
    end
    if not QPS.ready then return end
    if not QPS.knownQuests then QPS.knownQuests = {} end

    local currentSnapshot = BuildQuestLogSnapshot()
    -- Diff with previous cache (Questie style)
    local changes = {}
    -- Detect new quests (accepted)
    for hash, newData in pairs(currentSnapshot) do
        local debugMsg = "Checking quest for 'accepted': "..(newData.title or hash)
        if not questLogCache[hash] and (not QPS_SavedKnownQuests or not QPS_SavedKnownQuests[newData.title]) then
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Quest accepted: " .. tostring(newData.title))
            table.insert(changes, { type = "added", hash = hash, data = newData })
            foundNewQuest = true
            if QPS_SavedKnownQuests then
                QPS_SavedKnownQuests[newData.title] = true
            else
                QPS_SavedKnownQuests = { [newData.title] = true }
            end
        elseif not questLogCache[hash] then
            LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] "..debugMsg.." | Not in cache but IS in saved known quests: SKIP")
        elseif not QPS_SavedKnownQuests or not QPS_SavedKnownQuests[newData.title] then
            LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] "..debugMsg.." | In cache but NOT in saved known quests: SKIP")
        else
            LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] "..debugMsg.." | In both cache and saved known quests: SKIP")
        end
    end
    -- Detect removed quests (abandoned or completed and instantly removed)
    for hash, oldData in pairs(questLogCache) do
        if not currentSnapshot[hash] then
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Quest removed: " .. tostring(oldData.title))
            table.insert(changes, { type = "removed", hash = hash, data = oldData })
        end
    end
    -- Detect progress/completion
    for hash, newData in pairs(currentSnapshot) do
        local oldData = questLogCache[hash]
        LogDebugMessage(
            QPS_CoreDebugLog,
            "[QPS-DEBUG] Diff loop - hash: " .. tostring(hash) ..
            ", newData.title: " .. tostring(newData.title) ..
            ", oldData: " .. (oldData and oldData.title or "nil")
        )
        if oldData then
            LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] Checking completion for newData.title='" .. tostring(newData.title) .. ", completedQuestTitle='" .. tostring(completedQuestTitle) .. "'")
            if completedQuestTitle and newData.title == completedQuestTitle then
                LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Quest completed: " .. tostring(newData.title))
                table.insert(changes, { type = "completed", hash = hash, data = newData })
            else
                -- Progress: robustly match objectives by text, update all keys to reflect current order
                local numObjectives = GetTableLength(newData.objectives)
                -- Build a reverse map: text -> key for all lastProgress keys for this quest
                local textToKeyMap = {}
                local prefix = (newData.title or "") .. "-"
                local prefixLen = StringLib.Len(prefix)
                for k, v in pairs(lastProgress) do
                    if StringLib.Sub(k, 1, prefixLen) == prefix then
                        if type(v) == "string" and v ~= "Quest completed" then
                            textToKeyMap[v] = k
                        end
                    end
                end
                -- Track which old keys were matched, so we can update them after
                for i = 1, numObjectives do
                    local obj = newData.objectives[i]
                    local questKey = nil
                    -- Try to find a matching key in lastProgress by text (regardless of index)
                    if obj.text and textToKeyMap[obj.text] then
                        questKey = textToKeyMap[obj.text]
                    else
                        questKey = (newData.title or "") .. "-" .. i
                    end
                    local isMeaningless = false
                    if type(obj.text) ~= "string" then
                        isMeaningless = true
                    elseif StringLib.Sub(obj.text, 1, 3) == " : " then
                        -- Objective text starts with " : ", which is considered meaningless (e.g., blank or placeholder)
                        isMeaningless = true
                    else
                        local current = StringLib.SafeExtractNumbers(obj.text, QPS_LogToGroup)
                        if not current or tonumber(current) == 0 then
                            -- No progress number found, or progress is zero (e.g., "0/1" or nil)
                            isMeaningless = true
                        end
                    end
                    -- Debug: Log state before progress message decision
                    LogDebugMessage(QPS_CoreDebugLog, '[QPS-DEBUG] Progress check for questKey=' .. tostring(questKey) .. ', lastProgress=' .. tostring(lastProgress[questKey]) .. ', obj.text=' .. tostring(obj.text) .. ', isMeaningless=' .. tostring(isMeaningless))
                    if obj.finished then
                        if lastProgress[questKey] ~= obj.text and lastProgress[questKey] ~= "Quest completed" then
                            LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: SENDING progress ' .. questKey .. ' ' .. tostring(obj.text))
                            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Objective progress: " .. questKey .. " changed from '" .. tostring(lastProgress[questKey]) .. "' to '" .. tostring(obj.text) .. "'")
                            -- Instead of sending the message directly, record the change in the changes table
                            LogDebugMessage(QPS_CoreDebugLog, '[QPS-DEBUG] Recording progress change for ' .. questKey .. ' ' .. tostring(obj.text))
                            table.insert(changes, {
                                type = "progress",
                                title = newData.title,
                                text = obj.text,
                                finished = obj.finished,
                                questIndex = newData.questIndex,
                                objectiveIndex = i
                            })
                            lastProgress[questKey] = obj.text -- Prevent repeated sending of final progress
                        end
                        if lastProgress[questKey] ~= "Quest completed" then
                            LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: Marking as completed ' .. questKey)
                            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Objective completed: " .. questKey)
                            lastProgress[questKey] = "Quest completed"
                        end
                    else
                        -- Unified progress update block: record progress if changed and not meaningless
                        if lastProgress[questKey] ~= obj.text then
                            LogDebugMessage(QPS_CoreDebugLog, '[QPS-DEBUG] SENDING progress ' .. questKey .. ' ' .. tostring(obj.text) .. ' | isMeaningless=' .. tostring(isMeaningless) .. ', sendOnlyFinished=' .. tostring(QuestProgressShareConfig.sendOnlyFinished) .. ', completedQuestTitle=' .. tostring(completedQuestTitle))
                            if not isMeaningless
                                and (not completedQuestTitle or completedQuestTitle ~= newData.title)
                            then
                                LogDebugMessage(QPS_CoreDebugLog, '[QPS-DEBUG] Recording progress change for ' .. questKey .. ' ' .. tostring(obj.text))
                                LogDebugMessage(QPS_EventDebugLog, '[QPS-INFO] Objective progress: ' .. questKey .. " changed from '" .. tostring(lastProgress[questKey]) .. "' to '" .. tostring(obj.text) .. "'")
                                table.insert(changes, {
                                    type = "progress",
                                    title = newData.title,
                                    text = obj.text,
                                    finished = obj.finished,
                                    questIndex = newData.questIndex,
                                    objectiveIndex = i
                                })
                            else
                                LogDebugMessage(QPS_CoreDebugLog, '[QPS-DEBUG] Progress NOT recorded for ' .. questKey .. ' due to isMeaningless or completedQuestTitle')
                            end
                            lastProgress[questKey] = obj.text
                        end
                    end
                    -- After processing, always update the key for this objective to match the current text and index
                    lastProgress[(newData.title or "") .. "-" .. i] = obj.text
                end
                -- After processing all objectives, remap lastProgress keys for this quest to match current objectives
                -- Build a set of valid keys for this quest
                local validKeys = {}
                for i = 1, numObjectives do
                    local obj = newData.objectives[i]
                    local questKey = (newData.title or "") .. "-" .. i
                    validKeys[questKey] = true
                    -- If the current key does not match the text, update it
                    if lastProgress[questKey] ~= obj.text and obj.text ~= nil and obj.text ~= "" then
                        lastProgress[questKey] = obj.text
                    end
                end
                -- Remove any stale keys for this quest (wrong index or no longer present)
                local prefix = (newData.title or "") .. "-"
                for k in pairs(lastProgress) do
                    if StringLib.Sub(k, 1, StringLib.Len(prefix)) == prefix and not validKeys[k] then
                        lastProgress[k] = nil
                    end
                end
            end
        end
    end
    -- Only process if there are real changes
    if GetTableLength(changes) > 0 then
        LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Changes detected: " .. GetTableLength(changes))
        for _, change in ipairs(changes) do
            local data = change.data or {}
            LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Processing change type: "..tostring(change.type)..", data.title: "..tostring(data.title))
            if change.type == "added" then
                -- Always broadcast to addon channel for party sync
                QPS.Tooltip.BroadcastQuestUpdate(data.title, "Quest accepted", false, "", "quest accepted")
                -- Immediately broadcast all objectives for the new quest
                if data.objectives then
                    for i, obj in ipairs(data.objectives) do
                        if obj.text and obj.text ~= "" then
                            QPS.Tooltip.BroadcastQuestUpdate(data.title, obj.text, obj.finished, i, "initial objective")
                        end
                    end
                end
                -- Only send normal chat message if enabled
                if QuestProgressShareConfig.sendStartingQuests then
                    SendQuestMessage(data.title, "Quest accepted", false, nil, nil, true)
                end
                DummyQuestProgressScan()
                SyncSavedProgress()
            elseif change.type == "completed" then
                SendQuestMessage(data.title, "Quest completed", true)
                QPS.Tooltip.BroadcastQuestCompleted(data.title)
                RemoveAllProgressForQuest(data.title)
                -- Always remove from known quests so re-accepting triggers 'Quest accepted' for repeatable/chain quests
                if QPS_SavedKnownQuests then QPS_SavedKnownQuests[data.title] = nil end
                if QPS.knownQuests then QPS.knownQuests[data.title] = nil end
                SyncSavedProgress()
            elseif change.type == "progress" then
                -- Only send progress if the objective is finished or config allows unfinished
                local progressTitle = change.title or data.title
                if change.finished or not QuestProgressShareConfig.sendOnlyFinished then
                    LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Progress sent for " .. (progressTitle or "<nil>") .. "-" .. tostring(change.objectiveIndex) .. ": '" .. tostring(change.text) .. "'")
                    SendQuestMessage(progressTitle, change.text, change.finished, change.questIndex, change.objectiveIndex)
                    -- Broadcast progress update to party
                    QPS.Tooltip.BroadcastQuestUpdate(progressTitle, change.text, change.finished, change.objectiveIndex, "progress")
                else
                    LogDebugMessage(QPS_EventDebugLog, "[QPS-INFO] Progress not sent for " .. (progressTitle or "<nil>") .. "-" .. tostring(change.objectiveIndex) .. " due to sendOnlyFinished setting.")
                end
                SyncSavedProgress()
            elseif change.type == "removed" then
                if completedQuestTitle and data.title == completedQuestTitle then
                    SendQuestMessage(data.title, "Quest completed", true)
                    QPS.Tooltip.BroadcastQuestCompleted(data.title)
                    RemoveAllProgressForQuest(data.title)
                else
                    -- Send abandoned message if not completed and config allows
                    if QuestProgressShareConfig.sendAbandoned then
                        SendQuestMessage(data.title, "Quest abandoned", false)
                    end
                    QPS.Tooltip.BroadcastQuestAbandoned(data.title)
                end
                -- Always remove from known quests so re-accepting triggers 'Quest accepted' for repeatable/chain quests
                if QPS_SavedKnownQuests then QPS_SavedKnownQuests[data.title] = nil end
                if QPS.knownQuests then QPS.knownQuests[data.title] = nil end
                RemoveAllProgressForQuest(data.title)
                SyncSavedProgress()
            end
        end
    end

    -- Update questLogCache in place to preserve reference
    for k in pairs(questLogCache) do
        if not currentSnapshot[k] then questLogCache[k] = nil end
    end
    for k, v in pairs(currentSnapshot) do
        questLogCache[k] = v
    end
    -- Detailed objective progress diff logging
    for hash, newData in pairs(currentSnapshot) do
        local oldData = questLogCache[hash]
        if oldData then
            local numObjectives = GetTableLength(newData.objectives)
            for i = 1, numObjectives do
                local obj = newData.objectives[i]
                local oldObj = oldData.objectives and oldData.objectives[i] or nil
                LogDebugMessage(QPS_CoreDebugLog, "[QPS-DEBUG] Objective diff for " .. (newData.title or hash) .. " [" .. i .. "]: old='" .. tostring(oldObj and oldObj.text or "<nil>") .. "', new='" .. tostring(obj and obj.text or "<nil>") .. "', finished=" .. tostring(obj and obj.finished))
            end
        end
    end
end

-- Main event handler for all registered events
function OnEvent()
    -- Main event handler for all registered events: dispatches logic for quest log updates, login, entering world, and more
    LogDebugMessage('QPS DEBUG: OnEvent ' .. tostring(event) .. ' ' .. tostring(arg1))
    -- Log every event received for debugging
    LogDebugMessage("[QPS-INFO] Event received: " .. tostring(event) .. (arg1 and (", arg1: " .. tostring(arg1)) or ""))
    -- Quest turn-in: triggered when the quest completion window is opened
    if event == "QUEST_COMPLETE" then
        if GetTitleText then
            completedQuestTitle = GetTitleText()
        end
        return

    -- Player login: initialize known quests, print loaded message, and set up debug logs
    elseif event == "PLAYER_LOGIN" then
        LogDebugMessage('QPS DEBUG: On PLAYER_LOGIN, QPS_SavedProgress:')
        if QPS_SavedProgress then for k,v in pairs(QPS_SavedProgress) do LogDebugMessage('QPS DEBUG: QPS_SavedProgress ' .. k .. ' = ' .. tostring(v)) end end

        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffb48affQuestProgressShare|r loaded.")
        end
        if pfDB then
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffb48affQuestProgressShare: pfQuest integration enabled!|r")
            end
        end

        -- Clear all debug logs at the start of every session
        QPS_DebugLog = {}
        QPS_CoreDebugLog = {}
        QPS_EventDebugLog = {}
        QPS_ProgressDebugLog = {}
        QPS_SyncDebugLog = {}
        QPS_ConfigDebugLog = {}

        -- Initialize known quests from SavedVariables
        if not QPS_SavedKnownQuests then QPS_SavedKnownQuests = {} end
        QPS.knownQuests = {}
        for k, v in pairs(QPS_SavedKnownQuests) do QPS.knownQuests[k] = v end

        -- Load last progress from SavedVariables
        if not QPS_SavedProgress then QPS_SavedProgress = {} end
        for k, v in pairs(QPS_SavedProgress) do lastProgress[k] = v end

        -- Increment load count after login
        if QPS_SavedLoadCount == nil then QPS_SavedLoadCount = 0 end
        QPS_SavedLoadCount = QPS_SavedLoadCount + 1

        -- If headers are collapsed at login, load cache from saved progress and set silent refresh
        if AnyQuestLogHeadersCollapsed() then
            LoadCacheFromSavedProgress()
            QPS._pendingSilentRefresh = true
        else
            QPS._pendingSilentRefresh = false
        end
        -- On first load ever, do a dummy scan and update saved variables, but do not send messages
        QPS._didFirstLoadInit = false
        if IsFirstLoadEver() then
            QPS._didFirstLoadInit = true
        end
        sentCompleted = {}
        LogDebugMessage('QPS DEBUG: On PLAYER_LOGIN, lastProgress after load:')
        for k,v in pairs(lastProgress) do LogDebugMessage('QPS DEBUG: lastProgress ' .. k .. ' = ' .. tostring(v)) end
        return

    -- Addon loaded: set default config and update config UI
    elseif event == "ADDON_LOADED" and arg1 == "QuestProgressShare" then
        QPS.config.SetDefaultConfigValues()
        UpdateConfigFrame()
        return

    -- Entering world: delay quest log scanning until fully loaded, then initialize state
    elseif event == "PLAYER_ENTERING_WORLD" then
        LogDebugMessage('QPS DEBUG: On PLAYER_ENTERING_WORLD, lastProgress before DummyQuestProgressScan:')
        for k,v in pairs(lastProgress) do LogDebugMessage('QPS DEBUG: lastProgress ' .. k .. ' = ' .. tostring(v)) end
        QPS.ready = false
        if not QPS.delayFrame then
            QPS.delayFrame = CreateFrame("Frame")
        end
        QPS.delayFrame.elapsed = 0
        QPS.delayFrame.startTime = time()
        QPS.delayFrame:SetScript("OnUpdate", function()
            local now = time()
            if (now - QPS.delayFrame.startTime) >= 3 then
                QPS.ready = true
                QPS.delayFrame:SetScript("OnUpdate", nil)

                -- If headers are collapsed at entering world, set pending silent refresh
                if AnyQuestLogHeadersCollapsed() then
                    QPS._pendingSilentRefresh = true
                else
                    QPS._pendingSilentRefresh = false
                end

                -- Take initial snapshot for cache
                local initialSnapshot = BuildQuestLogSnapshot()
                for k in pairs(questLogCache) do questLogCache[k] = nil end
                for k, v in pairs(initialSnapshot) do questLogCache[k] = v end

                -- Suppress progress messages during initial scan
                QPS._suppressInitialProgress = true
                -- On first load ever, do a dummy scan and update saved variables, but do not send messages
                if QPS._didFirstLoadInit then
                    DummyQuestProgressScan()

                    -- Save lastProgress to SavedVariables (clear old data first)
                    LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: PLAYER_ENTERING_WORLD: QPS_SavedProgress BEFORE:')
                    if QPS_SavedProgress then for k,v in pairs(QPS_SavedProgress) do LogDebugMessage(QPS_CoreDebugLog, 'QPS_SavedProgress['..tostring(k)..'] = '..tostring(v)) end end
                    -- Use SyncSavedProgress to handle saving logic
                    SyncSavedProgress()
                    LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: PLAYER_ENTERING_WORLD: QPS_SavedProgress AFTER:')
                    if QPS_SavedProgress then for k,v in pairs(QPS_SavedProgress) do LogDebugMessage(QPS_CoreDebugLog, 'QPS_SavedProgress['..tostring(k)..'] = '..tostring(v)) end end

                    -- Also update known quests
                    for questIndex = 1, QPSGet_NumQuestLogEntries() do
                        local title, _, _, isHeader = QPSGet_QuestLogTitle(questIndex)
                        if not isHeader and title then
                            QPS.knownQuests[title] = true
                        end
                    end

                    if QPS_SavedKnownQuests then
                        for k in pairs(QPS_SavedKnownQuests) do QPS_SavedKnownQuests[k] = nil end
                    else
                        QPS_SavedKnownQuests = {}
                    end
                    for k, v in pairs(QPS.knownQuests) do
                        QPS_SavedKnownQuests[k] = v
                    end

                    -- Mark first-load initialization as complete
                    QPS._didFirstLoadInit = false
                else
                    DummyQuestProgressScan() -- Populates lastProgress for any new quests
                end
                QPS._suppressInitialProgress = false
                LogDebugMessage('QPS DEBUG: On PLAYER_ENTERING_WORLD, lastProgress after DummyQuestProgressScan:')
                for k,v in pairs(lastProgress) do LogDebugMessage('QPS DEBUG: lastProgress ' .. k .. ' = ' .. tostring(v)) end
            end
        end)
        return

    -- Quest item update: triggers quest log update logic for quest item changes
    elseif event == "QUEST_ITEM_UPDATE" then
        LogDebugMessage("[QPS-INFO] HandleQuestLogUpdate triggered by QUEST_ITEM_UPDATE")
        HandleQuestLogUpdate()
        return

    -- Quest log update: detects quest accept, completion, and progress
    elseif event == "QUEST_LOG_UPDATE" and QuestProgressShareConfig.enabled == 1 then
        LogDebugMessage("[QPS-INFO] HandleQuestLogUpdate triggered by QUEST_LOG_UPDATE")
        HandleQuestLogUpdate()

    -- Player logout: saves progress and known quests
    elseif event == "PLAYER_LOGOUT" then
        LogDebugMessage('QPS DEBUG: On PLAYER_LOGOUT, lastProgress:')
        for k,v in pairs(lastProgress) do LogDebugMessage('QPS DEBUG: lastProgress ' .. k .. ' = ' .. tostring(v)) end

        -- Only update and save known quests if all headers are expanded
        if not AnyQuestLogHeadersCollapsed() then
            local snapshot = BuildQuestLogSnapshot()
            if QPS_SavedKnownQuests then
                for k in pairs(QPS_SavedKnownQuests) do QPS_SavedKnownQuests[k] = nil end
            else
                QPS_SavedKnownQuests = {}
            end
            for _, data in pairs(snapshot) do
                QPS_SavedKnownQuests[data.title] = true
            end
        end

        -- Save lastProgress to QPS_SavedProgress on logout only
        LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: PLAYER_LOGOUT: QPS_SavedProgress BEFORE:')
        if QPS_SavedProgress then for k,v in pairs(QPS_SavedProgress) do LogDebugMessage(QPS_CoreDebugLog, 'QPS_SavedProgress['..tostring(k)..'] = '..tostring(v)) end end
        -- Use SyncSavedProgress to handle saving logic
        SyncSavedProgress()
        LogDebugMessage(QPS_CoreDebugLog, 'QPS DEBUG: PLAYER_LOGOUT: QPS_SavedProgress AFTER:')
        if QPS_SavedProgress then for k,v in pairs(QPS_SavedProgress) do LogDebugMessage(QPS_CoreDebugLog, 'QPS_SavedProgress['..tostring(k)..'] = '..tostring(v)) end end
        return
    end
end

--------------------------------------------------
-- EVENT REGISTRATION
--------------------------------------------------
QPS:RegisterEvent("QUEST_LOG_UPDATE")
QPS:RegisterEvent("PLAYER_LOGIN")
QPS:RegisterEvent("ADDON_LOADED")
QPS:RegisterEvent("PLAYER_ENTERING_WORLD")
QPS:RegisterEvent("QUEST_COMPLETE")
QPS:RegisterEvent("PLAYER_LOGOUT")
QPS:RegisterEvent("QUEST_ITEM_UPDATE")
QPS:SetScript("OnEvent", OnEvent)