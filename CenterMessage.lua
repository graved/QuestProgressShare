local QPS = QuestProgressShare
QPS.centerMessage = {}

-- Frame erstellen, um die Nachricht anzuzeigen
QPS.centerMessage.frame = CreateFrame("Frame", "QuestProgressShareCenterMessageFrame", UIParent)
QPS.centerMessage.frame:SetWidth(400) -- Breite und Höhe des Frames
QPS.centerMessage.frame:SetHeight(50) -- Breite und Höhe des Frames
QPS.centerMessage.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) -- Mittig auf dem Bildschirm

-- FontString für den Text erstellen
QPS.centerMessage.text = QPS.centerMessage.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
QPS.centerMessage.text:SetPoint("CENTER", QPS.centerMessage.frame, "CENTER", 0, 0)
QPS.centerMessage.text:SetTextColor(1, 0, 0) -- Textfarbe (rot)
QPS.centerMessage.text:SetText("") -- Startet leer
QPS.centerMessage.frame:Hide() -- Zu Beginn verstecken

function QPS.centerMessage.ShowMessage(text, duration)
    if (QuestProgressShareConfig.centerMessage) then
        QPS.centerMessage.text:SetText(text)
        QPS.centerMessage.frame:Show()
        -- Timer mit Chronos setzen
        Chronos.schedule(duration or 3, function()
            QPS.centerMessage.frame:Hide()
            QPS.centerMessage.text:SetText("")
        end)
    end    
end
