-- Commands.lua: Registers and handles slash commands and user input for QuestProgressShare.
-- Provides user-facing command interface for configuration and debugging.

local QPS = QuestProgressShare

-- Slash command to open the config frame
SLASH_QUESTPROGRESSSHARE1 = "/qps"
SlashCmdList["QUESTPROGRESSSHARE"] = function()
    if QPS.configFrame:IsShown() then
        QPS.configFrame:Hide()
    else
        QPS.configFrame:Show()
    end
end
