-- =============================================
-- Compat: WoW Forever (Interface 16001, Midnight-style "secret values")
-- + старый клиент 2.5.x. Всё, что может вернуть секрет, читаем через Read().
-- =============================================
local _, ns = ...

-- В Forever/Midnight есть issecretvalue(); в старых клиентах его нет -> ничего не секретно.
local issecret = issecretvalue or function() return false end
ns.issecret = issecret

-- Безопасный вызов API. Возвращает: значение, readable.
-- readable == false -> значение секретное (его можно отдать только в сеттер виджета) или вызов упал.
function ns.Read(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok then return nil, false end
    if issecret(v) then return v, false end
    return v, true
end

-- Цвет по СКРЫТОМУ значению ресурса (в бою энергия/комбо бывают секретными — сравнить их нельзя).
-- Игра сама считает долю (0…1) и берёт цвет со ступенчатой кривой: stops = { {доля, {r,g,b,a}}, ... }.
-- id+sig — кэш кривой (пересобирается, только когда меняется sig). Возвращает цвет или nil.
local pcurves = {}
function ns.PowerCurveColor(unit, ptype, id, sig, stops)
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitPowerPercent and CreateColor) then return nil end
    local e = pcurves[id]
    if not e or e.sig ~= sig then
        local ok, curve = pcall(function()
            local cv = C_CurveUtil.CreateColorCurve()
            if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then cv:SetType(Enum.LuaCurveType.Step) end
            for _, pt in ipairs(stops) do
                local c = pt[2]
                cv:AddPoint(math.max(0, math.min(1, pt[1])), CreateColor(c[1], c[2], c[3], c[4] or 1))
            end
            return cv
        end)
        if not ok or not curve then pcurves[id] = { sig = sig }; return nil end
        e = { sig = sig, curve = curve }; pcurves[id] = e
    end
    if not e.curve then return nil end
    local ok, col = pcall(UnitPowerPercent, unit, ptype, false, e.curve)
    if ok and type(col) == "table" and col.GetRGBA then return col end
end
-- Отдать такой цвет в сеттер (SetStatusBarColor / SetVertexColor) — секреты сеттеры принимают
function ns.PaintCurve(obj, method, col)
    return col and pcall(obj[method], obj, col:GetRGBA())
end

-- =============================================
-- ЯЗЫК ЦВЕТОВ В БОЮ: один цвет — одно действие.
--   синий — Sinister Strike, оранжевый — Slice and Dice, красный — добей (Eviscerate / цель при смерти),
--   бирюзовый — Kick (каст, который можно сбить), жёлтый — только энергия, серый — жди,
--   лиловый — просто информация (свои полоски, свой каст).
-- =============================================
ns.ACT = {
    ss   = { 0.40, 0.60, 0.90 },
    snd  = { 0.95, 0.58, 0.25 },
    evis = { 0.90, 0.38, 0.38 },
    kick = { 0.30, 0.78, 0.76 },
}

-- Жизнь противника (цель и полосы над головой) — одна шкала без жёлтого (жёлтый — энергия):
-- спокойный зелёный → ярче зелёный → красный «добей» → при смерти весь бар плавно пульсирует.
ns.HP_GOOD = { 0.42, 0.68, 0.46 }
ns.HP_MID  = { 0.54, 0.86, 0.56 }
ns.HP_LOW  = { 0.94, 0.36, 0.32 }
ns.HP_MID_AT, ns.HP_LOW_AT, ns.HP_DIE_AT = 0.60, 0.35, 0.15
local HP_PULSE = { 1.00, 0.86, 0.80 } -- светлая вспышка поверх красного

function ns.HealthColorPct(p)
    if p > ns.HP_MID_AT then return ns.HP_GOOD elseif p > ns.HP_LOW_AT then return ns.HP_MID end
    return ns.HP_LOW
end

local hcurves = {}
local function HCurve(id, stops)
    local e = hcurves[id]
    if e then return e.curve end
    if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor) then return nil end
    local ok, cv = pcall(function()
        local c = C_CurveUtil.CreateColorCurve()
        if Enum and Enum.LuaCurveType and Enum.LuaCurveType.Step then c:SetType(Enum.LuaCurveType.Step) end
        for _, pt in ipairs(stops) do
            local col = pt[2]
            c:AddPoint(pt[1], CreateColor(col[1], col[2], col[3], col[4] or 1))
        end
        return c
    end)
    hcurves[id] = { curve = ok and cv or nil }
    return ok and cv or nil
end
-- жизнь скрыта игрой: цвет считает сама игра по кривой
local function HealthCurveColor(unit, id, stops)
    if not UnitHealthPercent then return nil end
    local cv = HCurve(id, stops)
    if not cv then return nil end
    local ok, col = pcall(UnitHealthPercent, unit, false, cv)
    if ok and type(col) == "table" and col.GetRGBA then return col end
end

-- вспышка поверх заливки (лениво; маска — та же, что у заливки)
local function Pulse(bar)
    local t = bar.hpPulse
    if t then return t end
    t = bar:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints(bar:GetStatusBarTexture()); t:SetColorTexture(1, 1, 1, 1)
    if bar.mask then t:AddMaskTexture(bar.mask) end
    t:SetVertexColor(HP_PULSE[1], HP_PULSE[2], HP_PULSE[3], 1)
    local g = t:CreateAnimationGroup()
    local a = g:CreateAnimation("Alpha")
    a:SetFromAlpha(0); a:SetToAlpha(0.55); a:SetDuration(0.45)
    if a.SetSmoothing then a:SetSmoothing("IN_OUT") end
    g:SetLooping("BOUNCE")
    t.anim = g; t:SetAlpha(0); t:Hide()
    bar.hpPulse = t
    return t
end
local function PulseOn(bar, on)
    local t = bar.hpPulse
    if not on then
        if t and t:IsShown() then t.anim:Stop(); t:Hide() end
        return
    end
    t = Pulse(bar)
    if not t:IsShown() then t:Show(); t.anim:Play() end
end
function ns.HidePulse(bar) PulseOn(bar, false) end
-- пульс при смерти: прозрачность вспышки из кривой (видна только ниже порога)
local function DiePulseColor(unit)
    return HealthCurveColor(unit, "hpDie", {
        { 0, { HP_PULSE[1], HP_PULSE[2], HP_PULSE[3], 1 } },
        { ns.HP_DIE_AT + 0.0001, { HP_PULSE[1], HP_PULSE[2], HP_PULSE[3], 0 } },
    })
end

-- Покрасить полосу жизни противника. p — доля 0…1, если читается; nil — скрыто (бой).
function ns.PaintEnemyHP(bar, unit, p, alpha)
    alpha = alpha or 0.9
    if p then
        local c = ns.HealthColorPct(p)
        if bar.col ~= c then bar.col = c; bar:SetStatusBarColor(c[1], c[2], c[3], alpha) end
        PulseOn(bar, p > 0 and p <= ns.HP_DIE_AT)
        if bar.hpPulse then bar.hpPulse:SetVertexColor(HP_PULSE[1], HP_PULSE[2], HP_PULSE[3], 1) end
        return true
    end
    bar.col = nil
    local g, m, l = ns.HP_GOOD, ns.HP_MID, ns.HP_LOW
    local col = HealthCurveColor(unit, "hp", {
        { 0, { l[1], l[2], l[3], alpha } },
        { ns.HP_LOW_AT + 0.0001, { m[1], m[2], m[3], alpha } },
        { ns.HP_MID_AT + 0.0001, { g[1], g[2], g[3], alpha } },
    })
    if not ns.PaintCurve(bar, "SetStatusBarColor", col) then
        bar:SetStatusBarColor(0.45, 0.45, 0.45, alpha); PulseOn(bar, false); return false
    end
    local pc = DiePulseColor(unit)
    if pc then PulseOn(bar, true); ns.PaintCurve(bar.hpPulse, "SetVertexColor", pc) else PulseOn(bar, false) end
    return true
end

-- =============================================
-- «КТО ЭТО»: цвет полосы говорит, кто перед вами, длина — сколько у него жизни.
--   игрок — цвет класса (приглушённый), враждебный моб — красный, нейтральный — жёлтый,
--   дружелюбный — зелёный, чужой (уже бьёт кто-то другой) — серый.
--   «Добей» — не сменой цвета: ниже 35% полоса ярче, ниже 15% пульсирует.
-- =============================================
ns.WHO = {
    hostile  = { 0.76, 0.36, 0.34 },
    neutral  = { 0.84, 0.74, 0.40 },
    friendly = { 0.42, 0.68, 0.46 },
    tapped   = { 0.45, 0.45, 0.45 },
}
-- «да/нет» из API: секретное значение сравнивать нельзя — считаем «нет»
local function Yes(fn, ...)
    local v, ok = ns.Read(fn, ...)
    return ok and v == true
end
ns.Yes = Yes
-- цвет {r,g,b} -> «|cffRRGGBB» для текста
function ns.Hex(c) return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255) end
local classCol = {}
-- цвет и ключ (класс / отношение) — ключ нужен для кэша кривых
function ns.WhoColor(u)
    if Yes(UnitIsTapDenied, u) then return ns.WHO.tapped, "tapped" end
    if Yes(UnitIsPlayer, u) then
        local _, cls = UnitClass(u)
        if cls and not issecret(cls) and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls] then
            local c = classCol[cls]
            if not c then
                local cc = RAID_CLASS_COLORS[cls]
                c = { cc.r * 0.85, cc.g * 0.85, cc.b * 0.85 }; classCol[cls] = c
            end
            return c, cls
        end
    end
    local r, ok = ns.Read(UnitReaction, u, "player")
    if ok and type(r) == "number" then
        if r <= 3 then return ns.WHO.hostile, "hostile" elseif r == 4 then return ns.WHO.neutral, "neutral" end
        return ns.WHO.friendly, "friendly"
    end
    if Yes(UnitCanAttack, "player", u) then return ns.WHO.hostile, "hostile" end
    return ns.WHO.friendly, "friendly"
end
-- свой: атаковать нельзя и он дружелюбен
function ns.IsFriendUnit(u)
    return not Yes(UnitCanAttack, "player", u) and Yes(UnitIsFriend, "player", u)
end

local brightCol = {}
local function Bright(key, c)
    local b = brightCol[key]
    if not b then
        b = { math.min(1, c[1] * 1.2 + 0.06), math.min(1, c[2] * 1.2 + 0.06), math.min(1, c[3] * 1.2 + 0.06) }
        brightCol[key] = b
    end
    return b
end

-- Покрасить полосу жизни «кто это». p — доля 0…1, если читается; nil — скрыто (бой).
function ns.PaintWhoHP(bar, unit, p, alpha)
    alpha = alpha or 0.9
    local c, key = ns.WhoColor(unit)
    local tapped = key == "tapped"
    if p then
        local use = (not tapped and p <= ns.HP_LOW_AT) and Bright(key, c) or c
        if bar.col ~= use then bar.col = use; bar:SetStatusBarColor(use[1], use[2], use[3], alpha) end
        PulseOn(bar, not tapped and p > 0 and p <= ns.HP_DIE_AT)
        if bar.hpPulse then bar.hpPulse:SetVertexColor(HP_PULSE[1], HP_PULSE[2], HP_PULSE[3], 1) end
        return c
    end
    bar.col = nil
    if tapped then
        bar:SetStatusBarColor(c[1], c[2], c[3], alpha); PulseOn(bar, false); return c
    end
    local b = Bright(key, c)
    local col = HealthCurveColor(unit, "who|"..key..string.format("%.2f", alpha), {
        { 0, { b[1], b[2], b[3], alpha } },
        { ns.HP_LOW_AT + 0.0001, { c[1], c[2], c[3], alpha } },
    })
    if not ns.PaintCurve(bar, "SetStatusBarColor", col) then
        bar:SetStatusBarColor(c[1], c[2], c[3], alpha); PulseOn(bar, false); return c
    end
    local pc = DiePulseColor(unit)
    if pc then PulseOn(bar, true); ns.PaintCurve(bar.hpPulse, "SetVertexColor", pc) else PulseOn(bar, false) end
    return c
end

-- Секрет нельзя склеивать/сравнивать, но можно передать в SetText/SetValue.
function ns.SetText(fs, v, fallback)
    if not pcall(fs.SetText, fs, v) then fs:SetText(fallback or "-") end
end

-- =============================================
-- Шрифт: семейство, как у самого клиента. Голый SetFont("FRIZQT__.TTF") не знает
-- кириллицы -> русские имена превращаются в квадратики. Семейство даёт клиенту
-- выбрать файл под алфавит (латиница / кириллица / корейский / китайский).
-- =============================================
local fontCache = {}
local CYR = "Fonts\\FRIZQT___CYR.TTF"
function ns.Font(size, flags)
    flags = flags or "OUTLINE"
    local key = size.."|"..flags
    if fontCache[key] then return fontCache[key] end
    local name = "RogueTickFont"..size..(flags:gsub("%W", ""))
    local obj
    if CreateFontFamily then
        local ok, o = pcall(CreateFontFamily, name, {
            { alphabet = "roman",              file = "Fonts\\FRIZQT__.TTF", height = size, flags = flags },
            { alphabet = "korean",             file = "Fonts\\2002.TTF",     height = size, flags = flags },
            { alphabet = "simplifiedchinese",  file = "Fonts\\ARKai_T.ttf",  height = size, flags = flags },
            { alphabet = "traditionalchinese", file = "Fonts\\blei00d.TTF",  height = size, flags = flags },
            { alphabet = "russian",            file = CYR,                   height = size, flags = flags },
        })
        if ok then obj = o or _G[name] end
    end
    if not obj then -- старый клиент без семейств: кириллический FRIZQT покрывает и латиницу
        obj = _G[name] or CreateFont(name)
        obj:SetFont(CYR, size, flags)
    end
    fontCache[key] = obj
    return obj
end

-- Шрифты панелей учитывают общий масштаб (fontScale); окно настроек — нет (ns.Font напрямую).
-- Каждая надпись запоминает свой базовый размер, чтобы при смене масштаба её можно было пересчитать.
local fontRegistry = setmetatable({}, { __mode = "k" })
function ns.FontScale()
    local s = EnergyTickSettings and EnergyTickSettings.fontScale
    return (type(s) == "number" and s > 0) and s or 1
end

function ns.SetFont(fs, size, flags)
    fontRegistry[fs] = { size, flags }
    fs:SetFontObject(ns.Font(math.max(6, math.floor(size * ns.FontScale() + 0.5)), flags))
end

-- Пересчитать все надписи панелей (сменился масштаб шрифта)
function ns.ApplyFonts()
    for fs, v in pairs(fontRegistry) do
        fs:SetFontObject(ns.Font(math.max(6, math.floor(v[1] * ns.FontScale() + 0.5)), v[2]))
    end
end

-- Общий тест-режим для всех панелей (/et test, кнопка в настройках, ПКМ по иконке)
ns.testMode, ns.testStart, ns.testHooks = false, 0, {}
function ns.SetTest(on)
    ns.testMode, ns.testStart = on and true or false, GetTime()
    for _, fn in ipairs(ns.testHooks) do pcall(fn, ns.testMode) end
end

-- =============================================
-- Разблокировка по одной панели: ПКМ по полосе (Shift+ПКМ по фреймам игрока/цели)
-- подсвечивает её голубым — её можно двигать; повторный ПКМ закрепляет.
-- Действует до /reload; общая галочка «Закрепить фреймы» сбрасывает всё.
-- =============================================
ns.unlocked, ns.unlockHooks = {}, {}
local MOVE_BLUE = { 0.30, 0.62, 1.00 }

function ns.IsMovable(key)
    local S = EnergyTickSettings
    return not (S and S.locked) or ns.unlocked[key] == true
end

-- Голубая рамка — только у панели, выбранной ПКМ (не при общем откреплении)
function ns.IsSelected(key) return ns.unlocked[key] == true end

-- Открепили главный блок — открепляется и фрейм цели (и закрепляются вместе)
local UNLOCK_LINKS = { main = { "target" } }

function ns.ToggleUnlock(key)
    local on = not ns.unlocked[key]
    ns.unlocked[key] = on or nil
    for _, k in ipairs(UNLOCK_LINKS[key] or {}) do ns.unlocked[k] = on or nil end
    for _, fn in ipairs(ns.unlockHooks) do pcall(fn) end -- nil = обновить всех
end

function ns.ClearUnlocks()
    wipe(ns.unlocked)
    for _, fn in ipairs(ns.unlockHooks) do pcall(fn) end
end

-- Голубая рамка поверх фрейма (тоньше не бывает: 1px + лёгкая заливка)
function ns.MoveGlow(parent, pad)
    pad = pad or 2
    local g = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    g:SetPoint("TOPLEFT", parent, "TOPLEFT", -pad, pad)
    g:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", pad, -pad)
    g:SetFrameLevel(parent:GetFrameLevel() + 20)
    g:EnableMouse(false)
    g:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    g:SetBackdropColor(MOVE_BLUE[1], MOVE_BLUE[2], MOVE_BLUE[3], 0.10)
    g:SetBackdropBorderColor(MOVE_BLUE[1], MOVE_BLUE[2], MOVE_BLUE[3], 0.95)
    g:Hide()
    return g
end

-- =============================================
-- Скруглённые углы. Квадратный backdrop заменяется двумя текстурами
-- (рамка + фон) под масками со скруглёнными углами из Media\.
-- Маска растягивается на фрейм, поэтому под каждый размер подбирается файл
-- с подходящими пропорциями (aspect) и радиусом (% от высоты).
-- =============================================
local MEDIA = "Interface\\AddOns\\RogueTick\\Media\\"
local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local ASPECTS = { 1, 2, 4, 8, 16, 32, 64 }
local RATIOS = { 50, 35, 25, 17, 10 }
local roundAnchors = {}

function ns.Radius()
    local r = EnergyTickSettings and EnergyTickSettings.radius
    return type(r) == "number" and r or 3
end

local function MaskFile(w, h, R)
    if not (w and h) or w <= 1 or h <= 1 or R <= 0 then return nil end
    local a, bestA, bestD = w / h, 1, math.huge
    for _, v in ipairs(ASPECTS) do
        local d = math.abs(math.log(math.max(a, 1)) - math.log(v))
        if d < bestD then bestA, bestD = v, d end
    end
    local p, bestP = math.min(0.5, R / h) * 100, 50
    bestD = math.huge
    for _, v in ipairs(RATIOS) do
        local d = math.abs(p - v)
        if d < bestD then bestP, bestD = v, d end
    end
    return MEDIA.."r"..bestP.."_a"..bestA
end

local function RefreshItem(it)
    local w, h = it.a:GetSize()
    -- в бою размер полосы, зависящей от защищённых значений, игра может отдать «секретным» —
    -- считать с ним нельзя; маску оставляем прежней, обновится, когда размер станет обычным
    if issecret(w) or issecret(h) then return end
    w, h = (w or 0) + 2 * it.pad, (h or 0) + 2 * it.pad
    local R = ns.Radius()
    if R > 0 then R = math.max(0, math.min(R + it.adj, h / 2)) end
    local file = (R > 0) and MaskFile(w, h, R) or nil
    if file ~= it.file or it.file == nil then
        it.file = file
        it.m:SetTexture(file or WHITE8, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    end
end

local function OnAnchorSize(self)
    for _, it in ipairs(self.rItems) do RefreshItem(it) end
end

-- Маска на владельце owner, по размеру anchor (+pad со всех сторон); adj — поправка радиуса
local function NewMask(owner, anchor, pad, adj)
    local m = owner:CreateMaskTexture()
    m:SetPoint("TOPLEFT", anchor, "TOPLEFT", -pad, pad)
    m:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", pad, -pad)
    local it = { m = m, a = anchor, pad = pad, adj = adj or pad }
    if not anchor.rItems then
        anchor.rItems = {}
        table.insert(roundAnchors, anchor)
        if anchor.HookScript then anchor:HookScript("OnSizeChanged", OnAnchorSize) end
    end
    table.insert(anchor.rItems, it)
    RefreshItem(it)
    return m
end

-- =============================================
-- Кольцо (рамка) из 8 кусков: 4 скруглённых угла (четверти кольца из Media\ring_R_t)
-- и 4 прямые стороны. Внутри пусто — поэтому фон может быть хоть прозрачным.
-- =============================================
local function RingFile(R, t)
    if R < t then R = t end
    R = math.min(12, R)
    t = math.min(4, t, R)
    return MEDIA.."ring_"..R.."_"..t
end

local QUAD = {
    TOPLEFT = { 0, 0.5, 0, 0.5 }, TOPRIGHT = { 0.5, 1, 0, 0.5 },
    BOTTOMLEFT = { 0, 0.5, 0.5, 1 }, BOTTOMRIGHT = { 0.5, 1, 0.5, 1 },
}

-- Кольцо вокруг target (pad > 0 — снаружи, 0 — по краю внутри)
local function NewRing(target, pad, level)
    local r = CreateFrame("Frame", nil, target)
    r:SetPoint("TOPLEFT", target, "TOPLEFT", -pad, pad)
    r:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", pad, -pad)
    r:SetFrameLevel(target:GetFrameLevel() + (level or 5))
    r:EnableMouse(false)
    r.pad = pad
    r.c, r.e = {}, {}
    for k in pairs(QUAD) do
        local t = r:CreateTexture(nil, "BORDER")
        t:SetPoint(k, r, k, 0, 0)
        r.c[k] = t
    end
    for _, k in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = r:CreateTexture(nil, "BORDER"); t:SetTexture(WHITE8)
        r.e[k] = t
    end
    r.col = { 1, 1, 1, 1 }
    function r:SetRing(R, t)
        if R == self.R and t == self.t then return end
        self.R, self.t = R, t
        local cs = (R > 0) and math.max(R, t) or t -- размер угла
        for k, tex in pairs(self.c) do
            tex:SetSize(cs, cs)
            if R > 0 then
                local q = QUAD[k]
                tex:SetTexture(RingFile(R, t)); tex:SetTexCoord(q[1], q[2], q[3], q[4])
            else
                tex:SetTexture(WHITE8); tex:SetTexCoord(0, 1, 0, 1)
            end
        end
        local c, e = self.c, self.e
        e.TOP:ClearAllPoints(); e.TOP:SetPoint("TOPLEFT", c.TOPLEFT, "TOPRIGHT"); e.TOP:SetPoint("TOPRIGHT", c.TOPRIGHT, "TOPLEFT"); e.TOP:SetHeight(t)
        e.BOTTOM:ClearAllPoints(); e.BOTTOM:SetPoint("BOTTOMLEFT", c.BOTTOMLEFT, "BOTTOMRIGHT"); e.BOTTOM:SetPoint("BOTTOMRIGHT", c.BOTTOMRIGHT, "BOTTOMLEFT"); e.BOTTOM:SetHeight(t)
        e.LEFT:ClearAllPoints(); e.LEFT:SetPoint("TOPLEFT", c.TOPLEFT, "BOTTOMLEFT"); e.LEFT:SetPoint("BOTTOMLEFT", c.BOTTOMLEFT, "TOPLEFT"); e.LEFT:SetWidth(t)
        e.RIGHT:ClearAllPoints(); e.RIGHT:SetPoint("TOPRIGHT", c.TOPRIGHT, "BOTTOMRIGHT"); e.RIGHT:SetPoint("BOTTOMRIGHT", c.BOTTOMRIGHT, "TOPRIGHT"); e.RIGHT:SetWidth(t)
    end
    -- Цвет (подходит и секретный — значения просто передаются в сеттер)
    function r:SetBackdropBorderColor(cr, cg, cb, ca)
        for _, tex in pairs(self.c) do tex:SetVertexColor(cr, cg, cb, ca) end
        for _, tex in pairs(self.e) do tex:SetVertexColor(cr, cg, cb, ca) end
    end
    r:Hide()
    return r
end

-- =============================================
-- Общий вид фона и рамок (настраивается в меню)
--   bgGray  — 0 чёрный … 0.5 серый;  bgAlpha — 0 прозрачный … 1 сплошной
--   borderStyle — flat (плоская) | light (светлая) | shadow (с тенью) | classic (классика) | none
--   borderSize  — толщина 1…4
-- =============================================
local styled = {}
ns.styleHooks = {}
ns.BORDER_STYLES = { "flat", "light", "shadow", "classic", "none" }
ns.BORDER_NAMES = { flat = "Плоская", light = "Светлая", shadow = "С тенью", classic = "Классика", none = "Без рамки" }

local function Style()
    local S = EnergyTickSettings or {}
    return S.bgGray or 0, S.bgAlpha or 0.9, S.borderStyle or "flat", S.borderSize or 1
end

local BORDER_COL = { flat = { 0.22, 0.22, 0.22, 1 }, light = { 0.50, 0.50, 0.50, 0.9 },
                     shadow = { 0, 0, 0, 0.95 }, classic = { 0.70, 0.70, 0.70, 1 } }

local function DefaultBorder(frame)
    local _, _, st = Style()
    return BORDER_COL[st] or BORDER_COL.flat
end

local function SetFillInset(frame, n)
    local it = frame.rFillItem
    it.pad, it.adj = -n, -n
    it.m:ClearAllPoints()
    it.m:SetPoint("TOPLEFT", frame, "TOPLEFT", n, -n); it.m:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -n, n)
    frame.rBg:ClearAllPoints()
    frame.rBg:SetPoint("TOPLEFT", n, -n); frame.rBg:SetPoint("BOTTOMRIGHT", -n, n)
    it.file = nil; RefreshItem(it)
end

local function ClassicResize(frame)
    local cl = frame.rClassic
    if not (cl and cl:IsShown()) then return end
    local w, h = frame:GetSize()
    if issecret(w) or issecret(h) then return end
    local E = math.max(6, math.min(14, math.floor(math.min(w or 0, h or 0) / 2 + 6)))
    if E ~= cl.E then
        cl.E = E
        local p = math.floor(E * 0.35)
        cl:ClearAllPoints()
        cl:SetPoint("TOPLEFT", frame, "TOPLEFT", -p, p); cl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", p, -p)
        cl:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = E })
        local c = cl.col or BORDER_COL.classic
        cl:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
    end
end

-- Применить общий вид к одному фрейму
function ns.StyleFrame(frame)
    if not frame.rBg then return end
    local gray, alpha, st, size = Style()
    local R = ns.Radius()
    if frame.rSkip then -- невидимая оболочка (фрейм игрока в едином блоке)
        frame.rBg:SetVertexColor(0, 0, 0, 0)
        frame.rRing:Hide(); frame.rShadow:Hide()
        if frame.rClassic then frame.rClassic:Hide() end
        return
    end
    frame.rBg:SetVertexColor(gray, gray, gray, alpha)
    local inside = (st == "flat" or st == "light" or st == "shadow")
    frame.rRing:SetShown(inside)
    if inside then frame.rRing:SetRing(R, size) end
    SetFillInset(frame, inside and size or 0)
    -- тень: мягкое тёмное кольцо снаружи
    frame.rShadow:SetShown(st == "shadow")
    if st == "shadow" then frame.rShadow:SetRing(R + 2, 2); frame.rShadow:SetBackdropBorderColor(0, 0, 0, 0.45) end
    -- классика: рамка как у подсказок Blizzard
    if st == "classic" then
        if not frame.rClassic then
            local cl = CreateFrame("Frame", nil, frame, BackdropTemplateMixin and "BackdropTemplate" or nil)
            cl:SetFrameLevel(frame:GetFrameLevel() + 5); cl:EnableMouse(false)
            frame.rClassic = cl
            frame:HookScript("OnSizeChanged", ClassicResize)
        end
        frame.rClassic:Show(); frame.rClassic.E = nil
        ClassicResize(frame)
    elseif frame.rClassic then
        frame.rClassic:Hide()
    end
    ns.ResetBorder(frame)
end

-- Вернуть рамке обычный цвет (после подсветки/наведения)
function ns.ResetBorder(frame)
    if not frame.rRing or frame.rSkip then return end
    local c = DefaultBorder(frame)
    frame:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
end

-- Скруглить фон/рамку фрейма. SetBackdropColor/BorderColor продолжают работать.
function ns.Round(frame)
    if frame.rBg then return frame end
    if frame.ClearBackdrop then pcall(frame.ClearBackdrop, frame)
    elseif frame.SetBackdrop then pcall(frame.SetBackdrop, frame, nil) end
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
    fill:SetTexture(WHITE8)
    fill:SetPoint("TOPLEFT", 1, -1); fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:AddMaskTexture(NewMask(frame, frame, -1, -1))
    frame.rFillItem = frame.rItems[#frame.rItems]
    frame.rBg = fill
    frame.rRing = NewRing(frame, 0, 5)
    frame.rShadow = NewRing(frame, 2, 0)
    frame.SetBackdropColor = function(self, ...) self.rBg:SetVertexColor(...) end
    frame.SetBackdropBorderColor = function(self, cr, cg, cb, ca)
        self.rRing:SetBackdropBorderColor(cr, cg, cb, ca)
        if self.rClassic then
            self.rClassic.col = { cr, cg, cb, ca }
            pcall(self.rClassic.SetBackdropBorderColor, self.rClassic, cr, cg, cb, ca)
        end
    end
    table.insert(styled, frame)
    ns.StyleFrame(frame)
    return frame
end

-- Скруглить заливку StatusBar (и доп. текстуры — например, её фон)
function ns.RoundFill(bar, extra, adj)
    local m = NewMask(bar, bar, 0, adj or -1)
    local t = bar:GetStatusBarTexture()
    if t then t:AddMaskTexture(m) end
    for _, tex in ipairs(extra or {}) do tex:AddMaskTexture(m) end
    return m
end

-- Скруглить любые текстуры по размеру фрейма anchor (маска живёт на owner)
function ns.RoundTex(owner, anchor, texs, adj)
    local m = NewMask(owner, anchor, 0, adj or -1)
    for _, tex in ipairs(texs) do tex:AddMaskTexture(m) end
    return m
end

-- Скруглённое свечение вокруг фрейма (кольцо pad px). Понимает SetBackdropBorderColor.
local glowRings = {}
function ns.RoundRing(frame, pad)
    local r = NewRing(frame, pad, 6)
    r:SetRing(ns.Radius() + pad, pad)
    table.insert(glowRings, r)
    return r
end

-- Пересчитать скругление и вид всех фреймов (сменились радиус/фон/рамки)
function ns.ApplyRound()
    for _, a in ipairs(roundAnchors) do
        for _, it in ipairs(a.rItems) do it.file = nil; RefreshItem(it) end
    end
    for _, r in ipairs(glowRings) do r.R = nil; r:SetRing(ns.Radius() + r.pad, r.pad) end
    for _, fr in ipairs(styled) do fr.rRing.R = nil; fr.rShadow.R = nil; ns.StyleFrame(fr) end
    for _, fn in ipairs(ns.styleHooks) do pcall(fn) end
end

-- Звуки на выбор (у капа энергии и при агро)
ns.SOUNDS = {
    { id = 569595, name = "Тик" },
    { id = 8959,   name = "Колокол" },
    { id = 8960,   name = "Готовность" },
    { id = 12867,  name = "Будильник" },
    { id = 856,    name = "Щелчок" },
}
function ns.SoundName(id)
    for _, s in ipairs(ns.SOUNDS) do if s.id == id then return s.name end end
    return tostring(id)
end
function ns.NextSound(id)
    for i, s in ipairs(ns.SOUNDS) do if s.id == id then return ns.SOUNDS[i % #ns.SOUNDS + 1].id end end
    return ns.SOUNDS[1].id
end

-- Звук: soundID может быть и SoundKit, и FileDataID — пробуем оба.
function ns.PlayTick(id, channel)
    local ok, willPlay = pcall(PlaySound, id, channel)
    if not (ok and willPlay) then pcall(PlaySoundFile, id, channel) end
end

-- =============================================
-- Позиции фреймов: всегда храним как смещение центра от центра UIParent.
-- (GetPoint() после перетаскивания отдаёт другую точку привязки -> фрейм "прыгал")
-- =============================================
function ns.SavePos(frame, tbl, kx, ky)
    local fx, fy = frame:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (fx and ux) then return end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    tbl[kx], tbl[ky] = math.floor(fx * s - ux + 0.5), math.floor(fy * s - uy + 0.5)
    ns.RestorePos(frame, tbl, kx, ky)
    return true
end

function ns.RestorePos(frame, tbl, kx, ky)
    if tbl[kx] == nil or tbl[ky] == nil then return false end
    local s = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", tbl[kx] / s, tbl[ky] / s)
    return true
end

-- =============================================
-- Пинг: GetNetStats обновляется раз в ~30с -> сглаживаем, чтобы зона не прыгала,
-- и оцениваем разброс (джиттер) для запаса.
-- =============================================
local latSmooth, latJitter = nil, 0
function ns.UpdateLatency(elapsed)
    local _, _, _, world = GetNetStats()
    local sample = (world or 0) / 1000
    if not latSmooth then latSmooth = sample; return end
    local k = math.min(1, (elapsed or 0) * 0.5) -- постоянная времени ~2с
    latJitter = latJitter + (math.abs(sample - latSmooth) - latJitter) * k
    latSmooth = latSmooth + (sample - latSmooth) * k
end
function ns.Latency() return latSmooth or 0 end

-- =============================================
-- «Поздно для Kick»: тёмная полоска в конце каста цели. Kick, нажатый там, с пингом уже не успеет.
-- Kick не откатится до конца каста — весь каст серый («не сбить»), зоны нет.
-- =============================================
-- запас сверх пинга: 0,1 с + удвоенный разброс пинга (нестабильная связь — зона шире), не больше 0,3
function ns.KickLate() return ns.Latency() + 0.1 + math.min(0.2, 2 * (latJitter or 0)) end
function ns.KickZoneOn() return not (EnergyTickSettings and EnergyTickSettings.castKickZone == false) end
-- Kick успеет до конца каста (e)? Откат скрыт игрой — считаем, что успеет.
local kNow, kLeft, kKnown -- откат Kick: читаем раз за кадр (рамка цели и полоса над головой)
function ns.KickInTime(now, e)
    if not ns.KickLeft then return true end
    if kNow ~= now then kNow = now; kLeft, kKnown = ns.KickLeft(now) end
    if not kKnown then return true end
    return not (kLeft and kLeft > 0 and now + kLeft > e - ns.KickLate())
end
-- текстура зоны поверх полосы (лениво; маска — та же, что у заливки)
function ns.KickZoneTex(bar)
    local z = bar.kickZone
    if z then return z end
    z = bar:CreateTexture(nil, "OVERLAY", nil, -1)
    z:SetColorTexture(0, 0, 0, 0.5)
    if bar.mask then z:AddMaskTexture(bar.mask) end
    z:Hide()
    bar.kickZone = z
    return z
end
-- s, e — начало и конец каста; канал идёт справа налево — зона слева
function ns.KickZone(bar, s, e, channel)
    local z = ns.KickZoneTex(bar)
    local total = e - s
    local w = bar:GetWidth()
    if total <= 0 or not w or issecret(w) or w <= 0 then z:Hide(); return end
    local zw = math.min(w, w * ns.KickLate() / total)
    if zw < 1 then z:Hide(); return end
    if z.ch ~= channel then
        z.ch = channel
        z:ClearAllPoints()
        if channel then z:SetPoint("TOPLEFT", bar, "TOPLEFT"); z:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT")
        else z:SetPoint("TOPRIGHT", bar, "TOPRIGHT"); z:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT") end
    end
    z:SetWidth(zw); z:Show()
end
function ns.KickZoneHide(bar) if bar.kickZone then bar.kickZone:Hide() end end

-- =============================================
-- Slice and Dice: читаем бафф, когда можно; в бою (баффы скрыты) — считаем сами.
-- Скан аур кэшируется и обновляется по UNIT_AURA, а не каждый кадр.
-- =============================================
local SND_IDS = { [5171] = true, [6774] = true }
local SND_NAME = "Slice and Dice"
do
    local ok, n = pcall(function()
        if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(5171) end
        if GetSpellInfo then return (GetSpellInfo(5171)) end
    end)
    if ok and type(n) == "string" and n ~= "" then SND_NAME = n end
end

-- Бросает ошибку, если данные ауры секретные (ловится pcall).
local function ScanSnD()
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local a = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not a then return false end
            if SND_IDS[a.spellId] or a.name == SND_NAME then
                if issecret(a.duration) or issecret(a.expirationTime) then error("secret") end
                return true, a.duration, a.expirationTime
            end
        end
        return false
    end
    for i = 1, 40 do
        local n, _, _, _, d, e, _, _, _, sid = UnitBuff("player", i)
        if not n then return false end
        if SND_IDS[sid] or n == SND_NAME then return true, d, e end
    end
    return false
end

local scan = { valid = false, t = 0 }
local function CachedScan(now)
    if not scan.valid or now - scan.t > 1 then
        scan.ok, scan.found, scan.d, scan.e = pcall(ScanSnD)
        scan.valid, scan.t = true, now
    end
    return scan.ok, scan.found, scan.d, scan.e
end

local sndEst = { dur = 0, exp = 0, castAt = 0, cp = nil, cpKnown = false, learn = false }
local lastReadableCP, cpAtSend, cpAtSendKnown = nil, nil, false

local function SndBase(cp) return 6 + 3 * cp end -- 9с на 1 CP ... 21с на 5 CP

-- Возвращает duration, expirationTime (или nil). Третий результат: true = это оценка.
function ns.GetSnD()
    local now = GetTime()
    local ok, found, d, e = CachedScan(now)
    if ok and found and e and e > 0 then
        -- Учимся множителю (Improved Slice and Dice) только если CP были реально известны
        if sndEst.learn and sndEst.cpKnown and d and d > 0 and now - sndEst.castAt < 5 then
            local mult = d / SndBase(sndEst.cp)
            if mult >= 0.95 and mult <= 1.6 then EnergyTickSettings.sndMult = mult end
            sndEst.learn = false
        end
        sndEst.dur, sndEst.exp = d, e
        return d, e, false
    end
    -- Вне боя "не найдено" — правда; в бою баффы могут быть просто скрыты
    if ok and not found and not UnitAffectingCombat("player") then
        sndEst.exp = 0
        return nil
    end
    if sndEst.exp > now then return sndEst.dur, sndEst.exp, true end
    return nil
end

local sndWatch = CreateFrame("Frame")
sndWatch:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
sndWatch:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
sndWatch:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
sndWatch:RegisterUnitEvent("UNIT_AURA", "player")
sndWatch:RegisterEvent("PLAYER_REGEN_ENABLED")
sndWatch:RegisterEvent("PLAYER_REGEN_DISABLED")
sndWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
sndWatch:SetScript("OnEvent", function(_, ev, unit, ...)
    if ev == "UNIT_AURA" or ev == "PLAYER_REGEN_ENABLED" or ev == "PLAYER_REGEN_DISABLED" or ev == "PLAYER_ENTERING_WORLD" then
        scan.valid = false
    elseif ev == "UNIT_POWER_UPDATE" then
        local cp, okc = ns.Read(UnitPower, "player", 4)
        if okc then lastReadableCP = cp end
    elseif ev == "UNIT_SPELLCAST_SENT" then
        local cp, okc = ns.Read(UnitPower, "player", 4)
        if okc then cpAtSend, cpAtSendKnown = cp, true
        else cpAtSend, cpAtSendKnown = lastReadableCP, false end
    elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
        local spellID = select(2, ...)
        local okId, isSnd = pcall(function() return SND_IDS[spellID] end)
        if okId and isSnd then
            local cp, known = cpAtSend, cpAtSendKnown
            if not cp or cp < 1 then cp, known = 5, false end -- CP скрыты и неизвестны: считаем от 5
            local now = GetTime()
            sndEst.cp, sndEst.cpKnown, sndEst.castAt, sndEst.learn = cp, known, now, true
            sndEst.dur = SndBase(cp) * (EnergyTickSettings.sndMult or 1)
            sndEst.exp = now + sndEst.dur
            scan.valid = false
        end
    end
end)
