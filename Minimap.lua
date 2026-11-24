-- =============================================
-- Иконка у мини-карты (без библиотек).
-- ЛКМ — настройки, ПКМ — тест-режим, Shift+ЛКМ — закрепить/открепить, тянуть — двигать по кругу.
-- =============================================
local ADDON, ns = ...

local ICON = "Interface\\Icons\\Ability_Rogue_SliceDice"
local btn

local function UpdatePos()
    if not btn then return end
    local a = math.rad(EnergyTickSettings.minimapAngle or 215)
    local x, y = math.cos(a), math.sin(a)
    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    else
        x, y = x * w, y * h
    end
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local s = Minimap:GetEffectiveScale()
    px, py = px / s, py / s
    EnergyTickSettings.minimapAngle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePos()
end

local function Create()
    btn = CreateFrame("Button", "RogueTickMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(20, 20); bg:SetPoint("TOPLEFT", 7, -5)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17); icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ICON); icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53); border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    btn:SetScript("OnMouseDown", function() icon:SetPoint("TOPLEFT", 8, -7) end)
    btn:SetScript("OnMouseUp", function() icon:SetPoint("TOPLEFT", 7, -6) end)

    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight(); self:SetScript("OnUpdate", DragUpdate)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:UnlockHighlight(); self:SetScript("OnUpdate", nil)
        icon:SetPoint("TOPLEFT", 7, -6)
    end)

    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ns.SetTest(not ns.testMode)
            print("|cffffff00RogueTick:|r тест-режим "..(ns.testMode and "ВКЛ" or "ВЫКЛ"))
        elseif IsShiftKeyDown() then
            ns.SetLocked(not EnergyTickSettings.locked)
            print("|cffffff00RogueTick:|r "..(EnergyTickSettings.locked and "фреймы закреплены" or "фреймы можно двигать"))
        else
            ns.ToggleConfig()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Rogue Tick", 1, 0.82, 0.2)
        GameTooltip:AddLine("ЛКМ — настройки", 1, 1, 1)
        GameTooltip:AddLine("ПКМ — тест-режим", 1, 1, 1)
        GameTooltip:AddLine("Shift+ЛКМ — "..(EnergyTickSettings.locked and "открепить фреймы" or "закрепить фреймы"), 1, 1, 1)
        GameTooltip:AddLine("Перетащите, чтобы сдвинуть иконку", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ns.ApplyMinimap()
    if EnergyTickSettings.minimapHide then
        if btn then btn:Hide() end
        return
    end
    if not btn then Create() end
    btn:Show(); UpdatePos()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    ns.ApplyMinimap()
    self:UnregisterEvent("PLAYER_LOGIN")
end)
