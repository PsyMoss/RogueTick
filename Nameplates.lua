-- =============================================
-- НАД ГОЛОВОЙ: свои полоски вместо стандартных Blizzard — в стиле аддона.
--   «Полоса»: имя сверху, тонкая скруглённая полоса жизни (% справа), каст снизу.
--   «Кубик»:  маленький квадрат с % жизни — зелёный / жёлтый / красный. Почти не мешает.
-- Цвет полосы — кто это (класс игрока / враг / нейтрал), длина — жизнь; ниже 35% ярче, ниже 15% пульс.
-- Свои (союзники) — только имя цветом класса, без полосы: видно, кто где стоит.
-- Цель — светлая рамка; остальные чуть бледнее.
-- Значения, скрытые игрой в бою, показываются как есть (без цвета по %).
-- =============================================
local ADDON, ns = ...
local issecret, Read = ns.issecret, ns.Read

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

local function S() return EnergyTickSettings end
local function On() return S().npOn ~= false end

-- ---------- цвета (по стилю: мягкий цвет / монохром) ----------
local SOFT = {
    good = { 0.42, 0.72, 0.46 }, -- рамка: цель отравлена
    hostile = { 0.76, 0.36, 0.34 }, neutral = { 0.84, 0.74, 0.40 }, friendly = { 0.42, 0.68, 0.46 },
    tapped = { 0.45, 0.45, 0.45 }, kick = ns.ACT.kick, locked = { 0.55, 0.55, 0.55 },
}
local MONO = {
    good = { 0.62, 0.62, 0.62 },
    hostile = { 0.62, 0.62, 0.62 }, neutral = { 0.62, 0.62, 0.62 }, friendly = { 0.62, 0.62, 0.62 },
    tapped = { 0.35, 0.35, 0.35 }, kick = { 0.75, 0.75, 0.75 }, locked = { 0.45, 0.45, 0.45 },
}
local function C(key) return ((S().barStyle == "soft") and SOFT or MONO)[key] end
-- % жизни в «кубике» — всегда цветной (иначе в монохроме не отличить)
local function PctColor(p) return ns.HealthColorPct(p) end

local Yes, Hex = ns.Yes, ns.Hex

-- ---------- одна полоска ----------
local plates = {} -- [Blizzard nameplate] = наш фрейм

local function Box(fr, a)
    fr:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    fr:SetBackdropColor(0, 0, 0, a or 0.85); fr:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
    ns.Round(fr)
end

local function NewBar(parent)
    local b = CreateFrame("StatusBar", nil, parent)
    b:SetStatusBarTexture(WHITE); b:SetMinMaxValues(0, 1); b:SetValue(1)
    b:SetPoint("TOPLEFT", 1, -1); b:SetPoint("BOTTOMRIGHT", -1, 1)
    local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(b); bg:SetColorTexture(1, 1, 1, 0.05)
    b.mask = ns.RoundFill(b, { bg })
    return b
end

local function Text(parent, size)
    local t = parent:CreateFontString(nil, "OVERLAY")
    ns.SetFont(t, size); t:SetTextColor(1, 1, 1); t:SetWordWrap(false)
    return t
end

local function Create(plate)
    local o = CreateFrame("Frame", nil, plate)
    o:SetPoint("CENTER", plate, "CENTER", 0, 0)
    -- масштаб игры по расстоянию не применяем: размер постоянный, рамки не «дышат»
    if o.SetIgnoreParentScale then o:SetIgnoreParentScale(true) end
    o.plate = plate
    o:SetSize(110, 20)
    o:EnableMouse(false)

    o.hpBox = CreateFrame("Frame", nil, o, BACKDROP); Box(o.hpBox, 0.85)
    o.hp = NewBar(o.hpBox)
    local top = CreateFrame("Frame", nil, o); top:SetAllPoints(o); top:SetFrameLevel(o.hp:GetFrameLevel() + 3)
    o.pct = Text(top, 9); o.pct:SetTextColor(0.72, 0.72, 0.72)
    o.name = Text(top, 9)
    -- метка рейда (череп, крест…) — справа от полосы
    o.raid = top:CreateTexture(nil, "OVERLAY")
    o.raid:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons"); o.raid:Hide()

    o.castBox = CreateFrame("Frame", nil, o, BACKDROP); Box(o.castBox, 0.85)
    o.cast = NewBar(o.castBox)
    o.castName = Text(top, 8)
    o.castBox:Hide(); o.castName:Hide()

    -- комбо-точки (только на цели), под полосой жизни
    -- «ваш блок» на цели: ваша энергия + комбо (под жизнью и кастом моба)
    o.mine = CreateFrame("Frame", nil, o)
    o.enBox = CreateFrame("Frame", nil, o.mine, BACKDROP); Box(o.enBox, 0.85)
    o.en = NewBar(o.enBox)
    o.mine:Hide()
    o.cp = {}
    for i = 1, 5 do
        -- ячейка как на основном блоке: скруглённая рамка + заливка
        local c = CreateFrame("Frame", nil, o.mine, BACKDROP); Box(c, 0.85)
        c.fill = NewBar(c); c.fill:SetValue(1)
        -- серый фильтр поверх заливки (когда энергия скрыта — цвет/прозрачность считает игра)
        c.dim = c.fill:CreateTexture(nil, "OVERLAY")
        c.dim:SetAllPoints(c.fill:GetStatusBarTexture()); c.dim:SetColorTexture(1, 1, 1, 1)
        if c.fill.mask then c.dim:AddMaskTexture(c.fill.mask) end
        c.dim:Hide()
        c:Hide()
        o.cp[i] = c
    end
    -- сап: иконка слева от полосы, с таймером
    o.sap = CreateFrame("Frame", nil, o, BACKDROP)
    o.sap:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 }); o.sap:SetBackdropBorderColor(0, 0, 0, 1)
    o.sap.icon = o.sap:CreateTexture(nil, "ARTWORK")
    o.sap.icon:SetPoint("TOPLEFT", 1, -1); o.sap.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    o.sap.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    o.sap.cd = CreateFrame("Cooldown", nil, o.sap, "CooldownFrameTemplate")
    o.sap.cd:SetAllPoints(o.sap.icon); o.sap.cd:SetDrawEdge(false)
    if o.sap.cd.SetHideCountdownNumbers then o.sap.cd:SetHideCountdownNumbers(false) end
    o.sap:Hide()

    -- аура вокруг цели (жизнь + комбо) цветом совета «Удар»


    o.acc = 1
    o:Hide()
    return o
end

-- Раскладка по режиму
local function Layout(o)
    local s = S()
    local cube = s.npMode == "cube"
    o.cube = cube
    o.hpBox:ClearAllPoints(); o.name:ClearAllPoints(); o.pct:ClearAllPoints()
    if cube then
        local w, h = s.npCubeW or 34, s.npCubeH or 16
        o:SetSize(w, h)
        o.hpBox:SetAllPoints(o)
        o.hp:Hide()
        o.pct:SetPoint("CENTER", o.hpBox, "CENTER", 0, 0)
        ns.SetFont(o.pct, math.max(8, math.min(14, h - 4)))
        o.name:SetPoint("BOTTOM", o.hpBox, "TOP", 0, 2)
        o.name:SetShown((s.npCubeName or s.npLevel ~= false) and true or false)
    else
        local w, h = s.npWidth or 110, s.npHP or 8
        o:SetSize(w, h + 2)
        o.hpBox:SetAllPoints(o)
        o.hp:Show()
        o.pct:SetPoint("RIGHT", o.hpBox, "RIGHT", -3, 0)
        ns.SetFont(o.pct, math.max(7, math.min(11, h)))
        o.name:SetPoint("BOTTOM", o.hpBox, "TOP", 0, 2)
        o.name:SetWidth(w + 20)
        o.name:SetShown(s.npName ~= false or s.npLevel ~= false)
    end
    o.pct:SetShown((cube or s.npPct ~= false) and not s.noNumbers)
    -- каст — под жизнью
    local ch = s.npCastH or 6
    o.castBox:ClearAllPoints()
    o.castBox:SetPoint("TOPLEFT", o.hpBox, "BOTTOMLEFT", 0, -2)
    o.castBox:SetPoint("TOPRIGHT", o.hpBox, "BOTTOMRIGHT", 0, -2)
    if cube then o.castBox:SetWidth(math.max(s.npCubeW or 34, 60)) end
    o.castBox:SetHeight(ch + 2)
    o.castName:ClearAllPoints(); o.castName:SetPoint("TOP", o.castBox, "BOTTOM", 0, -1)
    -- сап: квадрат слева от полосы
    local sz = math.max(16, (cube and (s.npCubeH or 16) or (s.npHP or 8)) + 8)
    o.sap:ClearAllPoints(); o.sap:SetSize(sz, sz)
    o.sap:SetPoint("RIGHT", o.hpBox, "LEFT", -3, 0)
    o.raid:ClearAllPoints(); o.raid:SetSize(sz - 2, sz - 2)
    o.raid:SetPoint("LEFT", o.hpBox, "RIGHT", 3, 0)
    -- ваш блок: энергия, под ней 5 ячеек комбо — во всю ширину полосы (у кубика не уже 60)
    local rowW = cube and math.max(s.npCubeW or 34, 60) or (s.npWidth or 110)
    local eh = (s.npEnergy ~= false) and (s.npEnH or 5) or 0
    local d = (s.npCP ~= false) and (s.npCPSize or 6) or 0
    o.mine:SetWidth(rowW)
    o.enBox:ClearAllPoints()
    o.enBox:SetPoint("TOPLEFT", o.mine, "TOPLEFT", 0, 0); o.enBox:SetPoint("TOPRIGHT", o.mine, "TOPRIGHT", 0, 0)
    o.enBox:SetHeight(eh + 2); o.enBox:SetShown(eh > 0)
    local gap = 2
    local cw = (rowW - 4 * gap) / 5
    local cy = eh > 0 and -(eh + 2 + gap) or 0
    for i = 1, 5 do
        local c = o.cp[i]
        c:ClearAllPoints(); c:SetSize(cw, d + 2)
        c:SetPoint("TOPLEFT", o.mine, "TOPLEFT", (i - 1) * (cw + gap), cy)
        c:SetShown(d > 0)
    end
    local mh = (eh > 0 and eh + 2 or 0) + (d > 0 and d + 2 or 0) + ((eh > 0 and d > 0) and gap or 0)
    o.mine:SetHeight(math.max(1, mh))
    o.mineH = mh
    o.mineAnchor = nil
    o.col = nil
    if o.friendOnly then o.pct:Hide() end
end

-- ---------- Blizzard: прячем свою полоску, пока включены наши ----------
local function BlizzFrame(plate) return plate and plate.UnitFrame end
local function HideBlizz(plate)
    local uf = BlizzFrame(plate)
    if not uf then return end
    if not uf.rtHooked then
        uf.rtHooked = true
        uf:HookScript("OnShow", function(self) if On() then pcall(self.Hide, self) end end)
    end
    pcall(uf.Hide, uf)
end
local function ShowBlizz(plate)
    local uf = BlizzFrame(plate)
    if uf then pcall(uf.Show, uf) end
end

-- ---------- данные ----------
local function UnitColor(u)
    if S().barStyle == "soft" then return (ns.WhoColor(u)) end
    if Yes(UnitIsTapDenied, u) then return C("tapped") end
    if Yes(UnitIsPlayer, u) then
        local _, cls = UnitClass(u)
        local cc = (not issecret(cls)) and cls and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
        if cc and S().barStyle == "soft" then return { cc.r * 0.85, cc.g * 0.85, cc.b * 0.85 } end
    end
    local r, ok = Read(UnitReaction, u, "player")
    if ok and type(r) == "number" then
        if r <= 3 then return C("hostile") elseif r == 4 then return C("neutral") end
        return C("friendly")
    end
    if Yes(UnitCanAttack, "player", u) then return C("hostile") end
    return C("friendly")
end

-- «12», «12+», «??»: цвет сложности, приглушённый (смешан с серым)
local function LevelText(u)
    local lvl, ok = Read(UnitLevel, u)
    if not ok or type(lvl) ~= "number" then return "" end
    local txt = lvl < 0 and "??" or tostring(lvl)
    local cl, okC = Read(UnitClassification, u)
    if okC and type(cl) == "string" then
        if cl == "elite" or cl == "rareelite" then txt = txt.."+"
        elseif cl == "worldboss" then txt = "??" end
    end
    local r, g, b = 0.7, 0.7, 0.7
    if lvl < 0 then r, g, b = 0.78, 0.40, 0.38
    else
        local fn = GetCreatureDifficultyColor or GetQuestDifficultyColor
        if fn then
            local okD, c = pcall(fn, lvl)
            if okD and type(c) == "table" and c.r then r, g, b = c.r, c.g, c.b end
        end
    end
    local m = 0.35 -- приглушить
    return Hex({ r + (0.6 - r) * m, g + (0.6 - g) * m, b + (0.6 - b) * m })..txt.."|r"
end

-- ---------- ауры: ваш яд и сап ----------
local POISON_IDS = {}
for _, id in ipairs({ 8680, 8685, 8689, 11335, 11336, 11337, 2818, 2819, 11353, 11354, 25349,
    3409, 11201, 5760, 8692, 11398, 13218, 13222, 13223, 13224 }) do POISON_IDS[id] = true end
local SAP_IDS = { [6770] = true, [2070] = true, [11297] = true }
local SAP_NAME
do
    local ok, n = pcall(function()
        if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(6770) end
        if GetSpellInfo then return (GetSpellInfo(6770)) end
    end)
    if ok and type(n) == "string" then SAP_NAME = n end
end

local function Plain(v) return v ~= nil and not issecret(v) end

local function ScanAuras(o)
    local u, s = o.unit, S()
    o.poisoned = false
    local sap
    if u and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        if s.npPoison ~= false then
            for i = 1, 40 do
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, "HARMFUL|PLAYER")
                if not ok or not a then break end
                local dn, id = a.dispelName, a.spellId
                if (Plain(dn) and dn == "Poison") or (Plain(id) and POISON_IDS[id]) then o.poisoned = true; break end
            end
        end
        if s.npSap ~= false then
            for i = 1, 40 do
                local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, u, i, "HARMFUL")
                if not ok or not a then break end
                local id, nm = a.spellId, a.name
                if (Plain(id) and SAP_IDS[id]) or (Plain(nm) and SAP_NAME and nm == SAP_NAME) then sap = a; break end
            end
        end
    end
    if sap then
        if not pcall(o.sap.icon.SetTexture, o.sap.icon, sap.icon) then o.sap.icon:SetTexture(132310) end
        local dur, exp = sap.duration, sap.expirationTime
        if Plain(dur) and Plain(exp) and dur > 0 then
            o.sap.cd:SetCooldown(exp - dur, dur); o.sap.cd:Show()
        elseif C_UnitAuras.GetUnitAuraDuration and o.sap.cd.SetCooldownFromDurationObject then
            local ok = pcall(function()
                o.sap.cd:SetCooldownFromDurationObject(C_UnitAuras.GetUnitAuraDuration(u, sap.auraInstanceID))
            end)
            o.sap.cd:SetShown(ok)
        else
            o.sap.cd:Hide()
        end
        o.sap:Show()
    else
        o.sap:Hide()
    end
end

-- комбо-очки на цели (если прочитать нельзя — не показываем)
local CP_ON, CP_FULL = { 0.82, 0.52, 0.44 }, { 0.97, 0.68, 0.56 }
local CP_ON_M, CP_FULL_M = { 0.60, 0.60, 0.60 }, { 0.92, 0.92, 0.92 }
local function ComboPoints()
    local v, ok
    if GetComboPoints then v, ok = Read(GetComboPoints, "player", "target") end
    if (not ok or type(v) ~= "number") and UnitPower then
        local pt = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
        v, ok = Read(UnitPower, "player", pt)
    end
    if ok and type(v) == "number" then return v end
end
-- комбо как есть (может быть секретным) — только для SetValue
local function ComboRaw()
    local pt = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints) or 4
    local v = Read(UnitPower, "player", pt)
    return v
end

-- ваша энергия на цели: мягкий жёлтый (в монохроме — чуть жёлтый)
local EN_SOFT, EN_MONO = { 0.82, 0.73, 0.40 }, { 0.70, 0.64, 0.42 }
local EN_WAIT = { 0.42, 0.42, 0.42 }

local ADVICE_DIM = {} -- цвет совета под серым фильтром (заполняется после ADVICE)

-- цвета совета «Удар» (комбо над головой цели)
local ADVICE = {
    ss   = ns.ACT.ss,   -- Sinister Strike — синий
    snd  = ns.ACT.snd,  -- Slice and Dice — оранжевый
    evis = ns.ACT.evis, -- Eviscerate — красный
}
-- энергии не хватает: явно серый (лишь 10% цвета — чтобы не было светомузыки)
for k, c in pairs(ADVICE) do
    ADVICE_DIM[k] = { c[1] * 0.1 + 0.42 * 0.9, c[2] * 0.1 + 0.42 * 0.9, c[3] * 0.1 + 0.42 * 0.9 }
end

local function SetFill(o, c)
    if c ~= o.col then o.col = c; o.hp:SetStatusBarColor(c[1], c[2], c[3], 0.9) end
end

local function CastTimes(fn, u)
    if not fn then return nil end
    local ok, name, _, _, s, e = pcall(fn, u)
    if not ok then return nil end
    if issecret(s) or issecret(e) then return "secret", name end
    if s and e and e > s then return s / 1000, e / 1000, name end
end

local function RefreshCast(o)
    local u = o.unit
    o.castS, o.castE = nil, nil
    if not (u and S().npCast ~= false) or o.friendOnly then o.castBox:Hide(); o.castName:Hide(); return end
    local channel = false
    local s, e, name = CastTimes(UnitCastingInfo, u)
    if not s then s, e, name = CastTimes(UnitChannelInfo, u); channel = true end
    if not s then o.castBox:Hide(); o.castName:Hide(); return end
    -- нельзя сбить — серый (как на рамке цели)
    local okN, ni = pcall(function()
        if channel then return select(7, UnitChannelInfo(u)) end
        return select(8, UnitCastingInfo(u))
    end)
    local locked = okN and not issecret(ni) and ni and true or false
    o.kickable, o.kInTime = not locked, true
    ns.KickZoneHide(o.cast)
    local col = locked and C("locked") or C("kick")
    o.cast:SetStatusBarColor(col[1], col[2], col[3], 1)
    if s == "secret" then
        local durFn = channel and UnitChannelDuration or UnitCastingDuration
        local shown = false
        if durFn and o.cast.SetTimerDuration then
            shown = pcall(function()
                local dur = durFn(u)
                if not dur then error("no") end
                o.cast:SetTimerDuration(dur)
            end)
        end
        if not shown then o.castBox:Hide(); o.castName:Hide(); return end
        o.castS, o.castE = 0, math.huge
    else
        o.castS, o.castE, o.channel = s, e, channel
        o.cast:SetMinMaxValues(0, 1)
    end
    pcall(o.castName.SetText, o.castName, name)
    o.castBox:Show(); o.castName:Show()
end

-- Каждый кадр: масштаб как у интерфейса и левый-нижний угол точно на пикселе экрана.
-- Тогда тонкие рамки не прыгают на 1px, пока полоска плывёт за мобом.
local PH = 768
local function UpdatePH()
    local ok, _, h = pcall(GetPhysicalScreenSize)
    if ok and type(h) == "number" and h > 0 then PH = h end
end
UpdatePH()

-- Полоску Blizzard измерять нельзя (игра запрещает), поэтому меряем свою.
-- Если игра запретит и это — выравнивание выключается навсегда, без ошибок.
local alignOff = false
local function PixelAlign(o)
    local plate = o.plate
    if not plate then return end
    local ui = UIParent:GetEffectiveScale()
    if o.SetIgnoreParentScale and o:GetScale() ~= ui then o:SetScale(ui) end
    if alignOff then return end
    if o.IsAnchoringRestricted and o:IsAnchoringRestricted() then alignOff = true; return end
    local ok, l, b = pcall(o.GetLeft, o)
    if ok then ok, b = pcall(o.GetBottom, o) end
    if not ok then alignOff = true; return end
    if not l or not b or issecret(l) or issecret(b) then return end
    local k = o:GetEffectiveScale() * PH / 768 -- пикселей экрана в одной единице o
    -- где был бы край без нашего сдвига
    local left, bottom = l - (o.pdx or 0), b - (o.pdy or 0)
    local dx = (math.floor(left * k + 0.5) - left * k) / k
    local dy = (math.floor(bottom * k + 0.5) - bottom * k) / k
    if math.abs(dx - (o.pdx or 0)) > 0.001 or math.abs(dy - (o.pdy or 0)) > 0.001 then
        o.pdx, o.pdy = dx, dy
        o:ClearAllPoints()
        o:SetPoint("CENTER", plate, "CENTER", dx, dy)
    end
end

local function Update(o, el)
    local u = o.unit
    if not u then return end
    PixelAlign(o)
    local now = GetTime()
    -- каст (числовой — плавно каждый кадр)
    if o.castS and o.castE ~= math.huge then
        if now >= o.castE then o.castBox:Hide(); o.castName:Hide(); o.castS = nil
        else
            local p = (now - o.castS) / (o.castE - o.castS)
            o.cast:SetValue(o.channel and (1 - p) or p)
            -- только на цели: успеет ли Kick и зона «поздно»
            if o.kickable and o.isTgt and ns.KickZoneOn() then
                local inTime = ns.KickInTime(now, o.castE)
                if inTime ~= o.kInTime then
                    o.kInTime = inTime
                    local col = inTime and C("kick") or C("locked")
                    o.cast:SetStatusBarColor(col[1], col[2], col[3], 1)
                end
                if inTime then ns.KickZone(o.cast, o.castS, o.castE, o.channel) else ns.KickZoneHide(o.cast) end
            elseif o.cast.kickZone and o.cast.kickZone:IsShown() then
                ns.KickZoneHide(o.cast)
            end
        end
    end
    o.acc = o.acc + (el or 0)
    if o.acc < 0.1 then return end
    o.acc = 0
    local s = S()

    -- метка рейда
    if s.npRaid ~= false then
        local idx, okI = Read(GetRaidTargetIndex, u)
        if okI then
            if idx ~= o.raidIdx then
                o.raidIdx = idx
                if idx then SetRaidTargetIconTexture(o.raid, idx); o.raid:Show() else o.raid:Hide() end
            end
        elseif pcall(SetRaidTargetIconTexture, o.raid, idx) then
            o.raidIdx = nil; o.raid:Show()
        else
            o.raidIdx = nil; o.raid:Hide()
        end
    elseif o.raid:IsShown() then
        o.raidIdx = nil; o.raid:Hide()
    end

    -- свои: только имя (без полосы, процентов и каста)
    local fo = s.npFriendName ~= false and ns.IsFriendUnit(u)
    if fo ~= o.friendOnly then
        o.friendOnly = fo
        o.hpBox:SetShown(not fo)
        if fo then
            o.pct:Hide(); o.castBox:Hide(); o.castName:Hide(); o.sap:Hide(); ns.HidePulse(o.hp)
        else
            o.pct:SetShown((o.cube or s.npPct ~= false) and not s.noNumbers)
            RefreshCast(o)
        end
    end

    -- жизнь
    local cur, okC = Read(UnitHealth, u)
    local max, okM = Read(UnitHealthMax, u)
    local p
    if okC and okM and max and max > 0 then p = cur / max end
    if not o.cube then
        if p then o.hp:SetMinMaxValues(0, 1); o.hp:SetValue(p)
        else pcall(o.hp.SetMinMaxValues, o.hp, 0, max); pcall(o.hp.SetValue, o.hp, cur) end
        if s.npColor == "health" and not Yes(UnitIsTapDenied, u) then
            o.col = nil; ns.PaintEnemyHP(o.hp, u, p) -- старая шкала: цвет по % жизни
        elseif s.barStyle == "soft" then
            o.col = nil; ns.PaintWhoHP(o.hp, u, p) -- кто это; ниже 35% ярче, ниже 15% пульс
        else
            ns.HidePulse(o.hp); o.hp.col = nil; SetFill(o, UnitColor(u))
        end
    end
    if o.pct:IsShown() then
        if p then
            local t = math.floor(p * 100 + 0.5)
            o.pct:SetText(o.cube and (Hex(PctColor(p))..t.."|r") or (t.."%"))
        elseif not (UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 and pcall(function()
                o.pct:SetFormattedText(o.cube and "%.0f" or "%.0f%%", UnitHealthPercent(u, false, CurveConstants.ScaleTo100))
            end)) then
            o.pct:SetText("")
        end
    end

    -- уровень (цветом сложности) + имя
    if o.name:IsShown() then
        local showName = (o.cube and s.npCubeName) or (not o.cube and s.npName ~= false)
        local lv = ""
        if s.npLevel ~= false then lv = LevelText(u) end
        local c = UnitColor(u)
        if not showName then
            o.name:SetText(lv)
        else
            local name, okN = Read(UnitName, u)
            if okN and type(name) == "string" then
                o.name:SetText((lv ~= "" and (lv.." ") or "")..Hex(c)..name.."|r")
            else
                o.name:SetTextColor(c[1], c[2], c[3]); pcall(o.name.SetText, o.name, name)
            end
        end
    end

    -- рамка: цель — светлая; бьёт вас (если включено) — мягкая тёплая, не красная
    local isTarget = Yes(UnitIsUnit, u, "target")
    o.isTgt = isTarget
    local aggro = false
    if s.npAggro ~= false and UnitAffectingCombat("player") then
        local st, ok = Read(UnitThreatSituation, "player", u)
        aggro = ok and type(st) == "number" and st >= 2
    end
    local pc = SOFT.good
    if o.poisoned then o.hpBox:SetBackdropBorderColor(pc[1], pc[2], pc[3], 1)
    elseif aggro then o.hpBox:SetBackdropBorderColor(0.62, 0.50, 0.34, 1)
    elseif isTarget then o.hpBox:SetBackdropBorderColor(0.38, 0.38, 0.38, 1) -- цель: чуть светлее обычной, без белого
    else ns.ResetBorder(o.hpBox) end

    -- ваш блок на цели: энергия + комбо (в бою или на враждебной цели)
    local mineOn = isTarget and (o.mineH or 0) > 0
        and (UnitAffectingCombat("player") or Yes(UnitCanAttack, "player", u))
    if mineOn then
        -- под кастом моба (если он кастует), иначе сразу под жизнью
        local anchor = o.castBox:IsShown() and o.castName or o.hpBox
        if anchor ~= o.mineAnchor then
            o.mineAnchor = anchor
            o.mine:ClearAllPoints()
            o.mine:SetPoint("TOP", anchor, "BOTTOM", 0, anchor == o.hpBox and -3 or -2)
        end
        -- энергия
        if o.enBox:IsShown() then
            local e, okE = Read(UnitPower, "player", 3)
            local m, okM = Read(UnitPowerMax, "player", 3)
            if okE and okM and m and m > 0 then o.en:SetMinMaxValues(0, m); o.en:SetValue(e)
            else pcall(o.en.SetMinMaxValues, o.en, 0, m); pcall(o.en.SetValue, o.en, e) end
            local ec = (s.barStyle == "soft") and EN_SOFT or EN_MONO
            if ns.energyZone == "wait" then ec = EN_WAIT end -- копим (удар + запас на Kick ещё нет)
            local col
            if ns.energyZone == "secret" and ns.energyNeed then -- энергия скрыта: серый/жёлтый считает игра
                local mx = ns.energyMax or 100
                col = ns.PowerCurveColor("player", 3, "npEn", string.format("%.0f|%.0f|%s", ns.energyNeed, mx, tostring(ec)),
                    { { 0, { EN_WAIT[1], EN_WAIT[2], EN_WAIT[3], 0.9 } }, { ns.energyNeed / mx, { ec[1], ec[2], ec[3], 0.9 } } })
            end
            if not ns.PaintCurve(o.en, "SetStatusBarColor", col) then o.en:SetStatusBarColor(ec[1], ec[2], ec[3], 0.9) end
        end
        -- комбо: цветом того, что нажать (синий — Sinister Strike, оранжевый — SnD, красный — Eviscerate).
        -- Набранные — ярко, пустые — слабо тем же цветом (видно даже при 0 комбо).
        -- Не хватает энергии — серые. Совета нет — обычный цвет комбо.
        if o.cp[1]:IsShown() then
            local cpKnown = ComboPoints()
            local cp = cpKnown or 0
            local key = s.helpGlow ~= false and ns.advice
            local hiddenCP = key == "cp" -- комбо скрыты: цвет удара выберет кривая по числу комбо
            if hiddenCP then key = "ss" end
            local ac = key and ADVICE[key]
            local enHidden = ns.energyZone == "secret"
            local dimNow = ns.energyZone == "wait" or (not enHidden and ns.adviceDim)
            local advCol, dimCol
            if ac and hiddenCP and not dimNow then
                -- 0 комбо — синий; от 1 — оранжевый, если пора SnD; с N для Eviscerate — красный
                local evisN = EnergyTickSettings.helpEvisCP or 5
                local st = { { 0, ADVICE.ss } }
                if ns.adviceSnD then st[#st + 1] = { 0.5 / 5, ADVICE.snd } end
                if EnergyTickSettings.helpEvis ~= false then st[#st + 1] = { (evisN - 0.5) / 5, ADVICE.evis } end
                advCol = ns.PowerCurveColor("player", 4, "npAdv", (ns.adviceSnD and "s" or "-")..evisN..tostring(EnergyTickSettings.helpEvis), st)
            end
            if ac and enHidden and ns.energyNeed then
                -- энергия скрыта: серый фильтр поверх (виден ниже порога, прозрачен выше)
                local mx = ns.energyMax or 100
                dimCol = ns.PowerCurveColor("player", 3, "npDim", string.format("%.0f|%.0f", ns.energyNeed, mx),
                    { { 0, { 0.42, 0.42, 0.42, 0.92 } }, { ns.energyNeed / mx, { 0, 0, 0, 0 } } })
            end
            local on, empty
            if ac and dimNow then
                on, empty = ADVICE_DIM[key], ADVICE_DIM[key] -- серые вместе с энергией: «жди»
            elseif ac then
                on, empty = ac, ac
            else
                local soft = s.barStyle == "soft"
                on = cp >= 5 and (soft and CP_FULL or CP_FULL_M) or (soft and CP_ON or CP_ON_M)
            end
            local raw = (not cpKnown) and ComboRaw() or nil
            for i = 1, 5 do
                local c = o.cp[i]
                if cpKnown or raw == nil then
                    if c.secret then c.fill:SetMinMaxValues(0, 1); c.fill:SetValue(1); c.secret = nil end
                    if i <= cp then c.fill:SetStatusBarColor(on[1], on[2], on[3], 1); c.fill:SetAlpha(1)
                    elseif empty then c.fill:SetStatusBarColor(empty[1], empty[2], empty[3], 1); c.fill:SetAlpha(0.22)
                    else c.fill:SetAlpha(0) end
                else
                    -- комбо скрыты: ячейка i заполнена, если комбо >= i (полоса с диапазоном i-1…i)
                    if not c.secret then c.fill:SetMinMaxValues(i - 1, i); c.secret = true end
                    pcall(c.fill.SetValue, c.fill, raw)
                    c.fill:SetStatusBarColor(on[1], on[2], on[3], 1); c.fill:SetAlpha(1)
                end
                if advCol then ns.PaintCurve(c.fill, "SetStatusBarColor", advCol) end
                if dimCol and ns.PaintCurve(c.dim, "SetVertexColor", dimCol) then c.dim:Show() else c.dim:Hide() end
            end
        end
        o.mine:Show()
    else
        o.mine:Hide()
    end

    -- не цель — бледнее (если есть цель)
    local a = 1
    if s.npFade ~= false and not isTarget and UnitExists("target") then a = 0.6 end
    o:SetAlpha(a)
end

-- ---------- события ----------
local function Attach(unit)
    if not On() then return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
    local o = plates[plate]
    if not o then
        local ok, res = pcall(Create, plate)
        if not ok then return end
        o = res; plates[plate] = o
        o:SetScript("OnUpdate", Update)
    end
    o.unit = unit
    o.friendOnly, o.raidIdx = nil, false
    Layout(o)
    o.acc = 1
    HideBlizz(plate)
    o:Show()
    RefreshCast(o)
    ScanAuras(o)
end

local function Detach(unit)
    for plate, o in pairs(plates) do
        if o.unit == unit then o.unit = nil; o:Hide(); o.castBox:Hide(); o.castName:Hide() end
    end
end

local function ByUnit(unit)
    for _, o in pairs(plates) do if o.unit == unit then return o end end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:SetScript("OnEvent", function(_, e, unit)
    if e == "DISPLAY_SIZE_CHANGED" or e == "UI_SCALE_CHANGED" then
        UpdatePH()
    elseif e == "NAME_PLATE_UNIT_ADDED" then Attach(unit)
    elseif e == "UNIT_AURA" then
        if type(unit) == "string" and not issecret(unit) and unit:find("^nameplate") then
            local o = ByUnit(unit)
            if o then ScanAuras(o) end
        end
    elseif e == "NAME_PLATE_UNIT_REMOVED" then Detach(unit)
    elseif type(unit) == "string" and not issecret(unit) and unit:find("^nameplate") then
        local o = ByUnit(unit)
        if o then RefreshCast(o) end
    end
end)

-- Применить настройки ко всем видимым полоскам (или вернуть стандартные)
function ns.ApplyNameplates()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local ok, list = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(list) ~= "table" then return end
    for _, plate in ipairs(list) do
        local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if On() then
            if u then Attach(u) end
        else
            local o = plates[plate]
            if o then o:Hide(); o.unit = nil end
            ShowBlizz(plate)
        end
    end
end

-- =============================================
-- ТЕКСТ БОЯ: цифры урона над целью и текст над вашим персонажем.
-- Это настройки самой игры (CVar). Аддон меняет только то, что вы тронули
-- на вкладке «Текст боя»; остальное остаётся как было в игре.
-- =============================================
local FCT = {
    scale   = { "WorldTextScale" },                       -- размер цифр над целью
    dmg     = { "floatingCombatTextCombatDamage" },       -- ваш урон над целью
    heal    = { "floatingCombatTextCombatHealing" },      -- лечение
    pet     = { "floatingCombatTextPetMeleeDamage", "floatingCombatTextPetSpellDamage" },
    scatter = { "floatingCombatTextCombatDamageDirectionalScale" }, -- разлёт цифр в стороны
    self    = { "enableFloatingCombatText" },             -- текст над вашим персонажем
    mode    = { "floatingCombatTextFloatMode" },          -- 1 вверх, 2 вниз, 3 дугой
}
local BOOL = { dmg = true, heal = true, pet = true, self = true, scatter = true, calmCrit = true }
-- «спокойные криты»: криты растут и летят так же, как обычные цифры (не на пол-экрана)
local CRIT_PAIRS = { { "WorldTextRampPowCrit", "WorldTextRampPow" }, { "WorldTextCritScreenY", "WorldTextScreenY" } }

-- В новых версиях игры у этих настроек на конце «_v2» (WorldTextScale_v2 и т.д.):
-- берём новое имя, если оно есть, иначе старое.
local resolved = {}
local function RawGet(n)
    local g = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not g then return nil end
    local ok, v = pcall(g, n)
    if ok then return v end
end
local function Name(n)
    if resolved[n] == nil then
        resolved[n] = (RawGet(n.."_v2") ~= nil) and (n.."_v2") or n
    end
    return resolved[n]
end

local function CVarGet(n)
    n = Name(n)
    local g = (C_CVar and C_CVar.GetCVar) or GetCVar
    if not g then return nil end
    local ok, v = pcall(g, n)
    if ok then return v end
end
local function CVarDefault(n)
    n = Name(n)
    local g = (C_CVar and C_CVar.GetCVarDefault) or GetCVarDefault
    if not g then return nil end
    local ok, v = pcall(g, n)
    if ok then return v end
end
local function CVarSet(n, v)
    v = tostring(v)
    if CVarGet(n) == v then return end
    n = Name(n)
    local s = (C_CVar and C_CVar.SetCVar) or SetCVar
    if s then pcall(s, n, v) end
end

-- текущее значение: то, что вы выбрали, иначе — как сейчас в игре
function ns.FCTGet(key)
    local d = S().fct
    if d and d[key] ~= nil then return d[key] end
    if key == "selfSize" then return 1 end
    if key == "calmCrit" then return false end
    local raw = CVarGet(FCT[key][1])
    if BOOL[key] then
        if key == "scatter" then return (tonumber(raw) or 1) > 0 end
        return raw == "1"
    end
    return tonumber(raw) or 1
end

function ns.FCTSet(key, v)
    S().fct = S().fct or {}
    S().fct[key] = v
end

-- размер текста над вашим персонажем (Blizzard_CombatText)
local baseHeight
local function ApplySelfSize(k)
    if type(COMBAT_TEXT_HEIGHT) ~= "number" then return end
    baseHeight = baseHeight or COMBAT_TEXT_HEIGHT
    COMBAT_TEXT_HEIGHT = math.floor(baseHeight * k + 0.5)
    if CombatTextFont and CombatTextFont.GetFont then
        local file, _, flags = CombatTextFont:GetFont()
        if file then CombatTextFont:SetFont(file, COMBAT_TEXT_HEIGHT, flags) end
    end
end

local fctPending
function ns.ApplyCombatText()
    local d = S().fct
    if not d then return end
    if InCombatLockdown() then fctPending = true; return end
    for key, v in pairs(d) do
        if key == "selfSize" then
            ApplySelfSize(v)
        elseif key == "calmCrit" then
            for _, pr in ipairs(CRIT_PAIRS) do
                local src = v and CVarGet(pr[2]) or CVarDefault(pr[1])
                if src then CVarSet(pr[1], src) end
            end
        elseif FCT[key] then
            local val
            if key == "scatter" then val = v and 1 or 0
            elseif BOOL[key] then val = v and 1 or 0
            else val = v end
            for _, n in ipairs(FCT[key]) do CVarSet(n, val) end
        end
    end
end

-- вернуть всё как в игре по умолчанию
function ns.ResetCombatText()
    if InCombatLockdown() then return end
    S().fct = nil
    for key, names in pairs(FCT) do
        for _, n in ipairs(names) do
            local def = CVarDefault(n)
            if def then CVarSet(n, def) end
        end
    end
    for _, pr in ipairs(CRIT_PAIRS) do
        local def = CVarDefault(pr[1])
        if def then CVarSet(pr[1], def) end
    end
    if baseHeight then ApplySelfSize(1) end
end

-- один раз: красную рамку агро выключить у всех (старые настройки её включали)
local mig = CreateFrame("Frame")
mig:RegisterEvent("PLAYER_LOGIN")
mig:SetScript("OnEvent", function()
    local s = S()
    if s and not s.npV2 then s.npV2 = true; s.npAggro = false end
end)

local fev = CreateFrame("Frame")
fev:RegisterEvent("PLAYER_LOGIN")
fev:RegisterEvent("PLAYER_REGEN_ENABLED")
fev:RegisterEvent("ADDON_LOADED")
fev:SetScript("OnEvent", function(_, e, name)
    if e == "PLAYER_REGEN_ENABLED" then
        if fctPending then fctPending = nil; ns.ApplyCombatText() end
    elseif e == "ADDON_LOADED" then
        if name == "Blizzard_CombatText" and S() and S().fct and S().fct.selfSize then
            ApplySelfSize(S().fct.selfSize)
        end
    else
        ns.ApplyCombatText()
    end
end)
