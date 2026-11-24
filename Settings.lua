-- =============================================
-- Окно настроек в стиле главной полосы.
-- Открыть: /et config, иконка у мини-карты, меню аддонов, Esc -> Настройки -> AddOns.
-- =============================================
local ADDON, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BG = "Interface\\ChatFrame\\ChatFrameBackground"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

local C_HOLD = {0.25, 0.80, 0.35}
local C_KICK = {0.30, 0.85, 1.00}
local GOLD   = {1, 0.82, 0.2}
local GREY   = {0.55, 0.55, 0.55}

local W, PAD, GAP = 380, 14, 16
local HALF = (W - 2 * PAD - GAP) / 2
local COL2 = PAD + HALF + GAP

local win
local widgets = {}

local function ET() return EnergyTickSettings end
local function UF() return UF_Settings end

-- Общая блокировка: главная полоса, SnD, HUD и фреймы юнитов
function ns.SetLocked(v)
    ET().locked = v and true or false
    UF().locked = v and true or false
    if ns.ClearUnlocks then wipe(ns.unlocked) end -- общая галочка сбрасывает разблокировки по одной
    if ns.ApplyMain then ns.ApplyMain() end
    if ns.ApplyUF then ns.ApplyUF() end
    for _, w in ipairs(widgets) do w:Refresh() end
end

local function Changed()
    if ns.ApplyMain then ns.ApplyMain() end
    if ns.ApplyUF then ns.ApplyUF() end
    if ns.ApplyMinimap then ns.ApplyMinimap() end
    if ns.ApplyPoisons then ns.ApplyPoisons() end
    if ns.ApplyFonts then ns.ApplyFonts() end
    if ns.ApplyNameplates then ns.ApplyNameplates() end
    if ns.ApplyCombatText then ns.ApplyCombatText() end
    for _, w in ipairs(widgets) do w:Refresh() end
end

-- обновить окно снаружи (загрузили профиль, сбросили настройки)
function ns.RefreshConfig()
    if win then for _, w in ipairs(widgets) do w:Refresh() end end
end

-- =============================================
-- Виджеты
-- =============================================
local function Box(fr, a)
    fr:SetBackdrop({ bgFile = BG, edgeFile = WHITE, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    fr:SetBackdropColor(0, 0, 0, a or 1); fr:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
end

local function Label(parent, size, c)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFontObject(ns.Font(size)) -- окно настроек не масштабируется вместе с панелями
    c = c or {0.9, 0.9, 0.9}
    t:SetTextColor(c[1], c[2], c[3])
    return t
end

local function Hover(b)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(C_KICK[1], C_KICK[2], C_KICK[3], 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1) end)
end

local function Header(parent, y, text)
    local t = Label(parent, 10, GOLD); t:SetPoint("TOPLEFT", PAD, y); t:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.25, 0.25, 0.25, 1); line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", PAD, y - 14)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -PAD, y - 14)
end

local function Check(parent, x, y, text, get, set)
    local b = CreateFrame("Button", nil, parent, BACKDROP)
    b:SetPoint("TOPLEFT", x, y); b:SetSize(14, 14); Box(b, 1); Hover(b)
    local fill = b:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT", 3, -3); fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(C_HOLD[1], C_HOLD[2], C_HOLD[3], 1)
    local l = Label(b, 11); l:SetPoint("LEFT", b, "RIGHT", 6, 0); l:SetText(text)
    b:SetHitRectInsets(0, -(HALF - 20), 0, 0) -- кликается и по подписи
    b:SetScript("OnClick", function() set(not get()); Changed() end)
    b.Refresh = function() fill:SetShown(get() and true or false) end
    table.insert(widgets, b)
    return b
end

local function Slider(parent, x, y, w, text, minV, maxV, step, get, set, fmt)
    local h = CreateFrame("Frame", nil, parent)
    h:SetPoint("TOPLEFT", x, y); h:SetSize(w, 30)
    local l = Label(h, 11); l:SetPoint("TOPLEFT", 0, 0); l:SetText(text)
    local v = Label(h, 11, GOLD); v:SetPoint("TOPRIGHT", 0, 0)
    local function Show(val) v:SetText(fmt and fmt(val) or tostring(val)) end

    local s = CreateFrame("Slider", nil, h, BACKDROP)
    s:SetPoint("TOPLEFT", 0, -16); s:SetPoint("TOPRIGHT", 0, -16); s:SetHeight(10)
    Box(s, 1); Hover(s)
    s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(minV, maxV); s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:SetThumbTexture(WHITE)
    local th = s:GetThumbTexture()
    th:SetSize(8, 14); th:SetVertexColor(C_KICK[1], C_KICK[2], C_KICK[3], 1)
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, d) self:SetValue(self:GetValue() + d * step) end)
    s:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val / step + 0.5) * step
        Show(val)
        if self.lock or val == self.last then return end
        self.last = val
        set(val); Changed()
    end)
    h.Refresh = function()
        local val = get()
        s.lock = true; s.last = val; s:SetValue(val); s.lock = false
        Show(val)
    end
    table.insert(widgets, h)
    return h
end

local function Button(parent, x, y, w, text, onClick, refresh)
    local b = CreateFrame("Button", nil, parent, BACKDROP)
    b:SetPoint("TOPLEFT", x, y); b:SetSize(w, 22)
    Box(b, 1); b:SetBackdropColor(0.08, 0.08, 0.08, 1); Hover(b)
    b.label = Label(b, 11); b.label:SetPoint("CENTER"); b.label:SetText(text)
    b:SetScript("OnClick", function(self) onClick(self); Changed() end)
    b.Refresh = refresh or function() end
    table.insert(widgets, b)
    return b
end

-- =============================================
-- Окно: вкладки сверху, у каждой вкладки две колонки
--   Мой блок | Цель | Полоски | Вид | Боевая панель | Общее
-- =============================================
local TABS = {
    { key = "block",  text = "Мой блок" },
    { key = "target", text = "Цель" },
    { key = "strips", text = "Полоски" },
    { key = "plates", text = "Над головой" },
    { key = "fct",    text = "Текст боя" },
    { key = "look",   text = "Вид" },
    { key = "hud",    text = "Бой" },
    { key = "helper", text = "Помощник" },
    { key = "misc",   text = "Общее" },
    { key = "profiles", text = "Профили" },
}
local TOP = -76 -- откуда начинается содержимое вкладки

local function Hint(parent, y, text, lines)
    local t = Label(parent, 9, GREY); t:SetPoint("TOPLEFT", PAD, y); t:SetWidth(W - 2 * PAD)
    t:SetJustifyH("LEFT"); t:SetText(text)
    return y - (lines or 2) * 12 - 6
end

local function Build()
    win = CreateFrame("Frame", "RogueTickConfig", UIParent, BACKDROP)
    win:SetWidth(W * 2); win:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    win:SetFrameStrata("DIALOG"); win:SetClampedToScreen(true); win:SetToplevel(true)
    Box(win, 0.94); win:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
    win:EnableMouse(true); win:SetMovable(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "RogueTickConfig") -- закрывается по Esc

    local accent = win:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 1, -1); accent:SetPoint("TOPRIGHT", -1, -1); accent:SetHeight(2)
    accent:SetColorTexture(C_HOLD[1], C_HOLD[2], C_HOLD[3], 1)

    local title = Label(win, 14, GOLD); title:SetPoint("TOPLEFT", PAD, -12); title:SetText("ROGUE TICK")
    local sub = Label(win, 10, GREY); sub:SetPoint("LEFT", title, "RIGHT", 8, -1); sub:SetText("настройки")

    local close = CreateFrame("Button", nil, win, BACKDROP)
    close:SetSize(18, 18); close:SetPoint("TOPRIGHT", -8, -8); Box(close, 1); Hover(close)
    local x = Label(close, 12); x:SetPoint("CENTER", 1, 0); x:SetText("x")
    close:SetScript("OnClick", function() win:Hide() end)

    -- ---------- вкладки ----------
    local pages, tabBtns = {}, {}
    local function ShowTab(key)
        ET().cfgTab = key
        for k, pg in pairs(pages) do pg:SetShown(k == key) end
        for _, b in ipairs(tabBtns) do
            local on = b.key == key
            local v = on and 0.95 or 0.5
            b.label:SetTextColor(on and GOLD[1] or v, on and GOLD[2] or v, on and GOLD[3] or v)
            b:SetBackdropColor(on and 0.14 or 0.05, on and 0.14 or 0.05, on and 0.14 or 0.05, 1)
        end
    end
    local tabW = (W * 2 - 2 * PAD - (#TABS - 1) * 4) / #TABS
    for i, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, win, BACKDROP)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (tabW + 4), -38); b:SetSize(tabW, 24)
        Box(b, 1); Hover(b)
        b.label = Label(b, 11); b.label:SetPoint("CENTER"); b.label:SetText(t.text)
        b.key = t.key
        b:SetScript("OnClick", function() ShowTab(t.key) end)
        tabBtns[i] = b
    end

    local function NewPage(key)
        local pg = CreateFrame("Frame", nil, win)
        pg:SetPoint("TOPLEFT", 0, 0); pg:SetPoint("BOTTOMRIGHT", 0, 0)
        -- колонки растянуты на всю высоту вкладки (без высоты игра не рисует их содержимое)
        local L = CreateFrame("Frame", nil, pg); L:SetPoint("TOPLEFT", 0, 0); L:SetPoint("BOTTOMLEFT", 0, 0); L:SetWidth(W)
        local R = CreateFrame("Frame", nil, pg); R:SetPoint("TOPLEFT", W, 0); R:SetPoint("BOTTOMLEFT", W, 0); R:SetWidth(W)
        local div = pg:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(0.18, 0.18, 0.18, 1); div:SetWidth(1)
        div:SetPoint("TOP", pg, "TOP", 0, TOP); div:SetPoint("BOTTOM", pg, "BOTTOM", 0, 14)
        pages[key] = pg
        return L, R
    end
    local heights = {}

    -- ================= МОЙ БЛОК =================
    do
        local L, R = NewPage("block")
        local y = TOP
        Header(L, y, "РАЗМЕРЫ"); y = y - 24
        Slider(L, PAD, y, HALF, "Ширина", 160, 420, 5, function() return ET().width end, function(v) ET().width = v end)
        Slider(L, COL2, y, HALF, "Жизнь", 6, 24, 1, function() return UF().dockHeight end, function(v) UF().dockHeight = v end)
        y = y - 38
        Slider(L, PAD, y, HALF, "Энергия", 10, 40, 1, function() return ET().height end, function(v) ET().height = v end)
        Slider(L, COL2, y, HALF, "Инфо / каст", 8, 24, 1, function() return UF().castHeight end, function(v) UF().castHeight = v end)
        y = y - 38
        Slider(L, PAD, y, HALF, "Комбо", 3, 16, 1, function() return ET().cpHeight end, function(v) ET().cpHeight = v end)
        Button(L, COL2, y - 6, HALF, "Рекомендуемые толщины", function()
            if InCombatLockdown() then print("|cffffff00RogueTick:|r толщины — после боя"); return end
            ns.RecommendedSizes(); Changed()
        end)
        y = y - 44
        Header(L, y, "ЭНЕРГИЯ"); y = y - 24
        Check(L, PAD, y, "Звук у капа", function() return ET().sound end, function(v) ET().sound = v end)
        Check(L, COL2, y, "Метки (удар, кап, K)", function() return ET().showMarks end, function(v) ET().showMarks = v end)
        y = y - 24
        Button(L, PAD, y, HALF, "", function()
            ET().soundID = ns.NextSound(ET().soundID); ns.PlayTick(ET().soundID, "Master")
        end, function(self) self.label:SetText("Звук у капа: "..ns.SoundName(ET().soundID)) end)
        Check(L, COL2, y - 4, "Статистика под полосками", function() return ET().showStats ~= false end, function(v) ET().showStats = v end)
        y = y - 32
        Check(L, PAD, y, "Без цифр (все полосы и над головой)", function() return ET().noNumbers end, function(v) ET().noNumbers = v end)
        y = y - 26
        Check(L, PAD, y, "Тень: энергия через ГКД", function() return ET().energyShadow ~= false end, function(v) ET().energyShadow = v end)
        Check(L, COL2, y, "Итог боя одной строкой", function() return ET().fightSummary ~= false end, function(v) ET().fightSummary = v end)
        y = y - 26
        Slider(L, PAD, y, HALF, "Цена удара", 0, 80, 1,
            function() local g = ET().genCost; return type(g) == "number" and g or 0 end,
            function(v) ET().genCost = (v == 0) and "auto" or v end,
            function(v) return v == 0 and ("авто: "..math.floor(ns.GenCost and ns.GenCost() or 45)) or v end)
        Slider(L, COL2, y, HALF, "Резерв на Kick", 0, 60, 1,
            function() local k = ET().kickCost; return type(k) == "number" and k or 0 end,
            function(v) ET().kickCost = (v == 0) and "auto" or v end,
            function(v) return v == 0 and ("авто: "..math.floor(ns.KickCost and ns.KickCost() or 25)) or v end)
        y = y - 44
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "ЧТО ПОКАЗЫВАТЬ"); y = y - 24
        Check(R, PAD, y, "Единый блок (жизнь + энергия)", function() return UF().dock ~= false end, function(v) UF().dock = v end)
        y = y - 22
        Check(R, PAD, y, "Инфо-полоса", function() return UF().infoBar ~= false end, function(v) UF().infoBar = v end)
        Check(R, COL2, y, "АГРО в инфо-полосе", function() return UF().aggroInInfo ~= false end, function(v) UF().aggroInInfo = v end)
        y = y - 22
        Check(R, PAD, y, "Комбо", function() return ET().showCP ~= false end, function(v) ET().showCP = v end)
        Check(R, COL2, y, "Свой каст", function() return UF().showCast end, function(v) UF().showCast = v end)
        y = y - 22
        Check(R, PAD, y, "Цифры жизни", function() return UF().showText end, function(v) UF().showText = v end)
        Check(R, COL2, y, "Дебаффы на мне", function() return UF().showAuras end, function(v) UF().showAuras = v end)
        y = y - 22
        Check(R, PAD, y, "Надпись АГРО", function() return UF().aggro end, function(v) UF().aggro = v end)
        Check(R, COL2, y, "Звук, когда бьют вас", function() return UF().aggroSound end, function(v) UF().aggroSound = v end)
        y = y - 22
        Button(R, COL2, y, HALF, "", function()
            UF().aggroSoundID = ns.NextSound(UF().aggroSoundID); ns.PlayTick(UF().aggroSoundID, "Master")
        end, function(self) self.label:SetText("Звук агро: "..ns.SoundName(UF().aggroSoundID)) end)
        y = y - 30
        Slider(R, PAD, y, HALF, "Иконки дебаффов", 14, 36, 1, function() return UF().playerAuraSize or 22 end, function(v) UF().playerAuraSize = v end)
        Slider(R, COL2, y, HALF, "Иконок в ряду", 1, 12, 1, function() return UF().playerAuraMax or 8 end, function(v) UF().playerAuraMax = v end)
        y = y - 44
        Header(R, y, "КАК ДВИГАТЬ"); y = y - 22
        y = Hint(R, y, "ПКМ по любой полосе блока — блок (и цель) станут голубыми, их можно тянуть. "
            .."Ещё раз ПКМ — закрепить.\n"
            .."• Жизнь — главная: тянете её — едет весь блок.\n"
            .."• Энергия, инфо/каст, комбо, полоски — только вверх-вниз, рядом со своим местом прилипают обратно. "
            .."Можно поставить энергию над жизнью — как удобно.", 7)
        heights[#heights + 1] = -y
    end

    -- ================= ЦЕЛЬ =================
    do
        local L, R = NewPage("target")
        local y = TOP
        local function Linked() return UF().targetLink ~= false end
        Header(L, y, "РАЗМЕРЫ"); y = y - 24
        Check(L, PAD, y, "Такие же, как у моего блока", function() return Linked() end, function(v) UF().targetLink = v end)
        y = y - 20
        y = Hint(L, y, "Галочка связывает только ширину. Толщины у цели свои: жизнь главная, каст крупный (Kick!), ресурс тонкий.", 2)
        Slider(L, PAD, y, HALF, "Ширина", 120, 420, 5,
            function() return Linked() and ET().width or UF().width end,
            function(v) if Linked() then ET().width = v else UF().width = v end end)
        Slider(L, COL2, y, HALF, "Жизнь", 6, 36, 1, function() return UF().tHpH or 16 end, function(v) UF().tHpH = v end)
        y = y - 38
        Slider(L, PAD, y, HALF, "Ресурс", 2, 40, 1, function() return UF().tPowH or 4 end, function(v) UF().tPowH = v end)
        Slider(L, COL2, y, HALF, "Инфо / каст", 8, 24, 1, function() return UF().tCastH or 13 end, function(v) UF().tCastH = v end)
        y = y - 38
        Button(L, PAD, y, HALF, "Рекомендуемые толщины", function()
            if InCombatLockdown() then print("|cffffff00RogueTick:|r толщины — после боя"); return end
            ns.RecommendedSizes(); Changed()
        end)
        y = y - 32
        Header(L, y, "ЦЕЛЬ ЦЕЛИ"); y = y - 24
        Check(L, PAD, y, "Показывать", function() return UF().showToT end, function(v) UF().showToT = v end)
        y = y - 26
        Slider(L, PAD, y, HALF, "Ширина", 60, 200, 5, function() return UF().totWidth or 110 end, function(v) UF().totWidth = v end)
        y = y - 44
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "ЧТО ПОКАЗЫВАТЬ"); y = y - 24
        Check(R, PAD, y, "Фрейм цели", function() return UF().showTarget end, function(v) UF().showTarget = v end)
        Check(R, COL2, y, "Раздельные полосы", function() return UF().targetSplit ~= false end, function(v) UF().targetSplit = v end)
        y = y - 22
        Check(R, PAD, y, "Полоса ресурса", function() return UF().showPower end, function(v) UF().showPower = v end)
        Check(R, COL2, y, "Каст цели", function() return UF().showTargetCast ~= false end, function(v) UF().showTargetCast = v end)
        y = y - 22
        Check(R, PAD, y, "Тень вне досягаемости", function() return UF().rangeFade end, function(v) UF().rangeFade = v end)
        Check(R, COL2, y, "Мои дебаффы на цели", function() return UF().showTargetAuras end, function(v) UF().showTargetAuras = v end)
        y = y - 22
        Check(R, PAD, y, "Цифры жизни", function() return UF().showTargetText ~= false end, function(v) UF().showTargetText = v end)
        y = y - 28
        Slider(R, PAD, y, HALF, "Иконки дебаффов", 14, 36, 1, function() return UF().auraSize end, function(v) UF().auraSize = v end)
        Slider(R, COL2, y, HALF, "Иконок в ряду", 1, 12, 1, function() return UF().auraMax end, function(v) UF().auraMax = v end)
        y = y - 44
        Header(R, y, "КАК ДВИГАТЬ"); y = y - 22
        y = Hint(R, y, "ПКМ по моему блоку или Shift+ПКМ по цели — цель станет голубой.\n"
            .."• Жизнь цели — главная: тянете её — едет вся цель (и цель цели).\n"
            .."• Инфо-строку и ресурс — только вверх-вниз: можно поставить ресурс сверху, а инфо снизу.", 5)
        heights[#heights + 1] = -y
    end

    -- ================= ПОЛОСКИ =================
    do
        local L, R = NewPage("strips")
        local y = TOP
        Header(L, y, "ОТКАТЫ И БАФФЫ"); y = y - 24
        Check(L, PAD, y, "Иконки у полосок", function() return ET().barIcons ~= false end, function(v) ET().barIcons = v end)
        y = y - 20
        local legend = Label(L, 9, GREY); legend:SetPoint("TOPLEFT", PAD, y); legend:SetWidth(W - 2 * PAD); legend:SetJustifyH("LEFT")
        legend:SetText("[-] скрыть, не удаляя ([+] вернуть).  У баффов/дебаффов: [!] спал в бою — оранжевая, [~] последние 3 с — своим цветом, мягко пульсирует")
        y = y - 16

        local MAXS = ns.MAX_STRIPS or 5
        local ROW = 20
        local list = CreateFrame("Frame", nil, L)
        list:SetPoint("TOPLEFT", PAD, y); list:SetSize(W - 2 * PAD, ROW * MAXS)
        list.rows = {}
        for i = 1, MAXS do
            local row = CreateFrame("Frame", nil, list)
            row:SetSize(W - 2 * PAD, ROW - 2); row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
            -- порядок: выше / ниже
            local function Arrow(tex, dir, xo)
                local b = CreateFrame("Button", nil, row)
                b:SetSize(16, 16); b:SetPoint("LEFT", xo, 0)
                b:SetNormalTexture(tex.."-Up"); b:SetPushedTexture(tex.."-Down"); b:SetHighlightTexture(tex.."-Up", "ADD")
                b:SetScript("OnClick", function() if ns.MoveStrip then ns.MoveStrip(i, dir) end; Changed() end)
                return b
            end
            row.up = Arrow("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp", -1, 0)
            row.down = Arrow("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown", 1, 16)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(14, 14); row.icon:SetPoint("LEFT", 36, 0); row.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
            local del = CreateFrame("Button", nil, row, BACKDROP)
            del:SetSize(18, 18); del:SetPoint("RIGHT", 0, 0); Box(del, 1); Hover(del)
            local dx = Label(del, 11); dx:SetPoint("CENTER", 1, 0); dx:SetText("x")
            del:SetScript("OnClick", function() if ns.RemoveStrip then ns.RemoveStrip(i) end; Changed() end)
            local function Chip(key, txt, tip)
                local b = CreateFrame("Button", nil, row, BACKDROP)
                b:SetSize(18, 18); Box(b, 1); Hover(b)
                b.t = Label(b, 11); b.t:SetPoint("CENTER", 0, 0); b.t:SetText(txt)
                b:SetScript("OnClick", function() if ns.ToggleStripOpt then ns.ToggleStripOpt(i, key) end; Changed() end)
                b:HookScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, 1, 1, 1, 1, true); GameTooltip:Show()
                end)
                b:HookScript("OnLeave", function() GameTooltip:Hide() end)
                b.key = key
                return b
            end
            row.pulse = Chip("pulse", "~", "Последние 3 секунды — мягко пульсирует своим цветом")
            row.pulse:SetPoint("RIGHT", del, "LEFT", -4, 0)
            row.alert = Chip("alert", "!", "Спал в бою — полоска ровно горит оранжевым")
            row.alert:SetPoint("RIGHT", row.pulse, "LEFT", -3, 0)
            -- тип: нажать — сменить (откат -> бафф -> дебафф)
            -- скрыть, не удаляя (все настройки полоски остаются)
            row.hide = Chip("hidden", "-", "Скрыть полоску, не удаляя. Нажмите ещё раз — вернётся с теми же настройками")
            row.hide:SetPoint("RIGHT", row.alert, "LEFT", -3, 0)
            local kb = CreateFrame("Button", nil, row)
            kb:SetSize(96, 18); kb:SetPoint("RIGHT", row.hide, "LEFT", -6, 0)
            row.kind = Label(kb, 10, GREY); row.kind:SetPoint("RIGHT", kb, "RIGHT", 0, 0); row.kind:SetJustifyH("RIGHT")
            kb:SetScript("OnClick", function() if ns.CycleStripKind then ns.CycleStripKind(i) end; Changed() end)
            kb:SetScript("OnEnter", function(self)
                row.kind:SetTextColor(C_KICK[1], C_KICK[2], C_KICK[3])
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Нажмите, чтобы сменить тип", 1, 1, 1); GameTooltip:Show()
            end)
            kb:SetScript("OnLeave", function() row.kind:SetTextColor(GREY[1], GREY[2], GREY[3]); GameTooltip:Hide() end)
            row.kindBtn = kb
            row.text = Label(row, 11); row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
            row.text:SetPoint("RIGHT", kb, "LEFT", -6, 0); row.text:SetJustifyH("LEFT"); row.text:SetWordWrap(false)
            list.rows[i] = row
        end
        list.empty = Label(list, 10, GREY); list.empty:SetPoint("TOPLEFT", 0, -3)
        list.empty:SetText("Полосок пока нет. Добавьте откат или бафф ниже.")
        list.Refresh = function()
            local bars = ET().bars or {}
            for i, row in ipairs(list.rows) do
                local d = bars[i]
                if d then
                    row.icon:SetTexture(d.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                    if d.hidden then
                        row.text:SetText((d.name or tostring(d.spell)).."  (скрыта)"); row.text:SetTextColor(0.45, 0.45, 0.45)
                        row.icon:SetDesaturated(true); row.icon:SetAlpha(0.5)
                        row.hide.t:SetText("+"); row.hide.t:SetTextColor(0.95, 0.75, 0.35)
                    else
                        row.text:SetText(d.name or tostring(d.spell)); row.text:SetTextColor(0.9, 0.9, 0.9)
                        row.icon:SetDesaturated(false); row.icon:SetAlpha(1)
                        row.hide.t:SetText("-"); row.hide.t:SetTextColor(0.6, 0.6, 0.6)
                    end
                    row.kind:SetText((ns.STRIP_KINDS and ns.STRIP_KINDS[d.kind]) or "")
                    row.up:SetShown(i > 1); row.down:SetShown(bars[i + 1] ~= nil)
                    local aura = d.kind ~= "cd"
                    for _, b in ipairs({ row.alert, row.pulse }) do
                        b:SetShown(aura)
                        local on = d[b.key] and true or false
                        local v = on and 0.95 or 0.35
                        b.t:SetTextColor(on and 0.95 or v, on and 0.75 or v, on and 0.35 or v)
                    end
                    row:Show()
                else
                    row:Hide()
                end
            end
            list.empty:SetShown(#bars == 0)
        end
        table.insert(widgets, list)
        y = y - ROW * MAXS - 4

        -- Добавление: [способность или ID] [тип] [+]
        local addKind = "cd"
        local ORDER = { "cd", "buff", "debuff" }
        local edit = CreateFrame("EditBox", nil, L, BACKDROP)
        edit:SetPoint("TOPLEFT", PAD, y); edit:SetSize(HALF, 22); Box(edit, 1)
        edit:SetAutoFocus(false); edit:SetFontObject(ns.Font(11, "")); edit:SetTextInsets(6, 6, 0, 0)
        edit:SetTextColor(0.9, 0.9, 0.9); edit:SetMaxLetters(60)
        local ph = Label(edit, 10, GREY); ph:SetPoint("LEFT", 6, 0); ph:SetText("способность или ID")
        local function UpdPH() ph:SetShown(edit:GetText() == "" and not edit:HasFocus()) end
        edit:SetScript("OnTextChanged", UpdPH)
        edit:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(C_KICK[1], C_KICK[2], C_KICK[3], 1); UpdPH() end)
        edit:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0.2, 0.2, 0.2, 1); UpdPH() end)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

        local status = Label(L, 9, GREY); status:SetPoint("TOPLEFT", PAD, y - 26)
        status:SetWidth(W - 2 * PAD); status:SetJustifyH("LEFT")

        local function Add()
            if not ns.AddStrip then return end
            local ok, msg = ns.AddStrip(edit:GetText(), addKind)
            if ok then
                status:SetTextColor(0.75, 0.75, 0.75); status:SetText("Добавлено: "..msg)
                edit:SetText(""); edit:ClearFocus()
            else
                status:SetTextColor(0.8, 0.55, 0.5); status:SetText(msg)
            end
            Changed()
        end
        edit:SetScript("OnEnterPressed", Add)

        Button(L, COL2, y, HALF - 52, "", function()
            for i, k in ipairs(ORDER) do
                if k == addKind then addKind = ORDER[i % #ORDER + 1]; break end
            end
        end, function(self) self.label:SetText((ns.STRIP_KINDS and ns.STRIP_KINDS[addKind]) or addKind) end)
        Button(L, COL2 + HALF - 48, y, 48, "+", Add)
        y = y - 26 - 26
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "ТОЛЩИНА"); y = y - 24
        Slider(R, PAD, y, HALF, "Откаты", 3, 16, 1, function() return ET().cdHeight or ET().stripHeight or 6 end, function(v) ET().cdHeight = v end)
        Slider(R, COL2, y, HALF, "Баффы / дебаффы", 3, 16, 1, function() return ET().auraHeight or ET().stripHeight or 6 end, function(v) ET().auraHeight = v end)
        y = y - 44
        Header(R, y, "КАК ЭТО РАБОТАЕТ"); y = y - 22
        y = Hint(R, y, "Полоска показывает, сколько осталось: пустая — баффа нет или откат готов.\n"
            .."• Откат — кулдаун способности (ГКД не считается).\n"
            .."• Бафф на мне — например, Slice and Dice, Adrenaline Rush.\n"
            .."• Дебафф на цели — ваш, например Rupture или Garrote.\n"
            .."У разбойника Slice and Dice добавлена сама; у других классов — своё.\n"
            .."Название пишется как в книге заклинаний, или ID способности.", 8)
        heights[#heights + 1] = -y
    end

    -- ================= НАД ГОЛОВОЙ =================
    do
        local L, R = NewPage("plates")
        local y = TOP
        Header(L, y, "ПОЛОСКИ НАД ГОЛОВОЙ"); y = y - 24
        Check(L, PAD, y, "Свои вместо стандартных", function() return ET().npOn ~= false end, function(v) ET().npOn = v end)
        y = y - 26
        -- вид: полоса / кубик
        local function ModeButton(x, key, text)
            Button(L, x, y, HALF, text, function() ET().npMode = key end, function(self)
                local on = (ET().npMode or "bar") == key
                local v = on and 0.95 or 0.45
                self.label:SetTextColor(v, v, v)
                self:SetBackdropColor(on and 0.16 or 0.06, on and 0.16 or 0.06, on and 0.16 or 0.06, 1)
            end)
        end
        ModeButton(PAD, "bar", "Полоса")
        ModeButton(COL2, "cube", "Кубик с %")
        y = y - 34
        Header(L, y, "ПОЛОСА"); y = y - 24
        Slider(L, PAD, y, HALF, "Ширина", 50, 200, 5, function() return ET().npWidth or 110 end, function(v) ET().npWidth = v end)
        Slider(L, COL2, y, HALF, "Толщина жизни", 3, 20, 1, function() return ET().npHP or 8 end, function(v) ET().npHP = v end)
        y = y - 40
        Check(L, PAD, y, "Имя", function() return ET().npName ~= false end, function(v) ET().npName = v end)
        Check(L, COL2, y, "Проценты", function() return ET().npPct ~= false end, function(v) ET().npPct = v end)
        y = y - 26
        Button(L, PAD, y, HALF, "", function()
            ET().npColor = (ET().npColor == "health") and "reaction" or "health"
        end, function(self)
            self.label:SetText((ET().npColor == "health") and "Цвет: по % жизни" or "Цвет: кто это (класс)")
        end)
        Check(L, COL2, y - 2, "Своим только имя", function() return ET().npFriendName ~= false end, function(v) ET().npFriendName = v end)
        y = y - 30
        Check(L, PAD, y, "Метки рейда", function() return ET().npRaid ~= false end, function(v) ET().npRaid = v end)
        y = y - 30
        Header(L, y, "КУБИК"); y = y - 24
        Slider(L, PAD, y, HALF, "Ширина", 20, 80, 1, function() return ET().npCubeW or 34 end, function(v) ET().npCubeW = v end)
        Slider(L, COL2, y, HALF, "Высота", 10, 40, 1, function() return ET().npCubeH or 16 end, function(v) ET().npCubeH = v end)
        y = y - 40
        Check(L, PAD, y, "Имя над кубиком", function() return ET().npCubeName end, function(v) ET().npCubeName = v end)
        y = y - 28
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "ЕЩЁ"); y = y - 24
        Check(R, PAD, y, "Уровень (цвет — сложность)", function() return ET().npLevel ~= false end, function(v) ET().npLevel = v end)
        y = y - 22
        Check(R, PAD, y, "Ваш яд — зелёная рамка", function() return ET().npPoison ~= false end, function(v) ET().npPoison = v end)
        y = y - 22
        Check(R, PAD, y, "Иконка сапа", function() return ET().npSap ~= false end, function(v) ET().npSap = v end)
        y = y - 26
        Header(R, y, "ВАШ БЛОК НА ЦЕЛИ (под её жизнью и кастом)"); y = y - 24
        Check(R, PAD, y, "Ваша энергия", function() return ET().npEnergy ~= false end, function(v) ET().npEnergy = v end)
        Check(R, COL2, y, "Ваши комбо", function() return ET().npCP ~= false end, function(v) ET().npCP = v end)
        y = y - 28
        Slider(R, PAD, y, HALF, "Толщина энергии", 2, 12, 1, function() return ET().npEnH or 5 end, function(v) ET().npEnH = v end)
        Slider(R, COL2, y, HALF, "Толщина комбо", 3, 12, 1, function() return ET().npCPSize or 6 end, function(v) ET().npCPSize = v end)
        y = y - 40
        Check(R, PAD, y, "Комбо цветом удара (Помощник)", function() return ET().helpGlow ~= false end, function(v) ET().helpGlow = v end)
        y = y - 26
        Check(R, PAD, y, "Каст (для Kick)", function() return ET().npCast ~= false end, function(v) ET().npCast = v end)
        Check(R, COL2, y, "Зона «поздно для Kick»", function() return ET().castKickZone ~= false end, function(v) ET().castKickZone = v end)
        y = y - 26
        Slider(R, PAD, y, HALF, "Толщина каста", 2, 14, 1, function() return ET().npCastH or 5 end, function(v) ET().npCastH = v end)
        y = y - 40
        Check(R, PAD, y, "Рамка, если бьёт вас", function() return ET().npAggro == true end, function(v) ET().npAggro = v end)
        y = y - 22
        Check(R, PAD, y, "Не цель — бледнее", function() return ET().npFade ~= false end, function(v) ET().npFade = v end)
        y = y - 30
        Header(R, y, "КАК ЭТО РАБОТАЕТ"); y = y - 22
        y = Hint(R, y, "• Полоса — имя, тонкая жизнь и % справа, под ней каст.\n"
            .."• Кубик — только % жизни: зелёный, ярче зелёный (меньше 60%), красный (меньше 35%). Почти не мешает.\n"
            .."• Ваша цель — светлая рамка, остальные чуть бледнее. Зелёная рамка — на нём ваш яд. Слева — иконка сапа с таймером. Под жизнью и кастом цели — ваш блок: энергия и 5 ячеек комбо, ячейки комбо окрашены цветом удара, который нужно нажать (серые — не хватает энергии). Уровень — цветом сложности (серый, зелёный, жёлтый, оранжевый, красный), «+» — элита.\n"
            .."• Цвета берутся из стиля на вкладке «Вид».\n"
            .."• Если в бою игра скрывает жизнь, % показывается без цвета.", 15)
        heights[#heights + 1] = -y
    end

    -- ================= ТЕКСТ БОЯ =================
    do
        local L, R = NewPage("fct")
        local G, Sv = ns.FCTGet, ns.FCTSet
        local function Pct(v) return math.floor(v * 100 + 0.5).."%" end
        local y = TOP
        Header(L, y, "ЦИФРЫ НАД ЦЕЛЬЮ"); y = y - 24
        Slider(L, PAD, y, HALF, "Размер цифр", 0.2, 2.5, 0.1, function() return G("scale") end,
            function(v) Sv("scale", v) end, Pct)
        y = y - 44
        Check(L, PAD, y, "Ваш урон", function() return G("dmg") end, function(v) Sv("dmg", v) end)
        Check(L, COL2, y, "Лечение", function() return G("heal") end, function(v) Sv("heal", v) end)
        y = y - 22
        Check(L, PAD, y, "Урон питомца", function() return G("pet") end, function(v) Sv("pet", v) end)
        Check(L, COL2, y, "Разлёт в стороны", function() return G("scatter") end, function(v) Sv("scatter", v) end)
        y = y - 22
        Check(L, PAD, y, "Криты не раздувать (как обычные цифры)", function() return G("calmCrit") end, function(v) Sv("calmCrit", v) end)
        y = y - 32
        Header(L, y, "НАД ВАШИМ ПЕРСОНАЖЕМ"); y = y - 24
        Check(L, PAD, y, "Показывать (урон по вам, лечение)", function() return G("self") end, function(v) Sv("self", v) end)
        y = y - 28
        Slider(L, PAD, y, HALF, "Размер текста", 0.5, 2, 0.1, function() return G("selfSize") end,
            function(v) Sv("selfSize", v) end, Pct)
        local MODES = { [1] = "Движение: вверх", [2] = "Движение: вниз", [3] = "Движение: дугой" }
        Button(L, COL2, y + 4, HALF, "", function()
            local m = math.floor(G("mode") or 1)
            Sv("mode", (m % 3) + 1)
        end, function(self) self.label:SetText(MODES[math.floor(G("mode") or 1)] or MODES[1]) end)
        y = y - 44
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "СБРОС"); y = y - 26
        Button(R, PAD, y, HALF, "Как в игре по умолчанию", function() ns.ResetCombatText() end)
        y = y - 34
        Header(R, y, "КАК ЭТО РАБОТАЕТ"); y = y - 22
        y = Hint(R, y, "• Это настройки самой игры: аддон меняет только то, что вы тронули здесь.\n"
            .."• «Размер цифр» — урон, который вы наносите, над головой цели. Совсем убрать — снимите «Ваш урон».\n"
            .."• «Криты не раздувать» — криты не вылетают огромными на пол-экрана.\n"
            .."• «Разлёт в стороны» выключен — цифры идут ровно вверх, меньше мельтешат.\n"
            .."• Текст над персонажем — урон по вам, лечение, «Уклонение» и т.п.\n"
            .."• Сохраняется в профиле. В бою изменения применятся после боя.", 13)
        heights[#heights + 1] = -y
    end

    -- ================= ВИД =================
    do
        local L, R = NewPage("look")
        local y = TOP
        Header(L, y, "ЦВЕТА"); y = y - 24
        local function StyleButton(x, key, text)
            Button(L, x, y, HALF, text, function() ET().barStyle = key end, function(self)
                local on = (ET().barStyle or "mono") == key
                local v = on and 0.95 or 0.45
                self.label:SetTextColor(v, v, v)
                self:SetBackdropColor(on and 0.16 or 0.06, on and 0.16 or 0.06, on and 0.16 or 0.06, 1)
            end)
        end
        StyleButton(PAD, "mono", "Монохром")
        StyleButton(COL2, "soft", "Мягкий цвет")
        y = y - 34
        Slider(L, PAD, y, HALF, "Вне боя (все панели)", 10, 100, 5,
            function() return math.floor((ET().oocAlpha or 0.35) * 100 + 0.5) end,
            function(v) ET().oocAlpha = v / 100 end,
            function(v) return v.."%" end)
        Slider(L, COL2, y, HALF, "Размер шрифта", 70, 150, 5,
            function() return math.floor((ET().fontScale or 1) * 100 + 0.5) end,
            function(v) ET().fontScale = v / 100 end,
            function(v) return v.."%" end)
        y = y - 44
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "ФОН И РАМКИ"); y = y - 24
        Slider(R, PAD, y, HALF, "Фон: чёрный → серый", 0, 50, 1,
            function() return math.floor((ET().bgGray or 0) * 100 + 0.5) end,
            function(v) ET().bgGray = v / 100 end,
            function(v) return v == 0 and "чёрный" or (v.."%") end)
        Slider(R, COL2, y, HALF, "Плотность фона", 0, 100, 5,
            function() return math.floor((ET().bgAlpha or 0.9) * 100 + 0.5) end,
            function(v) ET().bgAlpha = v / 100 end,
            function(v) return v == 0 and "прозрачный" or (v.."%") end)
        y = y - 40
        local styles = ns.BORDER_STYLES or { "flat" }
        Button(R, PAD, y, HALF, "Рамка", function()
            local cur, idx = ET().borderStyle or "flat", 1
            for i, k in ipairs(styles) do if k == cur then idx = i end end
            ET().borderStyle = styles[idx % #styles + 1]
        end, function(self)
            local k = ET().borderStyle or "flat"
            self.label:SetText("Рамка: "..((ns.BORDER_NAMES and ns.BORDER_NAMES[k]) or k))
        end)
        Slider(R, COL2, y - 2, HALF, "Толщина рамки", 1, 4, 1, function() return ET().borderSize or 1 end,
            function(v) ET().borderSize = v end)
        y = y - 40
        Slider(R, PAD, y, HALF, "Скругление углов", 0, 8, 1, function() return ns.Radius and ns.Radius() or 3 end,
            function(v) ET().radius = v end, function(v) return v == 0 and "нет" or v end)
        y = y - 44
        heights[#heights + 1] = -y
    end

    -- ================= БОЕВАЯ ПАНЕЛЬ =================
    do
        local L, R = NewPage("hud")
        local y = TOP
        Header(L, y, "БОЕВАЯ ПАНЕЛЬ"); y = y - 24
        Check(L, PAD, y, "Показывать", function() return ET().showHUD ~= false end, function(v) ET().showHUD = v end)
        y = y - 22
        y = Hint(L, y, "Ячейки слева направо — по важности. Тусклое — всё спокойно, ярко — пора действовать. "
            .."Наведите на пункт — подсказка.", 3)
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "ЯЧЕЙКИ"); y = y - 24
        local CELL_NAMES = {
            hp = "Жизнь, %", threat = "Агро, %", snd = "Slice and Dice", cp = "Комбо",
            energy = "Энергия", next = "До удара", kick = "Kick", evasion = "Ускользание",
            vanish = "Исчезновение", feint = "Финт", target = "Здоровье цели",
        }
        for i, def in ipairs(ns.HUD_CELLS or {}) do
            local key = def.key
            local cx = (i % 2 == 1) and PAD or COL2
            local b = Check(R, cx, y, i..". "..(CELL_NAMES[key] or def.head),
                function()
                    local t = ET().hudCells
                    if t and t[key] ~= nil then return t[key] end
                    return def.on
                end,
                function(v) ET().hudCells = ET().hudCells or {}; ET().hudCells[key] = v end)
            b:HookScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(CELL_NAMES[key] or def.head, 1, 1, 1)
                GameTooltip:AddLine(def.tip, 0.8, 0.8, 0.8, true)
                GameTooltip:Show()
            end)
            b:HookScript("OnLeave", function() GameTooltip:Hide() end)
            if i % 2 == 0 then y = y - 22 end
        end
        if #(ns.HUD_CELLS or {}) % 2 == 1 then y = y - 22 end
        y = y - 10
        heights[#heights + 1] = -y
    end

    -- ================= ПОМОЩНИК =================
    do
        local L, R = NewPage("helper")
        local y = TOP
        Header(L, y, "ПОМОЩНИК: ИКОНКИ У БЛОКА"); y = y - 24
        Check(L, PAD, y, "Иконка «Удар»", function() return ET().helpAttack ~= false end, function(v) ET().helpAttack = v end)
        Check(L, COL2, y, "Иконка «Защита»", function() return ET().helpSave ~= false end, function(v) ET().helpSave = v end)
        y = y - 22
        Check(L, PAD, y, "Подписи под иконками", function() return ET().helpCaptions ~= false end, function(v) ET().helpCaptions = v end)
        Check(L, COL2, y, "Ожидание энергии", function() return ET().helpEnergy ~= false end, function(v) ET().helpEnergy = v end)
        y = y - 22
        Check(L, PAD, y, "Подсветка над головой цели", function() return ET().helpGlow ~= false end, function(v) ET().helpGlow = v end)
        Check(L, COL2, y, "Запас на Kick / обезоружить", function() return ET().helpReserve ~= false end, function(v) ET().helpReserve = v end)
        y = y - 28
        Slider(L, PAD, y, HALF, "Размер иконок", 20, 64, 1, function() return ET().helpSize or 36 end, function(v) ET().helpSize = v end)
        y = y - 44

        Header(L, y, "УДАР"); y = y - 24
        Check(L, PAD, y, "Slice and Dice", function() return ET().helpSnD ~= false end, function(v) ET().helpSnD = v end)
        Check(L, COL2, y, "Eviscerate", function() return ET().helpEvis ~= false end, function(v) ET().helpEvis = v end)
        y = y - 22
        Check(L, PAD, y, "Из невидимости: чем начать", function() return ET().helpOpener ~= false end, function(v) ET().helpOpener = v end)
        y = y - 28
        Slider(L, PAD, y, HALF, "SnD, если осталось <", 0, 6, 0.1, function() return ET().helpSnDRefresh or 1.2 end,
            function(v) ET().helpSnDRefresh = math.floor(v * 10 + 0.5) / 10 end,
            function(v) return v < 0.05 and "только спал" or string.format("%.1f с", v) end)
        Slider(L, COL2, y, HALF, "Eviscerate с комбо", 1, 5, 1, function() return ET().helpEvisCP or 5 end,
            function(v) ET().helpEvisCP = v end)
        y = y - 38
        -- тот же параметр, что «Цена удара» на первой вкладке: порог серого для энергии и комбо
        Slider(L, PAD, y, HALF, "Порог: цена удара", 0, 80, 1,
            function() local g = ET().genCost; return type(g) == "number" and g or 0 end,
            function(v) ET().genCost = (v == 0) and "auto" or v end,
            function(v) return v == 0 and ("авто: "..math.floor(ns.GenCost and ns.GenCost() or 45)) or v end)
        y = y - 38
        y = Hint(L, y, "Ниже порога энергия серая, комбо над целью — цветом удара под серым фильтром (жди). Выше — жёлтая энергия и яркие комбо. Sinister Strike с талантом — 30, без — 40–45.", 3)
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "ЗАЩИТА"); y = y - 24
        Check(R, PAD, y, "Kick, когда цель кастует", function() return ET().helpKick ~= false end, function(v) ET().helpKick = v end)
        Check(R, COL2, y, "Обезоружить бойца", function() return ET().helpDisarm ~= false end, function(v) ET().helpDisarm = v end)
        y = y - 22
        Check(R, PAD, y, "Ускользание", function() return ET().helpEvasion ~= false end, function(v) ET().helpEvasion = v end)
        Check(R, COL2, y, "Исчезновение", function() return ET().helpVanish ~= false end, function(v) ET().helpVanish = v end)
        y = y - 22
        Check(R, PAD, y, "Зелья и камни", function() return ET().helpPotion ~= false end, function(v) ET().helpPotion = v end)
        Check(R, COL2, y, "Финт", function() return ET().helpFeint ~= false end, function(v) ET().helpFeint = v end)
        y = y - 28
        Slider(R, PAD, y, HALF, "Спасаться, если жизни <", 10, 70, 5, function() return ET().helpHP or 35 end,
            function(v) ET().helpHP = v end, function(v) return v.."%" end)
        Slider(R, COL2, y, HALF, "Финт при угрозе от", 50, 100, 5, function() return ET().helpThreat or 90 end,
            function(v) ET().helpThreat = v end, function(v) return v.."%" end)
        y = y - 44
        Header(R, y, "КАК ЭТО РАБОТАЕТ"); y = y - 22
        y = Hint(R, y, "Удар: нет комбо — Sinister Strike; есть комбо и SnD спадает — Slice and Dice; "
            .."набрали нужное число комбо — Eviscerate; иначе — Sinister Strike.\n"
            .."Ячейки комбо (в блоке и над головой цели): синие — Sinister Strike, оранжевые — Slice and Dice, красные — Eviscerate; серые — копите энергию. Бирюзовый — каст, который можно сбить (Kick). Жёлтый — только энергия.\n"
            .."Не хватает энергии — иконка темнеет и заполняется по мере набора, в центре — секунды до удара.\n"
            .."Защита (по порядку): цель кастует — Kick; мало жизни — Ускользание, потом Исчезновение, потом зелье; "
            .."высокая угроза — Финт. Нечего советовать — ячейка пустая.\n"
            .."Двигать: ПКМ по блоку, потом тянуть иконки.", 13)
        heights[#heights + 1] = -y
    end

    -- ================= ОБЩЕЕ =================
    do
        local L, R = NewPage("misc")
        local y = TOP
        Header(L, y, "ОБЩЕЕ"); y = y - 24
        Check(L, PAD, y, "Иконка у мини-карты", function() return not ET().minimapHide end, function(v) ET().minimapHide = not v end)
        Check(L, COL2, y, "Закрепить всё", function() return ET().locked end, function(v) ns.SetLocked(v) end)
        y = y - 28
        Button(L, PAD, y, HALF, "Тест-режим", function() ns.SetTest(not ns.testMode) end,
            function(self)
                self.label:SetText(ns.testMode and "Тест-режим: ВКЛ" or "Тест-режим")
                local c = ns.testMode and C_HOLD or {0.9, 0.9, 0.9}
                self.label:SetTextColor(c[1], c[2], c[3])
            end)
        Button(L, COL2, y, HALF, "Сбросить позиции", function()
            if ns.ResetMainPositions then ns.ResetMainPositions() end
            if ns.ResetUFPositions then ns.ResetUFPositions() end
        end)
        y = y - 30
        local armed
        local resetBtn
        resetBtn = Button(L, PAD, y, HALF, "", function()
            if armed and GetTime() - armed < 4 then
                armed = nil
                local ok, msg = ns.ResetAll()
                if not ok and msg then print("|cffffff00RogueTick:|r "..msg) end
            else
                armed = GetTime()
                if C_Timer and C_Timer.After then C_Timer.After(4, function() if resetBtn then resetBtn:Refresh() end end) end
            end
        end, function(self)
            local on = armed and GetTime() - armed < 4
            self.label:SetText(on and "Точно? Нажмите ещё раз" or "Сбросить все настройки")
            if on then self.label:SetTextColor(0.9, 0.45, 0.4) else self.label:SetTextColor(0.9, 0.9, 0.9) end
        end)
        y = y - 34
        y = Hint(L, y, "Снять «Закрепить всё» — двигать можно все панели сразу. "
            .."Одну панель — ПКМ по ней (у цели — Shift+ПКМ).", 2)

        Header(L, y, "ЯДЫ"); y = y - 24
        Check(L, PAD, y, "Панель ядов", function() return ET().poisonBar ~= false end, function(v) ET().poisonBar = v end)
        y = y - 26
        Slider(L, PAD, y, HALF, "Размер", 20, 48, 1, function() return ET().poisonSize or 30 end, function(v) ET().poisonSize = v end)
        y = y - 40
        for i, hand in ipairs({ "MH", "OH" }) do
            local name = hand == "MH" and "Правая" or "Левая"
            Button(L, i == 1 and PAD or COL2, y, HALF, "", function(self)
                ns.CapturePoisonKey(hand, function() self:Refresh() end)
                self:Refresh()
            end, function(self)
                if ns.poisonCapture == hand then
                    self.label:SetText(name..": нажмите клавишу…"); self.label:SetTextColor(C_HOLD[1], C_HOLD[2], C_HOLD[3])
                else
                    self.label:SetText(name..": "..(ns.PoisonKeyText and ns.PoisonKeyText(hand) or "нет")); self.label:SetTextColor(0.9, 0.9, 0.9)
                end
            end)
        end
        y = y - 30
        y = Hint(L, y, "ЛКМ по кнопке — нанести яд, ПКМ — выбрать яд из сумки, Ctrl + перетащить — двигать. "
            .."Клавиша: нажмите кнопку выше, затем клавишу; Backspace — снять, Esc — отмена.", 3)
        heights[#heights + 1] = -y

        y = TOP
        Header(R, y, "СКРЫТЬ СТАНДАРТНЫЕ BLIZZARD"); y = y - 24
        Check(R, PAD, y, "Фрейм игрока", function() return UF().hideBlizzPlayer end, function(v) UF().hideBlizzPlayer = v end)
        Check(R, COL2, y, "Фрейм цели", function() return UF().hideBlizzTarget end, function(v) UF().hideBlizzTarget = v end)
        y = y - 22
        Check(R, PAD, y, "Каст-бар игрока", function() return UF().hideBlizzCast end, function(v) UF().hideBlizzCast = v end)
        y = y - 30
        Header(R, y, "ОТДЕЛЬНЫЙ ФРЕЙМ ИГРОКА"); y = y - 22
        y = Hint(R, y, "Если «Единый блок» выключен, фрейм игрока — отдельный:", 1)
        Check(R, PAD, y, "Показывать", function() return UF().showPlayer end, function(v) UF().showPlayer = v end)
        Check(R, COL2, y, "Тряска при низком HP", function() return UF().shake end, function(v) UF().shake = v end)
        y = y - 30
        heights[#heights + 1] = -y
    end

    -- ================= ПРОФИЛИ =================
    do
        local L, R = NewPage("profiles")
        local y = TOP
        Header(L, y, "ПРОФИЛИ НА АККАУНТЕ"); y = y - 22
        local charLbl = Label(L, 10, GREY); charLbl:SetPoint("TOPLEFT", PAD, y); charLbl:SetWidth(W - 2 * PAD); charLbl:SetJustifyH("LEFT")
        y = y - 18
        local status = Label(L, 9, GREY)

        local function Say(ok, msg)
            status:SetTextColor(ok and 0.75 or 0.85, ok and 0.75 or 0.55, ok and 0.75 or 0.5); status:SetText(msg or "")
        end

        local ROWS, RH = 8, 22
        local list = CreateFrame("Frame", nil, L)
        list:SetPoint("TOPLEFT", PAD, y); list:SetSize(W - 2 * PAD, RH * ROWS)
        list.rows = {}
        for r = 1, ROWS do
            local row = CreateFrame("Frame", nil, list)
            row:SetSize(W - 2 * PAD, RH - 2); row:SetPoint("TOPLEFT", 0, -(r - 1) * RH)
            local del = CreateFrame("Button", nil, row, BACKDROP)
            del:SetSize(20, 20); del:SetPoint("RIGHT", 0, 0); Box(del, 1); Hover(del)
            local dx = Label(del, 11); dx:SetPoint("CENTER", 1, 0); dx:SetText("x")
            local function Small(text, w)
                local b = CreateFrame("Button", nil, row, BACKDROP)
                b:SetSize(w, 20); Box(b, 1); b:SetBackdropColor(0.08, 0.08, 0.08, 1); Hover(b)
                b.label = Label(b, 10); b.label:SetPoint("CENTER"); b.label:SetText(text)
                return b
            end
            local mine = Small("Этому персонажу", 110); mine:SetPoint("RIGHT", del, "LEFT", -4, 0)
            local load = Small("Загрузить", 76); load:SetPoint("RIGHT", mine, "LEFT", -4, 0)
            row.name = Label(row, 11); row.name:SetPoint("LEFT", 2, 0); row.name:SetPoint("RIGHT", load, "LEFT", -6, 0)
            row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
            load:SetScript("OnClick", function()
                local ok, msg = ns.LoadProfile(row.profile)
                Say(ok, ok and ("Загружен профиль «"..row.profile.."»") or msg); Changed()
            end)
            mine:SetScript("OnClick", function()
                if ns.CharProfile() == row.profile then
                    ns.SetCharProfile(nil); Say(true, "Персонаж больше не привязан к профилю")
                else
                    local ok, msg = ns.LoadProfile(row.profile)
                    if ok then ns.SetCharProfile(row.profile); Say(true, "Профиль «"..row.profile.."» — для этого персонажа")
                    else Say(false, msg) end
                end
                Changed()
            end)
            del:SetScript("OnClick", function()
                if row.armed and GetTime() - row.armed < 4 then
                    row.armed = nil; ns.DeleteProfile(row.profile); Say(true, "Профиль удалён")
                else
                    row.armed = GetTime(); Say(false, "Удалить «"..row.profile.."»? Нажмите x ещё раз")
                end
                Changed()
            end)
            row.mine = mine
            list.rows[r] = row
        end
        list.empty = Label(list, 10, GREY); list.empty:SetPoint("TOPLEFT", 0, -4)
        list.empty:SetText("Профилей пока нет. Сохраните текущие настройки ниже.")
        list.Refresh = function()
            local names = ns.ProfileList and ns.ProfileList() or {}
            local cur = ns.CharProfile and ns.CharProfile()
            charLbl:SetText(cur and ("Этот персонаж: профиль «"..cur.."» (сохраняется сам при выходе)")
                or "Этот персонаж: общие настройки аккаунта (без профиля)")
            for r, row in ipairs(list.rows) do
                local n = names[r]
                row.profile = n
                if n then
                    row.name:SetText(n)
                    local on = cur == n
                    row.mine.label:SetText(on and "Отвязать" or "Этому персонажу")
                    local c = on and GOLD or { 0.9, 0.9, 0.9 }
                    row.name:SetTextColor(c[1], c[2], c[3])
                    row:Show()
                else
                    row:Hide()
                end
            end
            list.empty:SetShown(#names == 0)
        end
        table.insert(widgets, list)
        y = y - RH * ROWS - 6

        -- Сохранить текущие настройки как профиль
        local nameBox = CreateFrame("EditBox", nil, L, BACKDROP)
        nameBox:SetPoint("TOPLEFT", PAD, y); nameBox:SetSize(HALF, 22); Box(nameBox, 1)
        nameBox:SetAutoFocus(false); nameBox:SetFontObject(ns.Font(11, "")); nameBox:SetTextInsets(6, 6, 0, 0)
        nameBox:SetTextColor(0.9, 0.9, 0.9); nameBox:SetMaxLetters(40)
        local nph = Label(nameBox, 10, GREY); nph:SetPoint("LEFT", 6, 0); nph:SetText("название профиля")
        local function NPH() nph:SetShown(nameBox:GetText() == "" and not nameBox:HasFocus()) end
        nameBox:SetScript("OnTextChanged", NPH)
        nameBox:SetScript("OnEditFocusGained", NPH); nameBox:SetScript("OnEditFocusLost", NPH)
        nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local function SaveNow()
            local ok, msg = ns.SaveProfile(nameBox:GetText())
            if ok then nameBox:SetText(""); nameBox:ClearFocus(); Say(true, "Сохранено: «"..msg.."»") else Say(false, msg) end
            Changed()
        end
        nameBox:SetScript("OnEnterPressed", SaveNow)
        Button(L, COL2, y, HALF, "Сохранить текущие", SaveNow)
        y = y - 28
        status:SetPoint("TOPLEFT", PAD, y); status:SetWidth(W - 2 * PAD); status:SetJustifyH("LEFT")
        y = y - 20
        heights[#heights + 1] = -y

        -- ---------- перенос строкой ----------
        y = TOP
        Header(R, y, "ПЕРЕНОС НА ДРУГОЙ АККАУНТ"); y = y - 24
        local box = CreateFrame("EditBox", nil, R, BACKDROP)
        box:SetPoint("TOPLEFT", PAD, y); box:SetSize(W - 2 * PAD, 22); Box(box, 1)
        box:SetAutoFocus(false); box:SetFontObject(ns.Font(10, "")); box:SetTextInsets(6, 6, 0, 0)
        box:SetTextColor(0.85, 0.85, 0.85); box:SetMaxLetters(0)
        local bph = Label(box, 10, GREY); bph:SetPoint("LEFT", 6, 0); bph:SetText("сюда — строка профиля")
        local function BPH() bph:SetShown(box:GetText() == "" and not box:HasFocus()) end
        box:SetScript("OnTextChanged", BPH)
        box:SetScript("OnEditFocusGained", function(self) self:HighlightText(); BPH() end)
        box:SetScript("OnEditFocusLost", BPH)
        box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        y = y - 28
        local pstat = Label(R, 9, GREY)
        Button(R, PAD, y, HALF, "Экспорт", function()
            box:SetText(ns.ExportString()); box:SetFocus(); box:HighlightText()
            pstat:SetTextColor(0.75, 0.75, 0.75); pstat:SetText("Строка выделена — нажмите Ctrl+C и вставьте на другом аккаунте.")
        end)
        Button(R, COL2, y, HALF, "Импорт", function()
            local ok, msg = ns.ImportString(box:GetText())
            pstat:SetTextColor(ok and 0.75 or 0.85, ok and 0.75 or 0.55, ok and 0.75 or 0.5)
            pstat:SetText(ok and "Настройки загружены из строки. Сохраните их как профиль слева, если нужно." or msg)
        end)
        y = y - 28
        pstat:SetPoint("TOPLEFT", PAD, y); pstat:SetWidth(W - 2 * PAD); pstat:SetJustifyH("LEFT")
        y = y - 30
        Header(R, y, "КАК ЭТО РАБОТАЕТ"); y = y - 22
        y = Hint(R, y, "• Профили общие для всего аккаунта — любой персонаж может их загрузить.\n"
            .."• «Этому персонажу» — профиль загружается при входе этим персонажем и сам сохраняет его изменения при выходе. "
            .."Так у каждого персонажа свои настройки.\n"
            .."• Без профиля персонаж использует общие настройки аккаунта (как раньше).\n"
            .."• Другой аккаунт или компьютер: «Экспорт» -> Ctrl+C, там «Импорт» -> Ctrl+V.\n"
            .."• В строке все настройки, включая позиции панелей.", 9)
        heights[#heights + 1] = -y
    end

    local h = 0
    for _, v in ipairs(heights) do h = math.max(h, v) end
    win:SetHeight(h + 10)
    win:SetScript("OnShow", function()
        for _, w in ipairs(widgets) do w:Refresh() end
        ShowTab(ET().cfgTab or "block")
    end)
    ShowTab(ET().cfgTab or "block")
    win:Hide()
end

function ns.OpenConfig()
    if not win then Build() end
    win:Show(); win:Raise()
end

function ns.ToggleConfig()
    if win and win:IsShown() then win:Hide() else ns.OpenConfig() end
end

-- Тест-режим, включённый не из окна, тоже обновляет кнопку
table.insert(ns.testHooks, function()
    if win and win:IsShown() then for _, w in ipairs(widgets) do w:Refresh() end end
end)

-- Меню аддонов (кнопка-компас у мини-карты) — функция указана в .toc
function RogueTick_OnAddonCompartmentClick()
    ns.ToggleConfig()
end

-- Страница в Esc -> Настройки -> AddOns: кнопка, открывающая наше окно
local function RegisterBlizzardPanel()
    local p = CreateFrame("Frame")
    p.name = "Rogue Tick"
    local t = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16); t:SetText("Rogue Tick")
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(220, 26); b:SetPoint("TOPLEFT", 16, -50); b:SetText("Открыть настройки")
    b:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then pcall(HideUIPanel, SettingsPanel) end
        ns.OpenConfig()
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        pcall(function()
            local cat = Settings.RegisterCanvasLayoutCategory(p, "Rogue Tick")
            Settings.RegisterAddOnCategory(cat)
        end)
    elseif InterfaceOptions_AddCategory then
        pcall(InterfaceOptions_AddCategory, p)
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    RegisterBlizzardPanel()
    self:UnregisterEvent("ADDON_LOADED")
end)
