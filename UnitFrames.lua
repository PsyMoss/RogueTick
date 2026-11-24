-- =============================================
-- Фреймы игрока и цели в стиле главной полосы.
--   Клик: ЛКМ — выбрать цель, ПКМ — меню юнита (защищённая кнопка Blizzard).
--   HP (зелёный / янтарный / красный), ресурс, каст-бар.
--   Агро: светящаяся рамка + надпись «АГРО», звук; на цели — % угрозы и цель цели.
--   Дебаффы: иконки с таймером, рамка цвета типа (яд / проклятие / болезнь / магия);
--   на игроке — неоновая рамка цвета снимаемого дебаффа.
--   Уровень/элитность, метка рейда, затенение цели вне досягаемости, подсказка при наведении.
-- WoW Forever: часть данных в бою секретная — такие значения уходят прямо в виджеты.
-- =============================================
local ADDON, ns = ...
local Read, issecret, SafeText = ns.Read, ns.issecret, ns.SetText

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BG = "Interface\\ChatFrame\\ChatFrameBackground"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Цвета фреймов — по стилю главной полосы (Монохром / Мягкий цвет).
-- Таблицы меняются на месте (ApplyStyle), поэтому ссылки на них везде живые.
local C_HOLD   = {0, 0, 0} -- HP высокое / канал
local C_WAIT   = {0, 0, 0} -- HP среднее / свой каст
local C_CAP    = {0, 0, 0} -- HP низкое / прервано
local C_KICK   = {0, 0, 0} -- каст цели, который можно сбить
local C_SELF   = {0, 0, 0} -- свой каст
local C_SECRET = {0.45, 0.45, 0.45} -- значение скрыто игрой
local C_LOCKED = {0.55, 0.55, 0.55} -- каст нельзя сбить
local C_DEAD   = {0.15, 0.15, 0.15}

local POWER_COLORS = { [0] = {0,0,0}, [1] = {0,0,0}, [2] = {0,0,0}, [3] = {0,0,0}, [6] = {0,0,0} }

local STYLES = {
    soft = { -- приглушённые, ничего не режет глаз
        hold = {0.42, 0.68, 0.46}, wait = {0.86, 0.62, 0.36}, cap = {0.78, 0.36, 0.34}, kick = ns.ACT.kick,
        self = {0.66, 0.58, 0.84}, -- свой каст: лавандовый, не путается с жёлтой энергией
        power = { [0] = {0.36, 0.52, 0.82}, [1] = {0.74, 0.36, 0.34}, [2] = {0.80, 0.58, 0.36},
                  [3] = {0.84, 0.74, 0.40}, [6] = {0.42, 0.66, 0.80} },
    },
    mono = { -- чем опаснее, тем светлее
        hold = {0.58, 0.58, 0.58}, wait = {0.78, 0.78, 0.78}, cap = {0.95, 0.95, 0.95}, kick = {0.70, 0.70, 0.70},
        self = {0.75, 0.75, 0.75},
        power = { [0] = {0.55, 0.55, 0.55}, [1] = {0.55, 0.55, 0.55}, [2] = {0.55, 0.55, 0.55},
                  [3] = {0.62, 0.62, 0.62}, [6] = {0.55, 0.55, 0.55} },
    },
}
local function Copy(dst, src) dst[1], dst[2], dst[3] = src[1], src[2], src[3] end
local function ApplyStyle()
    local st = STYLES[EnergyTickSettings and EnergyTickSettings.barStyle] or STYLES.mono
    Copy(C_HOLD, st.hold); Copy(C_WAIT, st.wait); Copy(C_CAP, st.cap); Copy(C_KICK, st.kick); Copy(C_SELF, st.self)
    for k, c in pairs(st.power) do Copy(POWER_COLORS[k], c) end
end
ApplyStyle()

-- Единый блок: фрейм игрока = полоса жизни прямо над полосой энергии
local function Docked() return UF_Settings.dock ~= false end

local DebuffColors = {
    Magic   = {0.20, 0.60, 1.00},
    Curse   = {0.60, 0.00, 1.00},
    Disease = {0.60, 0.40, 0.00},
    Poison  = {0.00, 0.60, 0.00},
}
-- Яркие версии для неоновой рамки
local NeonColors = {
    Magic   = {0, 0.8, 1},
    Curse   = {0.8, 0, 1},
    Disease = {1, 0.5, 0},
    Poison  = {0, 1, 0},
}
local DISPEL_ORDER = { "Magic", "Curse", "Disease", "Poison" } -- Enum: 1..4

-- Угроза: 1 — высокая (скоро сорвёте), 2 — держите, но ненадёжно, 3 — бьют вас
local THREAT_COLORS = {
    [1] = {1.00, 0.90, 0.20},
    [2] = {1.00, 0.55, 0.00},
    [3] = {1.00, 0.10, 0.10},
}

local DEFAULTS = {
    v = 3, locked = true,
    width = 200, hpHeight = 20, powerHeight = 8, castHeight = 14,
    dock = true, dockHeight = 12, -- единый блок: жизнь над энергией
    targetSplit = true,  -- цель: раздельные полосы (инфо/каст, жизнь, ресурс)
    targetLink = true,   -- ширина цели = ширина моего блока
    tHpH = 16, tCastH = 13, tPowH = 4, -- цель по важности: жизнь главная, каст (Kick!) крупный, ресурс тонкий
    totWidth = 110,      -- ширина фрейма «цель цели»
    infoBar = true,      -- инфо-полоса на месте своего каста (каст её временно заменяет)
    aggroInInfo = true,  -- «АГРО» — в инфо-полосе, а не в полосе жизни
    px = -250, py = -150, tx = 250, ty = -150,
    showPlayer = true, showTarget = true, showPower = true, showCast = true,
    showText = true, shake = true,
    showTargetCast = true, showTargetText = true, -- у цели — свои галочки (каст, цифры жизни)
    hideBlizzPlayer = true, hideBlizzTarget = true, hideBlizzCast = true,
    aggro = true, aggroSound = true,
    showAuras = true, showTargetAuras = true, auraSize = 22, auraMax = 8, -- auraSize/auraMax — у цели
    playerAuraSize = 22, playerAuraMax = 8, -- иконки дебаффов на мне
    aggroSoundID = 8959, -- звук, когда мобы переключились на вас
    showToT = true, rangeFade = true,
}
UF_Settings = UF_Settings or {}
local function ApplyDefaults()
    local S = UF_Settings
    if S.v == nil or S.v < 2 then -- версия 1: квадраты 44x22 рядом с полосой -> новые размеры и места
        for _, k in ipairs({ "width", "height", "px", "py", "tx", "ty", "useIcons" }) do S[k] = nil end
        S.v = 2
    end
    if S.v < 3 then -- версия 3: единый блок (жизнь над энергией) включаем один раз
        S.dock, S.showPlayer = true, true
        S.v = 3
    end
    -- иконки дебаффов на мне стали отдельной настройкой: берём прежнюю общую
    if S.playerAuraSize == nil and S.auraSize then S.playerAuraSize = S.auraSize end
    if S.playerAuraMax == nil and S.auraMax then S.playerAuraMax = S.auraMax end
    for k, v in pairs(DEFAULTS) do if S[k] == nil then S[k] = v end end
end
ApplyDefaults()
ns.ApplyUFDefaults = ApplyDefaults

local function Flag(fn, ...)
    local v, ok = Read(fn, ...)
    return ok and v and true or false
end

-- =============================================
-- Отложенные защищённые действия (размер/позиция/показ кликабельных кнопок,
-- скрытие фреймов Blizzard): в бою игра их запрещает -> делаем после боя.
-- =============================================
local securePending = false
local function SecureOK()
    if InCombatLockdown() then
        if not securePending then print("|cffffff00RogueTick:|r часть изменений применится после боя") end
        securePending = true
        return false
    end
    return true
end

-- =============================================
-- Элементы стиля
-- =============================================
local function Box(fr, a)
    fr:SetBackdrop({ bgFile = BG, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    fr:SetBackdropColor(0, 0, 0, a or 1); fr:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    ns.Round(fr) -- скруглённые углы
end

local function Bar(parent, level)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(WHITE); b:SetMinMaxValues(0, 1); b:SetValue(1)
    b:SetFrameLevel(level)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(b); bg:SetColorTexture(1, 1, 1, 0.05)
    b.mask = ns.RoundFill(b, { bg })
    return b
end

local function Text(parent, size)
    local t = parent:CreateFontString(nil, "OVERLAY")
    ns.SetFont(t, size); t:SetTextColor(1, 1, 1); t:SetWordWrap(false)
    return t
end

local function SetColor(bar, c, a)
    if bar.col ~= c then bar.col = c; bar:SetStatusBarColor(c[1], c[2], c[3], a or 0.85) end
end

-- =============================================
-- КАСТ-БАР
-- =============================================
local function CreateCastBar(owner, unit)
    local c = CreateFrame("Frame", nil, owner, BACKDROP)
    c:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -3); c:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -3)
    Box(c, 0.9)
    c.unit = unit

    c.icon = c:CreateTexture(nil, "ARTWORK")
    c.icon:SetPoint("TOPLEFT", 1, -1); c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    ns.RoundTex(c, c, { c.icon }, -1) -- левые углы иконки повторяют скругление
    c.bar = Bar(c, c:GetFrameLevel() + 1)
    c.bar:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 1, 0); c.bar:SetPoint("BOTTOMRIGHT", -1, 1)

    c.spark = c.bar:CreateTexture(nil, "OVERLAY")
    c.spark:SetColorTexture(1, 1, 1, 0.9); c.spark:SetWidth(2)
    c.spark:SetPoint("TOP", c.bar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
    c.spark:SetPoint("BOTTOM", c.bar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)

    local top = CreateFrame("Frame", nil, c); top:SetAllPoints(c); top:SetFrameLevel(c:GetFrameLevel() + 3)
    c.time = Text(top, 10); c.time:SetPoint("RIGHT", c.bar, "RIGHT", -3, 0)
    c.name = Text(top, 10); c.name:SetPoint("LEFT", c.bar, "LEFT", 3, 0)
    c.name:SetPoint("RIGHT", c.time, "LEFT", -4, 0); c.name:SetJustifyH("LEFT")

    c:Hide()

    c:SetScript("OnUpdate", function(self)
        local now = GetTime()
        if self.holdUntil then
            if now >= self.holdUntil then self.holdUntil = nil; self:Hide()
            else self:SetAlpha((self.holdUntil - now) / 0.6) end
            return
        end
        if not self.active or self.timer then return end
        if now >= self.e then
            if self.fake then self.s, self.e = now, now + 2.5
            else self.active = false; self:Hide(); return end
        end
        local p = (now - self.s) / (self.e - self.s)
        self.bar:SetValue(self.channel and (1 - p) or p)
        self.time:SetFormattedText("%.1f", self.e - now)
        -- можно сбить: успеет ли Kick (иначе серый) и зона «поздно» в конце
        if self.kickable then
            local inTime = self.fake or ns.KickInTime(now, self.e)
            if inTime ~= self.kInTime then
                self.kInTime = inTime
                local col = inTime and C_KICK or C_LOCKED
                self.bar:SetStatusBarColor(col[1], col[2], col[3], 1)
            end
            if inTime then ns.KickZone(self.bar, self.s, self.e, self.channel) else ns.KickZoneHide(self.bar) end
        end
    end)
    return c
end

local function ReadCastInfo(fn, unit)
    if not fn then return nil end
    local ok, r = pcall(function() return { fn(unit) } end)
    if not ok then return nil end
    if issecret(r[1]) or r[1] ~= nil then return r end
    return nil
end

-- каст включён? у своего и у цели — отдельные галочки
local function CastOn(c)
    if c.unit == "target" then return UF_Settings.showTargetCast ~= false end
    return UF_Settings.showCast and true or false
end

local function CastHide(c)
    c.active, c.fake, c.kickable = false, false, false
    ns.KickZoneHide(c.bar)
    if not c.holdUntil then c:Hide() end
end

local function CastRefresh(c)
    if not CastOn(c) then c.holdUntil = nil; CastHide(c); return end
    if c.fake then return end
    local channel = false
    local r = ReadCastInfo(UnitCastingInfo, c.unit)
    if not r then r = ReadCastInfo(UnitChannelInfo, c.unit); channel = true end
    if not r then CastHide(c); return end

    c.holdUntil, c.channel = nil, channel
    SafeText(c.name, r[1], "")
    pcall(c.icon.SetTexture, c.icon, r[3])

    local col
    if c.unit == "player" then
        col = C_SELF
    else
        -- «нельзя сбить» может быть секретным: проверять его на истинность нельзя,
        -- поэтому без «a and b or c» — сначала проверка на секрет
        local ni
        if channel then ni = r[7] else ni = r[8] end
        col = C_KICK
        if not issecret(ni) and ni then col = C_LOCKED end
    end
    c.bar:SetStatusBarColor(col[1], col[2], col[3], 1)
    -- зона «поздно для Kick» — только у цели, только если каст можно сбить
    c.kickable = c.unit == "target" and col == C_KICK and ns.KickZoneOn()
    c.kInTime = true
    ns.KickZoneHide(c.bar)

    local s, e = r[4], r[5]
    if not issecret(s) and not issecret(e) and type(s) == "number" and type(e) == "number" and e > s then
        c.s, c.e, c.timer = s / 1000, e / 1000, false
        c.bar:SetMinMaxValues(0, 1)
    else
        c.s, c.e, c.timer = nil, nil, true
        c.time:SetText("")
        local durFn = channel and UnitChannelDuration or UnitCastingDuration
        if not (durFn and c.bar.SetTimerDuration) then CastHide(c); return end
        local ok = pcall(function()
            local d = durFn(c.unit)
            local dir = channel and Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
            if dir then
                if not pcall(c.bar.SetTimerDuration, c.bar, d, nil, dir) then c.bar:SetTimerDuration(d) end
            else
                c.bar:SetTimerDuration(d)
            end
        end)
        if not ok then CastHide(c); return end
    end
    c.active = true
    c:SetAlpha(1); c:Show()
end

local function CastInterrupted(c)
    if not c.active or c.fake then return end
    c.active, c.kickable = false, false
    ns.KickZoneHide(c.bar)
    c.bar:SetStatusBarColor(C_CAP[1], C_CAP[2], C_CAP[3], 1)
    c.bar:SetMinMaxValues(0, 1); c.bar:SetValue(1)
    c.name:SetText("Прервано"); c.time:SetText("")
    c.holdUntil = GetTime() + 0.6
end

local function CastFake(c, on)
    if on and CastOn(c) then
        local now = GetTime()
        c.fake, c.active, c.timer, c.holdUntil, c.channel = true, true, false, nil, false
        c.s, c.e = now, now + 2.5
        c.kickable, c.kInTime = c.unit == "target" and ns.KickZoneOn(), true
        local col = c.unit == "player" and C_SELF or C_KICK
        c.bar:SetStatusBarColor(col[1], col[2], col[3], 1)
        c.bar:SetMinMaxValues(0, 1)
        c.icon:SetTexture(QUESTION)
        c.name:SetText(c.unit == "player" and "Тестовый каст" or "Каст врага — Kick!")
        c:SetAlpha(1); c:Show()
    elseif c.fake then
        c.fake = false; c.active = false; c:Hide()
        CastRefresh(c)
    end
end

-- =============================================
-- ДЕБАФФЫ
-- =============================================
-- Если тип дебаффа скрыт игрой, красим через кривую цветов клиента (Midnight API)
local curves = {}
local function DispelCurve(noneAlpha)
    if curves[noneAlpha] ~= nil then return curves[noneAlpha] or nil end
    curves[noneAlpha] = false
    pcall(function()
        local c = C_CurveUtil.CreateColorCurve()
        if Enum and Enum.LuaCurveType then c:SetType(Enum.LuaCurveType.Step) end
        c:AddPoint(0, CreateColor(0.5, 0.5, 0.5, noneAlpha))
        for i, name in ipairs(DISPEL_ORDER) do
            local col = DebuffColors[name]
            c:AddPoint(i, CreateColor(col[1], col[2], col[3], 1))
        end
        c:AddPoint(5, CreateColor(0.5, 0.5, 0.5, noneAlpha)) -- ярость, кровотечение и пр.
        curves[noneAlpha] = c
    end)
    return curves[noneAlpha] or nil
end

-- r, g, b, a (могут быть секретными — только для сеттеров)
local function AuraColor(unit, a, noneAlpha)
    local dn = a.dispelName
    if not issecret(dn) then
        local c = dn and DebuffColors[dn]
        if c then return c[1], c[2], c[3], 1 end
        return 0.5, 0.5, 0.5, noneAlpha
    end
    local curve = DispelCurve(noneAlpha)
    if curve and C_UnitAuras.GetAuraDispelTypeColor then
        local ok, r, g, b, al = pcall(function()
            return C_UnitAuras.GetAuraDispelTypeColor(unit, a.auraInstanceID, curve):GetRGBA()
        end)
        if ok then return r, g, b, al end
    end
    return 0.5, 0.5, 0.5, noneAlpha
end

local AURA_SLOTS = 12

local function CreateAuraIcon(parent)
    local b = CreateFrame("Frame", nil, parent)
    b.border = b:CreateTexture(nil, "BACKGROUND"); b.border:SetAllPoints(b); b.border:SetTexture(WHITE)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon); b.cd:SetReverse(true); b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(false) end
    local top = CreateFrame("Frame", nil, b); top:SetAllPoints(b); top:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.count = Text(top, 10); b.count:SetPoint("BOTTOMRIGHT", 1, 0)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        if not self.auraID then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if not pcall(GameTooltip.SetUnitDebuffByAuraInstanceID, GameTooltip, self.unit, self.auraID, self.filter) then
            pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, self.unit, self.auraID, self.filter)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    return b
end

local function SetAuraIcon(b, unit, a, filter)
    b.unit, b.auraID, b.filter = unit, a.auraInstanceID, filter
    pcall(b.icon.SetTexture, b.icon, a.icon)
    local r, g, bl, al = AuraColor(unit, a, 1)
    pcall(b.border.SetVertexColor, b.border, r, g, bl, al)

    local d, e = a.duration, a.expirationTime
    if not issecret(d) and not issecret(e) then
        if type(d) == "number" and d > 0 and type(e) == "number" then
            b.cd:SetCooldown(e - d, d); b.cd:Show()
        else
            b.cd:Hide()
        end
    elseif not pcall(function()
            b.cd:SetCooldownFromDurationObject(C_UnitAuras.GetUnitAuraDuration(unit, a.auraInstanceID)); b.cd:Show()
        end) then
        b.cd:Hide()
    end

    local n = a.applications
    if not issecret(n) then
        b.count:SetText((type(n) == "number" and n > 1) and n or "")
    elseif not pcall(function()
            b.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, a.auraInstanceID, 2, 99))
        end) then
        b.count:SetText("")
    end
    b:Show()
end

local TEST_AURAS = { "Poison", "Curse", "Magic", "Disease" }

-- Иконки дебаффов + цвет неоновой рамки игрока
local function UpdateAuras(f)
    local S, unit = UF_Settings, f.unit
    local show = (unit == "player" and S.showAuras) or (unit == "target" and S.showTargetAuras)
    local maxN = math.min(((f.unit == "player") and S.playerAuraMax or S.auraMax) or 8, AURA_SLOTS)
    local n = 0
    f.neonColor, f.neonSecret = nil, nil

    if ns.testMode then
        if unit == "player" then f.neonColor = NeonColors.Poison end
        if show then
            for i = 1, math.min(unit == "player" and 3 or 4, maxN) do
                local b = f.auras[i]
                n = i
                if not b.fake then
                    b.fake, b.auraID = true, nil
                    b.icon:SetTexture(QUESTION)
                    local c = DebuffColors[TEST_AURAS[i]]
                    b.border:SetVertexColor(c[1], c[2], c[3], 1)
                    b.cd:SetCooldown(GetTime(), 15); b.cd:Show()
                    b.count:SetText(i == 1 and 3 or "")
                end
                b:Show()
            end
        end
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local filter = unit == "player" and "HARMFUL" or "HARMFUL|PLAYER"
        for i = 1, 40 do
            local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok or not a then break end
            if unit == "player" and not f.neonColor then
                local dn = a.dispelName
                if not issecret(dn) then
                    if dn and NeonColors[dn] then f.neonColor = NeonColors[dn] end
                elseif not f.neonSecret then
                    f.neonSecret = a -- тип скрыт: покрасим через кривую (прозрачно, если не снимается)
                end
            end
            if show and n < maxN then
                n = n + 1
                f.auras[n].fake = false
                SetAuraIcon(f.auras[n], unit, a, filter)
            end
            if not show and unit ~= "player" then break end
        end
    end
    for i = n + 1, AURA_SLOTS do f.auras[i].fake = false; f.auras[i]:Hide() end
    f.auraDirty, f.auraT = false, GetTime()
end

-- =============================================
-- ФРЕЙМ ЮНИТА
--   btn  — защищённая кликабельная кнопка (неподвижная, двигается мышью вне боя)
--   f    — видимая часть, привязана к кнопке; трясётся отдельно от неё
-- =============================================
local function CreateUnitFrame(key, unit, kx, ky)
    local btn = CreateFrame("Button", "RT_UF_"..key.."Button", UIParent, "SecureUnitButtonTemplate")
    btn:SetAttribute("unit", unit)
    btn:SetAttribute("*type1", "target")
    btn:SetAttribute("*type2", "togglemenu")
    btn:SetAttribute("shift-type2", "") -- Shift+ПКМ: без меню, открепить/закрепить фрейм
    btn:RegisterForClicks("AnyUp")
    local ukey = key:lower()
    -- В едином блоке фрейм игрока двигается вместе с главной полосой
    local function MoveKey() return (unit == "player" and Docked()) and "main" or ukey end
    btn:HookScript("PostClick", function(_, button)
        if button == "RightButton" and IsShiftKeyDown() then ns.ToggleUnlock(MoveKey()) end
    end)
    btn:SetFrameStrata("MEDIUM"); btn:SetClampedToScreen(true)
    btn:SetMovable(true); btn:RegisterForDrag("LeftButton")
    ClickCastFrames = ClickCastFrames or {} -- поддержка Clique и т.п.
    ClickCastFrames[btn] = true

    local f = CreateFrame("Frame", "RT_UF_"..key, UIParent, BACKDROP)
    f.unit, f.kx, f.ky, f.btn = unit, kx, ky, btn
    btn.visual = f
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(btn:GetFrameLevel() + 1)
    f:EnableMouse(false) -- клики проходят на кнопку
    Box(f, 1)
    local lvl = f:GetFrameLevel()

    btn:SetScript("OnDragStart", function(self)
        if not ns.IsMovable(MoveKey()) or InCombatLockdown() then return end
        if unit == "player" and Docked() then
            -- в блоке жизнь — главная: за неё тянется весь блок
            self.dragMain = true; ET_MainFrame:StartMoving()
        else
            self.moving = true; self:StartMoving()
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        if self.dragMain then
            self.dragMain = false
            ET_MainFrame:StopMovingOrSizing()
            ns.SavePos(ET_MainFrame, EnergyTickSettings, "x", "y")
            return
        end
        self:StopMovingOrSizing(); self.moving = false
        if not InCombatLockdown() then ns.SavePos(self, UF_Settings, kx, ky) end
        f.applied = nil
    end)
    btn:SetScript("OnEnter", function(self)
        f.hover = true
        if not f.docked then (f.split and f.hpBox or f):SetBackdropBorderColor(0.9, 0.9, 0.9, 1) end
        if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
        else GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT") end
        pcall(GameTooltip.SetUnit, GameTooltip, unit)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        f.hover = false
        if not f.docked then ns.ResetBorder(f.split and f.hpBox or f) end
        GameTooltip:Hide()
    end)

    f.neon = ns.RoundRing(f, 2)        -- тип дебаффа: скруглённое кольцо вокруг фрейма
    f.ukey, f.MoveKey = ukey, MoveKey
    f.moveGlow = ns.MoveGlow(f, 2)     -- голубая: фрейм можно двигать

    f.hp = Bar(f, lvl + 2)
    f.power = Bar(f, lvl + 2)

    -- Раздельные полосы (цель): у инфо/каста, жизни и ресурса — свои скруглённые подложки
    f.infoBox = CreateFrame("Frame", nil, f, BACKDROP); Box(f.infoBox, 0.9); f.infoBox:SetFrameLevel(lvl); f.infoBox:Hide()
    f.hpBox = CreateFrame("Frame", nil, f, BACKDROP); Box(f.hpBox, 1); f.hpBox:SetFrameLevel(lvl + 1); f.hpBox:Hide()
    f.pwBox = CreateFrame("Frame", nil, f, BACKDROP); Box(f.pwBox, 1); f.pwBox:SetFrameLevel(lvl + 1); f.pwBox:Hide()
    f.neonBase, f.neonHP = f.neon, ns.RoundRing(f.hpBox, 2) -- рамка дебаффа — вокруг жизни

    local top = CreateFrame("Frame", nil, f); top:SetAllPoints(f); top:SetFrameLevel(lvl + 6)
    f.hpText = Text(top, 12); f.hpText:SetPoint("RIGHT", f.hp, "RIGHT", -4, 0)
    f.level = Text(top, 10); f.level:SetPoint("LEFT", f.hp, "LEFT", 4, 0)
    f.name = Text(top, 10); f.name:SetPoint("LEFT", f.level, "RIGHT", 3, 0)
    f.name:SetPoint("RIGHT", f.hpText, "LEFT", -4, 0); f.name:SetJustifyH("LEFT")
    f.stateText = Text(top, 11); f.stateText:SetPoint("CENTER", f.hp, "CENTER", 0, 0)
    f.powerText = Text(top, 8); f.powerText:SetPoint("RIGHT", f.power, "RIGHT", -3, 0)

    -- строка над фреймом: слева АГРО / цель цели, справа % угрозы
    f.infoL = Text(top, 10); f.infoL:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 1, 3); f.infoL:SetJustifyH("LEFT")
    f.infoR = Text(top, 10); f.infoR:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -1, 3)
    f.infoL:SetPoint("RIGHT", f.infoR, "LEFT", -6, 0)

    f.raid = top:CreateTexture(nil, "OVERLAY")
    f.raid:SetSize(16, 16); f.raid:SetPoint("CENTER", f, "TOP", 0, 0)
    f.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons"); f.raid:Hide()

    f.auras = {}
    for i = 1, AURA_SLOTS do f.auras[i] = CreateAuraIcon(f) end

    f.cast = CreateCastBar(f, unit)
    -- каст лежит на месте инфо-строки: текст гаснет, пока идёт каст
    f.infoWant, f.infoA = 1, 1
    f.cast:HookScript("OnShow", function() f.infoWant = 0 end)
    f.cast:HookScript("OnHide", function() f.infoWant = 1 end)
    f.acc, f.auraDirty, f.auraT = 1, true, 0
    return f
end

-- =============================================
-- Свой каст-бар в едином блоке: отдельная полоса, привязана к жизни,
-- двигается только по вертикали (UF_Settings.castOffY)
-- =============================================
local CAST_DEFAULT_Y = 3
local function PlaceDockCast(c)
    local y = UF_Settings.castOffY or CAST_DEFAULT_Y
    c:ClearAllPoints()
    c:SetPoint("BOTTOMLEFT", ET_HPFrame, "TOPLEFT", 0, y)
    c:SetPoint("BOTTOMRIGHT", ET_HPFrame, "TOPRIGHT", 0, y)
end

local castDrag = CreateFrame("Frame")
local function MakeCastDrag(c, target)
    target = target or c
    c:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not self.dockMove then return end
        local sc = self:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local from, y0 = cy / sc, UF_Settings.castOffY or CAST_DEFAULT_Y
        self.dragging = true
        castDrag:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local v = y0 + (y / sc - from)
            v = math.max(-200, math.min(200, v))
            if math.abs(v - CAST_DEFAULT_Y) < 4 then v = CAST_DEFAULT_Y end -- прилипает над жизнью
            UF_Settings.castOffY = math.floor(v + 0.5)
            PlaceDockCast(target)
        end)
    end)
    c:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.ToggleUnlock("main"); return end
        if not self.dragging then return end
        self.dragging = false
        castDrag:SetScript("OnUpdate", nil)
        if UF_Settings.castOffY == CAST_DEFAULT_Y then UF_Settings.castOffY = nil end
    end)
end

-- Цель (раздельные полосы): главная — жизнь (это и есть фрейм/кнопка).
-- Инфо-строка и ресурс — снаружи, двигаются только вверх-вниз (tInfoY / tPowY).
local T_INFO_Y, T_POW_Y = 2, -2
local function PlaceTargetBoxes(f)
    local S = UF_Settings
    local iy, py = S.tInfoY or T_INFO_Y, S.tPowY or T_POW_Y
    f.infoBox:ClearAllPoints()
    f.infoBox:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, iy); f.infoBox:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, iy)
    f.pwBox:ClearAllPoints()
    f.pwBox:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, py); f.pwBox:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, py)
end

-- Размеры цели: свои или как у моего блока
local function TargetSizes()
    local S, E = UF_Settings, EnergyTickSettings
    local link = S.targetLink ~= false
    local w = link and E.width or S.width
    local hpH = S.tHpH or 16
    local pH = S.showPower and (S.tPowH or 4) or 0
    return w, hpH, pH, S.tCastH or 13
end

local function LayoutFrame(f)
    local S = UF_Settings
    local dock = f.unit == "player" and Docked()
    local split = f.unit == "target" and S.targetSplit ~= false
    f.docked, f.split = dock, split
    local ph = S.showPower and S.powerHeight or 0
    local w, h = S.width, 2 + S.hpHeight + (ph > 0 and (1 + ph) or 0)

    -- по умолчанию — без раздельных подложек
    f.infoBox:Hide(); f.hpBox:Hide(); f.pwBox:Hide()
    f.neonHP:Hide(); f.neonBase:Hide()
    f.neon = split and f.neonHP or f.neonBase
    for _, t in ipairs({ f.level, f.name, f.infoL, f.infoR }) do t:SetAlpha(1) end
    f.infoA = 1
    f.level:ClearAllPoints(); f.name:ClearAllPoints(); f.infoL:ClearAllPoints(); f.infoR:ClearAllPoints()

    if split then
        -- Цель: [инфо/каст]  [ЖИЗНЬ]  [ресурс] — отдельные скруглённые полосы.
        -- Фрейм (и кнопка) = полоса жизни; инфо и ресурс — снаружи, тянутся вверх-вниз.
        local ci, hpH
        w, hpH, ph, ci = TargetSizes()
        h = hpH + 2
        f:SetSize(w, h)
        f.rSkip = true; ns.StyleFrame(f)
        local ib, hb, pb = f.infoBox, f.hpBox, f.pwBox
        hb:ClearAllPoints(); hb:SetAllPoints(f); hb:Show()
        f.hp:ClearAllPoints(); f.hp:SetPoint("TOPLEFT", hb, "TOPLEFT", 1, -1); f.hp:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT", -1, 1)
        f.hp:Show()
        ib:SetHeight(ci); ib:Show()
        pb:SetHeight(math.max(1, ph) + 2); pb:SetShown(ph > 0)
        PlaceTargetBoxes(f)
        f.power:ClearAllPoints(); f.power:SetPoint("TOPLEFT", pb, "TOPLEFT", 1, -1); f.power:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", -1, 1)
        f.power:SetShown(ph > 0); f.powerText:Hide()
        -- инфо-строка: уровень и имя слева; справа «→ ВЫ» и % угрозы
        local fs = math.max(8, math.min(12, ci - 3))
        for _, t in ipairs({ f.level, f.name, f.infoL, f.infoR }) do ns.SetFont(t, fs); t:Show() end
        f.level:SetPoint("LEFT", ib, "LEFT", 5, 0)
        f.infoR:SetPoint("RIGHT", ib, "RIGHT", -5, 0)
        f.infoL:SetPoint("RIGHT", f.infoR, "LEFT", -6, 0); f.infoL:SetJustifyH("RIGHT")
        f.name:SetPoint("LEFT", f.level, "RIGHT", 3, 0); f.name:SetPoint("RIGHT", f.infoL, "LEFT", -6, 0)
        f.hpText:Show(); f.stateText:Show()
    else
        -- обычная раскладка текстов (в одной рамке)
        for _, t in ipairs({ f.level, f.name, f.infoL, f.infoR }) do ns.SetFont(t, 10) end
        f.level:SetPoint("LEFT", f.hp, "LEFT", 4, 0)
        f.name:SetPoint("LEFT", f.level, "RIGHT", 3, 0); f.name:SetPoint("RIGHT", f.hpText, "LEFT", -4, 0)
        f.infoR:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -1, 3)
        f.infoL:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 1, 3); f.infoL:SetPoint("RIGHT", f.infoR, "LEFT", -6, 0)
        f.infoL:SetJustifyH("LEFT")
    end

    if split then
        -- уже разложено выше
    elseif dock then
        -- Единый блок: жизнь рисует главная полоса (ET_HPFrame). Здесь — невидимая
        -- оболочка вокруг блока: клик/меню, рамка цвета дебаффа, иконки дебаффов, звук агро.
        f:ClearAllPoints()
        f:SetAllPoints(ET_MainFrame) -- рамка дебаффа — вокруг энергии
        f.rSkip = true; ns.StyleFrame(f) -- невидимая оболочка
        for _, r in ipairs({ f.hp, f.power, f.hpText, f.name, f.level, f.infoL, f.infoR, f.stateText, f.powerText }) do r:Hide() end
    else
        f:SetSize(w, h)
        f.rSkip = false; ns.StyleFrame(f)
        for _, r in ipairs({ f.hp, f.hpText, f.name, f.level, f.infoL, f.infoR, f.stateText }) do r:Show() end
        f.hp:ClearAllPoints()
        f.hp:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1); f.hp:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
        f.hp:SetHeight(S.hpHeight)
        f.power:ClearAllPoints()
        f.power:SetPoint("TOPLEFT", f.hp, "BOTTOMLEFT", 0, -1); f.power:SetPoint("TOPRIGHT", f.hp, "BOTTOMRIGHT", 0, -1)
        f.power:SetHeight(math.max(1, ph))
        f.power:SetShown(ph > 0); f.powerText:Hide() -- минимально: полоска без цифр
    end
    local castH = split and select(4, TargetSizes()) or S.castHeight
    f.cast:SetHeight(castH)
    f.cast.icon:SetSize(castH - 2, castH - 2)

    -- Свой каст: в блоке — отдельная полоса над жизнью (тянется вверх-вниз), иначе — под фреймом
    f.cast:ClearAllPoints()
    if dock then
        PlaceDockCast(f.cast)
    elseif split then
        f.cast:SetAllPoints(f.infoBox) -- каст цели — на месте инфо-строки
    else
        f.cast:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -3); f.cast:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
    end

    -- Дебаффы: у цели — над фреймом справа налево; у игрока — над фреймом,
    -- а в блоке — справа от блока, в ряд
    local size = ((f.unit == "player") and S.playerAuraSize or S.auraSize) or 22
    for i, b in ipairs(f.auras) do
        b:SetSize(size, size); b:ClearAllPoints()
        local x = (i - 1) * (size + 2)
        if split then b:SetPoint("BOTTOMRIGHT", f.infoBox, "TOPRIGHT", -x, 4) -- над инфо-строкой
        elseif f.unit == "target" then b:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -x, 16)
        elseif dock then b:SetPoint("TOPLEFT", f, "TOPRIGHT", 6 + x, 0)
        else b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", x, 16) end
    end
    f.applied = nil
    f.auraDirty = true

    -- защищённая кнопка: размер/позиция только вне боя
    if SecureOK() then
        local btn = f.btn
        btn:ClearAllPoints()
        if dock then
            -- поверх полосы жизни (выше слоя главной полосы, чтобы клики шли сюда)
            btn:SetFrameStrata(ET_MainFrame:GetFrameStrata())
            btn:SetFrameLevel(ET_MainFrame:GetFrameLevel() + 12)
            btn:SetPoint("TOPLEFT", ET_HPFrame, "TOPLEFT", 0, 0)
            btn:SetPoint("BOTTOMRIGHT", ET_HPFrame, "BOTTOMRIGHT", 0, 0)
        else
            btn:SetFrameStrata("MEDIUM")
            btn:SetSize(w, h)
            btn:SetPoint("CENTER", UIParent, "CENTER", S[f.kx] or 0, S[f.ky] or 0)
        end
        btn:EnableMouse(true)
    end
end

local function HPColor(pct)
    if pct > 0.7 then return C_HOLD elseif pct > 0.3 then return C_WAIT end
    return C_CAP
end

local Hex = ns.Hex

local CLASSIF = { elite = "+", rareelite = "R+", rare = "R", worldboss = "Б" }

-- Уровень (с цветом сложности) и цвет имени: класс у игроков, отношение у NPC
local function UpdateNameLevel(f, unit)
    local lvl, okL = Read(UnitLevel, unit)
    if okL and type(lvl) == "number" then
        local cl, okC = Read(UnitClassification, unit)
        local mark = (okC and CLASSIF[cl]) or ""
        -- Минимально: свой уровень не показываем; у цели — только если он отличается или моб особый
        local myLvl = Read(UnitLevel, "player")
        local same = unit == "player" or (lvl == myLvl and mark == "")
        local txt = same and "" or (((lvl < 0) and "??" or tostring(lvl))..mark)
        local col = {1, 0.82, 0}
        if lvl < 0 then col = {1, 0.1, 0.1}
        elseif unit ~= "player" and GetCreatureDifficultyColor then
            local ok, c = pcall(GetCreatureDifficultyColor, lvl)
            if ok and type(c) == "table" and c.r then col = {c.r, c.g, c.b} end
        end
        f.level:SetText(txt ~= "" and (Hex(col)..txt.."|r") or "")
    else
        f.level:SetText("")
    end

    -- имя — тем же цветом «кто это», что и полоса над головой
    local wc = ns.WhoColor(unit)
    f.name:SetTextColor(wc[1], wc[2], wc[3])
    SafeText(f.name, (Read(UnitName, unit)), "")
end

-- Ближний бой: Sinister Strike как мерка досягаемости
local meleeSpell
-- base — общая прозрачность (вне боя); вне досягаемости — ещё бледнее
local function TargetRange(f, base)
    base = base or 1
    if not meleeSpell then
        local ok, n = pcall(function() return C_Spell.GetSpellName(1752) end)
        meleeSpell = (ok and type(n) == "string") and n or 1752
    end
    local ok, r = pcall(function() return C_Spell.IsSpellInRange(meleeSpell, "target") end)
    if not ok then return base end
    if issecret(r) then
        -- Midnight: прозрачность из секретного boolean без сравнения
        if f.SetAlphaFromBoolean and pcall(f.SetAlphaFromBoolean, f, r, base, base * 0.55) then return nil end
        return base
    end
    return (r == false) and base * 0.55 or base
end

local lastAggroSound, prevPlayerThreat = 0, 0

local function UpdateThreat(f, unit, test)
    local S = UF_Settings
    local status, pct
    if test then
        status, pct = (unit == "player") and 3 or 1, 87
    elseif S.aggro then
        if unit == "player" then
            local v, ok = Read(UnitThreatSituation, "player")
            if ok then status = v end
        elseif UnitExists("target") then
            local ok, _, st, sp = pcall(UnitDetailedThreatSituation, "player", "target")
            if ok and not issecret(st) then status = st end
            if ok and not issecret(sp) and type(sp) == "number" then pct = sp end
        end
    end
    status = type(status) == "number" and status or 0

    -- Минимально: только надпись «АГРО», без рамок
    local c = THREAT_COLORS[status]
    if unit == "player" then
        f.infoL:SetText(status >= 2 and (Hex(C_CAP).."АГРО|r") or "")
        -- звук: только в момент, когда мобы переключились на вас
        if status == 3 and prevPlayerThreat < 3 and not test and S.aggroSound
            and UnitAffectingCombat("player") and GetTime() - lastAggroSound > 3 then
            lastAggroSound = GetTime()
            ns.PlayTick(S.aggroSoundID or 8959, "Master")
        end
        prevPlayerThreat = status
    else
        -- % угрозы — только когда он важен: вы близко к срыву агро или уже держите его
        if pct and c then
            f.infoR:SetText(Hex(c).."угроза "..math.floor(pct + 0.5).."%|r")
        else
            f.infoR:SetText("")
        end
    end
end

local function UpdateToT(f, test)
    -- с раздельными полосами цель цели показывает свой фрейм; здесь «→ ВЫ» — только если он выключен
    if f.split then
        if UF_Settings.showToT then f.infoL:SetText(""); return end
    elseif not UF_Settings.showToT then f.infoL:SetText(""); return end
    if test then f.infoL:SetText("|cffe0b464→ ВЫ|r"); return end
    if not UnitExists("targettarget") then f.infoL:SetText(""); return end
    local isMe, ok = Read(UnitIsUnit, "targettarget", "player")
    -- Минимально: показываем только когда цель смотрит на вас
    f.infoL:SetText((ok and isMe) and "|cffe0b464→ ВЫ|r" or "")
end

local function UpdateRaidIcon(f, unit)
    local idx, ok = Read(GetRaidTargetIndex, unit)
    if ok then
        if idx then SetRaidTargetIconTexture(f.raid, idx); f.raid:Show() else f.raid:Hide() end
    elseif pcall(SetRaidTargetIconTexture, f.raid, idx) then
        f.raid:Show()
    else
        f.raid:Hide()
    end
end

local function UpdateUnitFrame(self, el)
    local S = UF_Settings
    local unit, now, test = self.unit, GetTime(), ns.testMode

    local pct, pctOK, rawCur, rawMax, state = 1, true, nil, nil, nil
    if test then
        pct = unit == "player" and 0.25 or 0.55
    else
        local conn, okConn = Read(UnitIsConnected, unit)
        if okConn and not conn then state = "OFFLINE"
        elseif Flag(UnitIsGhost, unit) then state = "ПРИЗРАК"
        elseif Flag(UnitIsDead, unit) then state = "МЁРТВ"
        else
            local cur, okC = Read(UnitHealth, unit)
            local max, okM = Read(UnitHealthMax, unit)
            if okC and okM then pct = (max and max > 0) and (cur / max) or 0
            else pctOK, rawCur, rawMax = false, cur, max end
        end
    end

    -- HP
    local hp = self.hp
    -- цель: как полоса над головой — «кто это» (или старая шкала по % жизни)
    -- цвет цели (класс / отношение + кривые) — 10 раз в секунду; смена цели сразу (acc = 1)
    local tick = self.acc >= 0.1
    local enemyHP = unit == "target"
    local paintT = (EnergyTickSettings and EnergyTickSettings.npColor == "health") and ns.PaintEnemyHP or ns.PaintWhoHP
    if state then
        hp:SetMinMaxValues(0, 1); hp:SetValue(1); SetColor(hp, C_DEAD); ns.HidePulse(hp)
    elseif pctOK then
        hp:SetMinMaxValues(0, 1); hp:SetValue(pct)
        if not enemyHP then SetColor(hp, HPColor(pct)) elseif tick then paintT(hp, unit, pct, 0.85) end
    else
        pcall(hp.SetMinMaxValues, hp, 0, rawMax)
        pcall(hp.SetValue, hp, rawCur)
        if not enemyHP then SetColor(hp, C_SECRET) elseif tick then paintT(hp, unit, nil, 0.85) end
    end

    -- Ресурс
    if S.showPower then
        local pw = self.power
        if test then
            local v = math.floor(((now - ns.testStart) * 20) % 100)
            SetColor(pw, POWER_COLORS[unit == "player" and 3 or 0], 1)
            pw:SetMinMaxValues(0, 100); pw:SetValue(v)
            if tick then self.powerText:SetText(v) end
        else
            local pt, ptOK = Read(UnitPowerType, unit)
            SetColor(pw, (ptOK and POWER_COLORS[pt]) or C_SECRET, 1)
            local cur, okC = Read(UnitPower, unit)
            local max, okM = Read(UnitPowerMax, unit)
            if okC and okM then
                pw:SetMinMaxValues(0, (max and max > 0) and max or 1); pw:SetValue(cur or 0)
                if tick then self.powerText:SetText((max and max > 0) and cur or "") end
            else
                pcall(pw.SetMinMaxValues, pw, 0, max)
                pcall(pw.SetValue, pw, cur)
                if tick then SafeText(self.powerText, cur, "") end
            end
        end
    end

    -- Всё остальное — 10 раз в секунду
    self.acc = self.acc + (el or 0)
    if tick then
        self.acc = 0
        if test then
            self.level:SetText(unit == "target" and "|cffff800062+|r" or "")
            self.name:SetTextColor(1, 1, 1)
            self.name:SetText(unit == "player" and "Вы" or "Тестовый враг")
            self.raid:SetShown(unit == "target")
            if unit == "target" then SetRaidTargetIconTexture(self.raid, 8) end
        else
            UpdateNameLevel(self, unit)
            UpdateRaidIcon(self, unit)
        end

        self.stateText:SetText(state or "")
        local textOn
        if unit == "target" then textOn = S.showTargetText ~= false else textOn = S.showText end
        if EnergyTickSettings and EnergyTickSettings.noNumbers then textOn = false end
        if state or not textOn then
            self.hpText:SetText("")
        elseif pctOK then
            self.hpText:SetText(math.floor(pct * 100 + 0.5).."%")
        elseif not (UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 and pcall(function()
                self.hpText:SetFormattedText("%.0f%%", UnitHealthPercent(unit, false, CurveConstants.ScaleTo100))
            end)) then
            self.hpText:SetText("")
        end

        if unit == "target" then UpdateToT(self, test) end
        UpdateThreat(self, unit, test)

        -- Прозрачность вне боя — общая для всех панелей (и игрок, и цель);
        -- цель вне досягаемости — ещё бледнее
        local base = (test or UnitAffectingCombat("player")) and 1 or (EnergyTickSettings.oocAlpha or 0.35)
        if unit == "target" and S.rangeFade and not test then
            local a = TargetRange(self, base)
            if a then self:SetAlpha(a) end
        else
            self:SetAlpha(base)
        end
    end

    -- Дебаффы: по событию UNIT_AURA, плюс страховка раз в секунду
    if self.auraDirty or now - self.auraT > 1 then UpdateAuras(self) end

    -- Положение: следуем за кнопкой; тряска при низком HP
    local shaking = S.shake and not self.docked and not ns.IsMovable(self.ukey) and pctOK and not state and pct < 0.35 and pct > 0
    if shaking then
        local power = (0.35 - pct) * 25
        local ox = math.sin(now * 18) * (power * 0.4) + math.sin(now * 45) * 0.4
        local oy = math.cos(now * 14) * (power * 0.3)
        self:ClearAllPoints(); self:SetPoint("CENTER", self.btn, "CENTER", ox, oy)
        self.applied = nil
    elseif not self.applied and not self.docked then
        self:ClearAllPoints(); self:SetPoint("CENTER", self.btn, "CENTER", 0, 0)
        self.applied = true
    end

    -- Инфо-строка цели гаснет под кастом (плавно, без мигания)
    if self.split and self.infoA ~= self.infoWant then
        local a, wnt = self.infoA, self.infoWant
        a = (wnt > a) and math.min(wnt, a + (el or 0) / 0.15) or math.max(wnt, a - (el or 0) / 0.15)
        self.infoA = a
        for _, t in ipairs({ self.level, self.name, self.infoL, self.infoR }) do t:SetAlpha(a) end
    end

    -- Неон: цвет снимаемого дебаффа (яд / проклятие / болезнь / магия)
    local pulse = 1 -- минимально: ровная рамка, без мигания
    if state then
        self.neon:Hide()
    elseif self.neonColor then
        local c = self.neonColor
        self.neon:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        self.neon:SetAlpha(pulse); self.neon:Show()
    elseif self.neonSecret then
        local r, g, b, a = AuraColor(unit, self.neonSecret, 0)
        if pcall(self.neon.SetBackdropBorderColor, self.neon, r, g, b, a) then
            self.neon:SetAlpha(pulse); self.neon:Show()
        else
            self.neon:Hide()
        end
    else
        self.neon:Hide()
    end
end

local Player = CreateUnitFrame("Player", "player", "px", "py")
local Target = CreateUnitFrame("Target", "target", "tx", "ty")
Player:SetScript("OnUpdate", UpdateUnitFrame)
Target:SetScript("OnUpdate", UpdateUnitFrame)

MakeCastDrag(Player.cast)

-- =============================================
-- ИНФО-ПОЛОСА: лежит на месте своего каста. Пока нет каста — показывает
-- полезное (в бою и вне боя — разное), каст её плавно заменяет.
--   в бою:    АГРО / угроза %  ·  → ВЫ  ·  яды (только если проблема)
--   вне боя:  уровень и имя    ·  опыт  ·  яды, прочность (если < 50%)
-- =============================================
local info = CreateFrame("Frame", "RT_InfoBar", Player, BACKDROP)
info:SetAllPoints(Player.cast)
info:SetFrameLevel(math.max(0, Player.cast:GetFrameLevel() - 1))
Box(info, 0.9)
info.L = Text(info, 10); info.L:SetPoint("LEFT", info, "LEFT", 5, 0); info.L:SetJustifyH("LEFT")
-- Яды: две точки справа, как оружие в окне персонажа: левая — основная рука, правая — вторая.
-- Зелёная — яд есть, жёлтая — меньше 5 минут, красная — яда нет. Нет оружия — нет точки.
local DOT = "Interface\\AddOns\\RogueTick\\Media\\ring_4_4" -- залитый круг (кольцо толщиной в радиус)
info.dotR = info:CreateTexture(nil, "OVERLAY"); info.dotR:SetTexture(DOT)
info.dotR:SetPoint("RIGHT", info, "RIGHT", -6, 0)
info.dotL = info:CreateTexture(nil, "OVERLAY"); info.dotL:SetTexture(DOT)
info.dotL:SetPoint("RIGHT", info.dotR, "LEFT", -3, 0)
-- без «прилипания» к пикселям: иначе при нецелом масштабе интерфейса одну точку сплющивает
for _, d in ipairs({ info.dotL, info.dotR }) do
    if d.SetSnapToPixelGrid then d:SetSnapToPixelGrid(false); d:SetTexelSnappingBias(0) end
end
info.R = Text(info, 10); info.R:SetPoint("RIGHT", info.dotL, "LEFT", -6, 0); info.R:SetJustifyH("RIGHT")
-- центр занимает место между левым и правым текстом и обрезается, а не наслаивается
info.C = Text(info, 10)
info.C:SetPoint("LEFT", info.L, "RIGHT", 6, 0); info.C:SetPoint("RIGHT", info.R, "LEFT", -6, 0)
info.C:SetJustifyH("CENTER")
info.want, info.acc = 1, 1
info:Hide()
MakeCastDrag(info, Player.cast)

local function InfoOn() return Player.docked and UF_Settings.infoBar ~= false end
-- «АГРО» показывает инфо-полоса (тогда полоса жизни его не рисует)
ns.InfoAggro = function() return Docked() and UF_Settings.infoBar ~= false and UF_Settings.aggroInInfo ~= false end

-- каст поверх: инфо гаснет, после каста возвращается
Player.cast:HookScript("OnShow", function() info.want = 0 end)
Player.cast:HookScript("OnHide", function() info.want = 1 end)

local DIM = { 0.55, 0.55, 0.55 }
local TEXT = { 0.85, 0.85, 0.85 }
local function Col(c, txt) return Hex(c)..txt.."|r" end

-- Цвета точек ядов — одинаковые в любом стиле (в монохроме красный/зелёный иначе не различить)
local DOT_OK, DOT_LOW, DOT_NONE = { 0.42, 0.72, 0.46 }, { 0.88, 0.66, 0.34 }, { 0.82, 0.34, 0.32 }

-- Состояние руки: nil — нет оружия, иначе таблица цвета
local function HandState(slot, has, exp)
    if not GetInventoryItemID("player", slot) then return nil end
    if issecret(has) then return nil end
    if not has then return DOT_NONE end
    if type(exp) == "number" and not issecret(exp) and exp < 5 * 60000 then return DOT_LOW end
    return DOT_OK
end

local function SetDot(tex, c)
    if c then tex:SetVertexColor(c[1], c[2], c[3], 1); tex:Show() else tex:Hide() end
end

local function UpdatePoisonDots()
    if ns.testMode then SetDot(info.dotL, DOT_OK); SetDot(info.dotR, DOT_NONE); return end
    local lvl = Read(UnitLevel, "player")
    local ok, hasMH, mhExp, _, _, hasOH, ohExp
    if GetWeaponEnchantInfo and type(lvl) == "number" and lvl >= 20 then -- ядов до 20 уровня нет
        ok, hasMH, mhExp, _, _, hasOH, ohExp = pcall(GetWeaponEnchantInfo)
    end
    if not ok then SetDot(info.dotL, nil); SetDot(info.dotR, nil); return end
    -- как в окне персонажа: слева основная рука, справа вторая
    SetDot(info.dotL, HandState(16, hasMH, mhExp)) -- основная рука
    SetDot(info.dotR, HandState(17, hasOH, ohExp)) -- вторая рука
end

local function Durability()
    local low
    for slot = 1, 18 do
        local ok, cur, max = pcall(GetInventoryItemDurability, slot)
        if ok and type(cur) == "number" and type(max) == "number" and max > 0 then
            local p = cur / max
            low = math.min(low or p, p)
        end
    end
    return low
end

local function InfoUpdate()
    local inCombat = UnitAffectingCombat("player")
    if ns.testMode then
        info.L:SetText(Col(C_CAP, "АГРО")); info.C:SetText(Col(C_CAP, "→ ВЫ")); info.R:SetText("")
        UpdatePoisonDots()
        return
    end
    if inCombat then
        -- агро: на вас / угроза на цели
        local L = ""
        if UF_Settings.aggro ~= false and UF_Settings.aggroInInfo ~= false then
            local st, ok = Read(UnitThreatSituation, "player")
            if ok and type(st) == "number" and st >= 2 then
                L = Col(C_CAP, "АГРО")
            elseif UnitExists("target") then
                local ok2, _, _, pct = pcall(UnitDetailedThreatSituation, "player", "target")
                if ok2 and type(pct) == "number" and not issecret(pct) and pct >= 70 then
                    L = Col(C_WAIT, "угроза "..math.floor(pct + 0.5).."%")
                end
            end
        end
        info.L:SetText(L)
        local me, okm = false, false
        if UnitExists("targettarget") then me, okm = Read(UnitIsUnit, "targettarget", "player") end
        info.C:SetText((okm and me) and Col(C_CAP, "→ ВЫ") or "")
        info.R:SetText("")
    else
        local lvl, okL = Read(UnitLevel, "player")
        local name = Read(UnitName, "player")
        local _, cls = UnitClass("player")
        local cc = (not issecret(cls)) and cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        local nameTxt = (type(name) == "string") and name or ""
        if cc then nameTxt = string.format("|cff%02x%02x%02x%s|r", cc.r * 255, cc.g * 255, cc.b * 255, nameTxt) end
        info.L:SetText(((okL and type(lvl) == "number") and (Col(DIM, lvl).."  ") or "")..nameTxt)
        -- опыт (если ещё качаемся)
        local xp, ok1 = Read(UnitXP, "player")
        local xm, ok2 = Read(UnitXPMax, "player")
        local maxLvl = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
        if ok1 and ok2 and type(xm) == "number" and xm > 0 and type(lvl) == "number" and lvl < maxLvl then
            info.C:SetText(Col(TEXT, "XP "..math.floor(xp / xm * 100).."%"))
        else
            info.C:SetText("")
        end
        local d = Durability()
        info.R:SetText((d and d < 0.5) and Col(d < 0.25 and C_CAP or C_WAIT, "броня "..math.floor(d * 100 + 0.5).."%") or "")
    end
    UpdatePoisonDots()
end

info:SetScript("OnUpdate", function(self, el)
    -- плавная смена: каст <-> инфо (без мигания)
    local a = self:GetAlpha()
    if a ~= self.want then
        a = (self.want > a) and math.min(self.want, a + el / 0.15) or math.max(self.want, a - el / 0.15)
        self:SetAlpha(a)
    end
    self.acc = self.acc + el
    if self.acc >= 0.25 then
        self.acc = 0; InfoUpdate()
        -- центр второстепенный: не влез целиком — прячем, а не режем до «оп…»
        if self.C.IsTruncated and self.C:IsTruncated() then self.C:SetText("") end
    end
end)

local function LayoutInfo()
    local on = InfoOn()
    info:SetShown(on and true or false)
    if on then
        local fs = math.max(8, math.min(12, (UF_Settings.castHeight or 14) - 3))
        for _, t in ipairs({ info.L, info.C, info.R }) do ns.SetFont(t, fs) end
        local ds = math.max(4, math.min(10, (UF_Settings.castHeight or 14) - 6))
        info.dotL:SetSize(ds, ds); info.dotR:SetSize(ds, ds)
        info.want = Player.cast:IsShown() and 0 or 1
        info:SetAlpha(info.want)
        info.acc = 1
    end
end

-- Свой каст в блоке: когда блок выбран ПКМ, показываем пример каста, чтобы его было видно и можно было тянуть
-- (с инфо-полосой пример не нужен — её и так видно)
local function ApplyCastMove()
    local c = Player.cast
    local movable = Player.docked and ns.IsMovable("main") and true or false
    c.dockMove = movable
    c:EnableMouse(movable)
    info.dockMove = movable
    info:EnableMouse(movable)
    local show = Player.docked and ns.IsSelected("main") and not InfoOn()
    if show and not c.active then
        CastFake(c, true); c.moveFake = true
    elseif not show and c.moveFake then
        c.moveFake = nil
        if not ns.testMode then CastFake(c, false) end
    end
end

-- Цель: тянуть жизнь — едет вся цель; инфо-строку и ресурс — только вверх-вниз
local tDrag = CreateFrame("Frame")
local function MakeTargetBoxDrag(box, key, default)
    box:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or InCombatLockdown() or not ns.IsMovable("target") then return end
        if box == Target.hpBox then
            self.moving = true; Target.btn.moving = true; Target.btn:StartMoving()
            return
        end
        local sc = self:GetEffectiveScale()
        local _, cy = GetCursorPosition()
        local from, y0 = cy / sc, UF_Settings[key] or default
        self.dragging = true
        tDrag:SetScript("OnUpdate", function()
            local _, y = GetCursorPosition()
            local v = y0 + (y / sc - from)
            v = math.max(-200, math.min(200, v))
            if math.abs(v - default) < 4 then v = default end -- прилипает к жизни
            UF_Settings[key] = math.floor(v + 0.5)
            PlaceTargetBoxes(Target)
        end)
    end)
    box:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then ns.ToggleUnlock("target"); return end
        if self.moving then
            self.moving = false; Target.btn.moving = false
            Target.btn:StopMovingOrSizing()
            ns.SavePos(Target.btn, UF_Settings, "tx", "ty")
            Target.applied = nil
            return
        end
        if not self.dragging then return end
        self.dragging = false
        tDrag:SetScript("OnUpdate", nil)
        if UF_Settings[key] == default then UF_Settings[key] = nil end
    end)
end
MakeTargetBoxDrag(Target.hpBox)
MakeTargetBoxDrag(Target.infoBox, "tInfoY", T_INFO_Y)
MakeTargetBoxDrag(Target.pwBox, "tPowY", T_POW_Y)

local function ApplyMoveGlow()
    for _, fr in ipairs({ Player, Target }) do fr.moveGlow:SetShown(ns.IsSelected(fr.MoveKey())) end
    ApplyCastMove()
    -- полосы цели ловят мышь только в режиме перемещения (иначе клики идут на кнопку цели / в мир)
    local tm = Target.split and ns.IsMovable("target") and true or false
    for _, b in ipairs({ Target.hpBox, Target.infoBox, Target.pwBox }) do b:EnableMouse(tm) end
end
table.insert(ns.unlockHooks, function(key)
    if key == nil or key == "player" or key == "target" or key == "main" then ApplyMoveGlow() end
end)

-- Видимая часть (не защищённая — можно в бою)
-- =============================================
-- ЦЕЛЬ ЦЕЛИ: маленькая кликабельная полоса справа от жизни цели.
-- Имя (или «ВЫ», если цель бьёт вас) и жизнь. ЛКМ — выбрать, ПКМ — меню.
-- =============================================
local totBtn = CreateFrame("Button", "RT_UF_ToTButton", UIParent, "SecureUnitButtonTemplate")
totBtn:SetAttribute("unit", "targettarget")
totBtn:SetAttribute("*type1", "target")
totBtn:SetAttribute("*type2", "togglemenu")
totBtn:RegisterForClicks("AnyUp")
totBtn:SetFrameStrata("MEDIUM")
ClickCastFrames[totBtn] = true
totBtn:Hide()

local tot = CreateFrame("Frame", "RT_UF_ToT", UIParent, BACKDROP)
tot:SetFrameStrata("MEDIUM"); tot:SetFrameLevel(totBtn:GetFrameLevel() + 1)
tot:EnableMouse(false)
tot:SetAllPoints(totBtn)
Box(tot, 1)
tot.hp = Bar(tot, tot:GetFrameLevel() + 1)
tot.hp:SetPoint("TOPLEFT", 1, -1); tot.hp:SetPoint("BOTTOMRIGHT", -1, 1)
local totTop = CreateFrame("Frame", nil, tot); totTop:SetAllPoints(tot); totTop:SetFrameLevel(tot:GetFrameLevel() + 4)
tot.name = Text(totTop, 10); tot.name:SetPoint("LEFT", tot, "LEFT", 4, 0); tot.name:SetJustifyH("LEFT")
tot.pct = Text(totTop, 9); tot.pct:SetPoint("RIGHT", tot, "RIGHT", -4, 0)
tot.name:SetPoint("RIGHT", tot.pct, "LEFT", -4, 0)
tot:Hide()

totBtn:SetScript("OnEnter", function(self)
    tot:SetBackdropBorderColor(0.9, 0.9, 0.9, 1)
    if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT") end
    pcall(GameTooltip.SetUnit, GameTooltip, "targettarget")
    GameTooltip:Show()
end)
totBtn:SetScript("OnLeave", function() ns.ResetBorder(tot); GameTooltip:Hide() end)

local function ToTOn() return UF_Settings.showTarget and UF_Settings.showToT end

local totAcc = 0
local totDriver = CreateFrame("Frame")
totDriver:SetScript("OnUpdate", function(_, el)
    totAcc = totAcc + el
    if totAcc < 0.1 then return end
    totAcc = 0
    local test = ns.testMode
    local show = ToTOn() and (test or totBtn:IsShown()) and Target:IsShown()
    tot:SetShown(show and true or false)
    if not show then return end
    pcall(tot.SetAlpha, tot, Target:GetAlpha()) -- как у цели (вне боя / вне досягаемости)
    if test then
        tot.hp:SetMinMaxValues(0, 1); tot.hp:SetValue(0.7); SetColor(tot.hp, C_HOLD)
        tot.name:SetText(Hex(C_CAP).."ВЫ|r"); tot.pct:SetText("70%")
        return
    end
    local u = "targettarget"
    -- жизнь
    local cur, okC = Read(UnitHealth, u)
    local max, okM = Read(UnitHealthMax, u)
    if okC and okM and max and max > 0 then
        local p = cur / max
        tot.hp:SetMinMaxValues(0, 1); tot.hp:SetValue(p); SetColor(tot.hp, HPColor(p))
        tot.pct:SetText(math.floor(p * 100 + 0.5).."%")
    else
        pcall(tot.hp.SetMinMaxValues, tot.hp, 0, max); pcall(tot.hp.SetValue, tot.hp, cur)
        SetColor(tot.hp, C_SECRET); tot.pct:SetText("")
    end
    -- имя: «ВЫ», если цель смотрит на вас; иначе — цветом класса / отношения
    local isMe, okMe = Read(UnitIsUnit, u, "player")
    if okMe and isMe then
        tot.name:SetText(Hex(C_CAP).."ВЫ|r")
    else
        local wc = ns.WhoColor(u)
        tot.name:SetTextColor(wc[1], wc[2], wc[3])
        SafeText(tot.name, (Read(UnitName, u)), "")
    end
end)

-- Размер/место: справа от полосы жизни цели (защищённая кнопка — только вне боя)
local function LayoutToT()
    if not SecureOK() then return end
    local S = UF_Settings
    local hpH = Target.split and select(2, TargetSizes()) or S.hpHeight
    local yOff = 0
    totBtn:ClearAllPoints()
    totBtn:SetPoint("TOPLEFT", Target.btn, "TOPRIGHT", 6, yOff)
    totBtn:SetSize(S.totWidth or 110, hpH + 2)
    local fs = math.max(8, math.min(11, hpH - 3))
    ns.SetFont(tot.name, fs); ns.SetFont(tot.pct, math.max(8, fs - 1))
    if ToTOn() then
        RegisterUnitWatch(totBtn)
    else
        UnregisterUnitWatch(totBtn); totBtn:Hide()
    end
end

local function UpdateVisibility()
    local S, test = UF_Settings, ns.testMode
    Player:SetShown(S.showPlayer and true or false)
    Target:SetShown(S.showTarget and (test or UnitExists("target")) and true or false)
end

-- Кликабельные кнопки (защищённые — только вне боя)
local function ApplySecureVisibility()
    if not SecureOK() then return end
    local S = UF_Settings
    Player.btn:SetShown(S.showPlayer and true or false)
    if S.showTarget then
        RegisterUnitWatch(Target.btn) -- игра сама показывает/прячет кнопку при смене цели
    else
        UnregisterUnitWatch(Target.btn); Target.btn:Hide()
    end
end

-- =============================================
-- СТАНДАРТНЫЕ ФРЕЙМЫ BLIZZARD: в скрытый родитель (вернуть можно без /reload)
-- =============================================
local hiddenParent = CreateFrame("Frame"); hiddenParent:Hide()
local origParent = {}

local function Reparent(frame, hide)
    if not frame then return end
    if hide then
        if frame:GetParent() ~= hiddenParent then
            origParent[frame] = frame:GetParent()
            frame:SetParent(hiddenParent)
        end
    elseif origParent[frame] then
        frame:SetParent(origParent[frame])
        origParent[frame] = nil
    end
end

function ns.ApplyBlizzard()
    if not SecureOK() then return end
    local S = UF_Settings
    pcall(Reparent, PlayerCastingBarFrame or CastingBarFrame, S.hideBlizzCast)
    pcall(Reparent, PlayerFrame, S.hideBlizzPlayer)
    pcall(Reparent, TargetFrame, S.hideBlizzTarget)
end

-- =============================================
-- СОБЫТИЯ
-- =============================================
local ev = CreateFrame("Frame")
ev:RegisterUnitEvent("UNIT_AURA", "player", "target")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_EMPOWER_STOP", "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}) do
    pcall(ev.RegisterUnitEvent, ev, e, "player", "target")
end

ev:SetScript("OnEvent", function(_, e, unit)
    if e == "UNIT_AURA" then
        local fr = (unit == "player" and Player) or (unit == "target" and Target)
        if fr then fr.auraDirty = true end
    elseif e == "PLAYER_TARGET_CHANGED" then
        UpdateVisibility()
        Target.auraDirty, Target.acc, Target.applied = true, 1, nil
        if not ns.testMode then Target.cast.holdUntil = nil; CastRefresh(Target.cast) end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if securePending then
            securePending = false
            ns.ApplyUF()
        end
    elseif e == "PLAYER_LOGIN" then
        ns.ApplyBlizzard()
    elseif e == "PLAYER_ENTERING_WORLD" then
        UpdateVisibility(); CastRefresh(Player.cast); CastRefresh(Target.cast)
        Player.auraDirty, Target.auraDirty = true, true
    else
        local fr = (unit == "player" and Player) or (unit == "target" and Target)
        if not fr then return end
        local c = fr.cast
        if e == "UNIT_SPELLCAST_INTERRUPTED" then
            CastInterrupted(c)
        elseif e == "UNIT_SPELLCAST_STOP" or e == "UNIT_SPELLCAST_CHANNEL_STOP"
            or e == "UNIT_SPELLCAST_FAILED" or e == "UNIT_SPELLCAST_EMPOWER_STOP" then
            if not c.holdUntil then CastRefresh(c) end
        else
            CastRefresh(c)
        end
    end
end)

table.insert(ns.testHooks, function(on)
    UpdateVisibility()
    CastFake(Player.cast, on); CastFake(Target.cast, on)
    Player.auraDirty, Target.auraDirty = true, true
end)

-- =============================================
-- API для окна настроек
-- =============================================
function ns.ApplyUF()
    ApplyDefaults()
    ApplyStyle()
    for _, fr in ipairs({ Player, Target }) do fr.hp.col, fr.power.col = nil, nil end -- перекрасить
    LayoutFrame(Player); LayoutFrame(Target)
    LayoutToT()
    UpdateVisibility()
    LayoutInfo()
    ApplyMoveGlow()
    ApplySecureVisibility()
    for _, c in ipairs({ Player.cast, Target.cast }) do
        if not CastOn(c) then c:Hide()
        elseif ns.testMode then CastFake(c, true) end
    end
    ns.ApplyBlizzard()
end

function ns.ResetUFPositions()
    local S = UF_Settings
    S.px, S.py, S.tx, S.ty = DEFAULTS.px, DEFAULTS.py, DEFAULTS.tx, DEFAULTS.ty
    S.castOffY, S.tInfoY, S.tPowY = nil, nil, nil
    ns.ApplyUF()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    -- одна общая галочка «Закрепить фреймы» в настройках
    UF_Settings.locked = EnergyTickSettings.locked and true or false
    ns.ApplyUF()
    self:UnregisterEvent("ADDON_LOADED")
end)

-- =============================================
-- КОМАНДЫ
-- =============================================
SLASH_RTH1 = "/rth"
SlashCmdList["RTH"] = function(msg)
    local cmd = (msg or ""):lower()
    if cmd == "lock" then
        if ns.SetLocked then ns.SetLocked(not UF_Settings.locked)
        else UF_Settings.locked = not UF_Settings.locked; ns.ApplyUF() end
        print("|cffffff00RogueTick:|r "..(UF_Settings.locked and "Заблокировано" or "Разблокировано"))
    elseif cmd == "text" then
        UF_Settings.showText = not UF_Settings.showText
        print("|cffffff00RogueTick:|r Цифры HP: "..(UF_Settings.showText and "ВКЛ" or "ВЫКЛ"))
    elseif cmd == "test" then
        ns.SetTest(not ns.testMode)
    else
        print("|cffffff00RogueTick:|r /rth lock | text | test — остальное в /et config")
    end
end
