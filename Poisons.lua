-- =============================================
-- ЯДЫ: маленькая панель из двух кнопок — правая рука (основное оружие) и левая.
--   ЛКМ (или своя клавиша) — нанести выбранный яд на это оружие.
--   ПКМ — меню: яды, которые есть в сумках. Ctrl + перетащить — двигать панель (вне боя).
-- Иконка — выбранный яд, снизу — сколько минут осталось на оружии, сверху — сколько в сумках.
-- Яда нет на оружии или осталось меньше 5 минут — рамка тёплая (не красная).
-- Нанесение — защищённое действие: выбор яда меняется только вне боя.
-- =============================================
local ADDON, ns = ...
local issecret = ns.issecret

local WHITE = "Interface\\Buttons\\WHITE8X8"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local C_OK = { 0.20, 0.20, 0.20 }
local C_WARN = { 0.88, 0.66, 0.34 } -- яда нет / кончается
local LOW_MS = 5 * 60 * 1000

local function S() return EnergyTickSettings end
local HANDS = {
    { key = "MH", slot = 16, setting = "poisonMH", name = "Правая рука", prefer = { "Instant", "Быстродейств" } },
    { key = "OH", slot = 17, setting = "poisonOH", name = "Левая рука", prefer = { "Deadly", "Смертельн" } },
}
ns.POISON_BIND = { MH = "CLICK RogueTickPoisonMH:LeftButton", OH = "CLICK RogueTickPoisonOH:LeftButton" }
BINDING_HEADER_ROGUETICK = "Rogue Tick"
_G["BINDING_NAME_" .. ns.POISON_BIND.MH] = "Яд: правая рука"
_G["BINDING_NAME_" .. ns.POISON_BIND.OH] = "Яд: левая рука"

-- ---------- яды в сумках ----------
-- Известные яды (Classic): быстродействующий, смертельный, калечащий, дурманящий, нейтрализующий.
-- Остальные узнаём по названию («яд» / «Poison») среди расходуемых предметов.
local KNOWN = {}
for _, id in ipairs({ 6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844,
    3775, 3776, 5237, 6951, 9186, 10918, 10920, 10921, 10922 }) do KNOWN[id] = true end

local function ItemName(id)
    local ok, n = pcall(function()
        if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
        return (GetItemInfo(id))
    end)
    return ok and type(n) == "string" and n or nil
end
local function ItemIcon(id)
    local ok, t = pcall(function()
        if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
        return GetItemIcon(id)
    end)
    return ok and t or QUESTION
end
local function ItemClass(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not fn then return nil end
    local ok, _, _, _, _, _, classID = pcall(fn, id)
    return ok and classID or nil
end
local function IsPoison(id)
    if KNOWN[id] then return true end
    if ItemClass(id) ~= 0 then return false end -- 0 — расходуемые
    local n = ItemName(id)
    return n and (n:find("яд") or n:find("Яд") or n:find("Poison") or n:find("poison")) and true or false
end
-- «Быстродействующий яд IV» -> «Быстродействующий яд» (одно семейство разных рангов)
local function Family(name) return name and (name:gsub("%s+[IVX]+$", "")) or nil end

local bagList, bagCount = {}, {}
local function ScanBags()
    wipe(bagList); wipe(bagCount)
    local CC = C_Container
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
        local okN, n = pcall(CC and CC.GetContainerNumSlots or GetContainerNumSlots, bag)
        if okN and type(n) == "number" then
            for slot = 1, n do
                local id, cnt
                if CC and CC.GetContainerItemInfo then
                    local info = CC.GetContainerItemInfo(bag, slot)
                    if info then id, cnt = info.itemID, info.stackCount end
                elseif GetContainerItemInfo then
                    local _, c, _, _, _, _, _, _, _, i = GetContainerItemInfo(bag, slot)
                    id, cnt = i, c
                end
                if id and not issecret(id) and IsPoison(id) then
                    if not bagCount[id] then bagList[#bagList + 1] = id end
                    bagCount[id] = (bagCount[id] or 0) + (cnt or 1)
                end
            end
        end
    end
    table.sort(bagList, function(a, b)
        local na, nb = ItemName(a) or "", ItemName(b) or ""
        if na ~= nb then return na < nb end
        return a > b
    end)
end

-- Какой яд нанести на руку: выбранный; кончился — другой ранг того же яда; не выбран — подходящий по умолчанию
local function Resolve(h)
    local want = S()[h.setting]
    if want and bagCount[want] then return want end
    if want then
        local fam = Family(ItemName(want))
        local best
        for _, id in ipairs(bagList) do
            if Family(ItemName(id)) == fam and (not best or id > best) then best = id end
        end
        if best then return best end
        return want -- выбран, но в сумках нет: показываем серым
    end
    for _, p in ipairs(h.prefer) do
        for _, id in ipairs(bagList) do
            local n = ItemName(id)
            if n and n:find(p) then return id end
        end
    end
    return bagList[1]
end

-- ---------- панель ----------
local bar = CreateFrame("Frame", "RogueTickPoisonBar", UIParent)
bar:SetMovable(true); bar:SetClampedToScreen(true)
bar:SetFrameStrata("MEDIUM")

local function SavePos()
    local cx, cy = bar:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local sc = bar:GetEffectiveScale() / UIParent:GetEffectiveScale()
    if cx and ux then S().poisonX, S().poisonY = math.floor(cx * sc - ux + 0.5), math.floor(cy * sc - uy + 0.5) end
end

local buttons = {}
local lastApply = 0
local pending = false
local menu -- создаётся при первом ПКМ

local function NewHand(h, i)
    local b = CreateFrame("Button", "RogueTickPoison" .. h.key, bar,
        "SecureActionButtonTemplate" .. (BackdropTemplateMixin and ", BackdropTemplate" or ""))
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 } })
    b:SetBackdropColor(0, 0, 0, 0.6); b:SetBackdropBorderColor(C_OK[1], C_OK[2], C_OK[3], 1)
    ns.Round(b)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ns.RoundTex(b, b, { b.icon }, -1)
    b.time = b:CreateFontString(nil, "OVERLAY"); ns.SetFont(b.time, 10)
    b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, 2); b.time:SetTextColor(0.9, 0.9, 0.9)
    b.count = b:CreateFontString(nil, "OVERLAY"); ns.SetFont(b.count, 8)
    b.count:SetPoint("TOPRIGHT", b, "TOPRIGHT", -2, -2); b.count:SetTextColor(0.72, 0.72, 0.72)
    b.hand = h
    -- двигать: Ctrl + перетащить (или когда снято «Закрепить всё»)
    b:SetScript("OnDragStart", function()
        if (IsControlKeyDown() or ns.IsMovable("poison")) and not InCombatLockdown() then bar:StartMoving() end
    end)
    b:SetScript("OnDragStop", function() bar:StopMovingOrSizing(); SavePos() end)
    b:RegisterForDrag("LeftButton")
    b:HookScript("OnClick", function(self, button, down)
        if down then return end -- меню и отметка — один раз, на отпускание
        if button == "RightButton" then
            if InCombatLockdown() then return end
            ns.PoisonMenu(self)
        elseif button == "LeftButton" then
            lastApply = GetTime()
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(h.name)
        if self.item then GameTooltip:AddLine(ItemName(self.item) or "?", 0.8, 0.8, 0.8) end
        GameTooltip:AddLine("ЛКМ — нанести, ПКМ — выбрать яд", 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Ctrl + перетащить — двигать", 0.6, 0.6, 0.6)
        local key = GetBindingKey and GetBindingKey(ns.POISON_BIND[h.key])
        if key then GameTooltip:AddLine("Клавиша: " .. key, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = b
    return b
end
for i, h in ipairs(HANDS) do NewHand(h, i) end

-- Защищённые атрибуты: «/use яд» + «/use слот». Только вне боя; в бою — после боя.
local function ApplySecure()
    if InCombatLockdown() then pending = true; return end
    pending = false
    local movable = ns.IsMovable("poison")
    for _, b in ipairs(buttons) do
        local id = b.item
        if id and not movable then
            b:SetAttribute("type1", "macro")
            b:SetAttribute("macrotext1", "/use item:" .. id .. "\n/use " .. b.hand.slot)
        else
            b:SetAttribute("type1", nil) -- двигаем панель — клик ничего не наносит
        end
        -- Ctrl+ЛКМ (отпустили после перетаскивания) — ничего не наносит
        b:SetAttribute("ctrl-type1", "macro"); b:SetAttribute("ctrl-macrotext1", "")
        b:SetAttribute("type2", nil)
    end
end

local function Layout()
    if InCombatLockdown() then pending = true; return end
    local sz = S().poisonSize or 30
    bar:SetSize(sz * 2 + 4, sz)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", S().poisonX or 0, S().poisonY or -220)
    for i, b in ipairs(buttons) do
        b:SetSize(sz, sz); b:ClearAllPoints()
        b:SetPoint("LEFT", bar, "LEFT", (i - 1) * (sz + 4), 0)
        ns.SetFont(b.time, math.max(8, math.floor(sz / 3)))
    end
end

local function IsRogue()
    local _, cls = UnitClass("player")
    return cls == "ROGUE"
end
local function HasOffWeapon()
    local id = GetInventoryItemID("player", 17)
    return id and not issecret(id) and ItemClass(id) == 2
end

local function Refresh()
    local changed = false
    for _, b in ipairs(buttons) do
        local id = Resolve(b.hand)
        if id ~= b.item then b.item = id; changed = true end
        b.icon:SetTexture(id and ItemIcon(id) or QUESTION)
        local n = id and bagCount[id] or 0
        b.icon:SetDesaturated(n == 0)
        b.icon:SetAlpha(n == 0 and 0.5 or 1)
        b.count:SetText(id and n or "")
    end
    if changed then ApplySecure() end
end

function ns.ApplyPoisons()
    local on = S().poisonBar ~= false and IsRogue()
    if InCombatLockdown() then pending = true; return end
    bar:SetShown(on)
    if not on then return end
    Layout(); ScanBags(); Refresh(); ApplySecure()
end

-- ---------- меню выбора ----------
local ROW = 20
function ns.PoisonMenu(btn)
    if not menu then
        menu = CreateFrame("Frame", "RogueTickPoisonMenu", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        menu:SetFrameStrata("DIALOG"); menu:SetClampedToScreen(true)
        menu:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 } })
        menu:SetBackdropColor(0.04, 0.04, 0.04, 0.95); menu:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)
        ns.Round(menu)
        menu.title = menu:CreateFontString(nil, "OVERLAY"); ns.SetFont(menu.title, 10)
        menu.title:SetPoint("TOPLEFT", 8, -6); menu.title:SetTextColor(0.72, 0.72, 0.72)
        menu.rows = {}
        menu:Hide()
        tinsert(UISpecialFrames, "RogueTickPoisonMenu") -- закрыть по Esc
        menu:SetScript("OnEvent", function(self, e)
            if e == "PLAYER_REGEN_DISABLED" then self:Hide()
            elseif e == "GLOBAL_MOUSE_DOWN" and not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
                self:Hide()
            end
        end)
        menu:SetScript("OnShow", function(self)
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
        end)
        menu:SetScript("OnHide", function(self) self:UnregisterAllEvents() end)
    end
    if menu:IsShown() and menu.owner == btn then menu:Hide(); return end
    ScanBags()
    menu.owner = btn
    local h = btn.hand
    menu.title:SetText(h.name .. ":")
    local list = bagList
    local w = 150
    for i = 1, math.max(#list, 1) do
        local r = menu.rows[i]
        if not r then
            r = CreateFrame("Button", nil, menu)
            r:SetHeight(ROW)
            r.hl = r:CreateTexture(nil, "BACKGROUND"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 1, 1, 0.06); r.hl:Hide()
            r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(ROW - 4, ROW - 4); r.icon:SetPoint("LEFT", 4, 0)
            r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            r.text = r:CreateFontString(nil, "OVERLAY"); ns.SetFont(r.text, 10)
            r.text:SetPoint("LEFT", r.icon, "RIGHT", 6, 0); r.text:SetJustifyH("LEFT")
            r.num = r:CreateFontString(nil, "OVERLAY"); ns.SetFont(r.num, 9)
            r.num:SetPoint("RIGHT", -6, 0); r.num:SetTextColor(0.6, 0.6, 0.6)
            r:SetScript("OnEnter", function(self) self.hl:Show() end)
            r:SetScript("OnLeave", function(self) self.hl:Hide() end)
            r:SetScript("OnClick", function(self)
                if not self.id or InCombatLockdown() then return end
                S()[menu.owner.hand.setting] = self.id
                menu:Hide()
                Refresh(); ApplySecure()
            end)
            menu.rows[i] = r
        end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 1, -18 - (i - 1) * ROW); r:SetPoint("TOPRIGHT", -1, -18 - (i - 1) * ROW)
        local id = list[i]
        r.id = id
        if id then
            r.icon:SetTexture(ItemIcon(id)); r.icon:Show()
            r.text:SetText(ItemName(id) or ("item:" .. id))
            local sel = id == btn.item
            r.text:SetTextColor(sel and 0.96 or 0.85, sel and 0.80 or 0.85, sel and 0.40 or 0.85)
            r.num:SetText(bagCount[id] or "")
            w = math.max(w, r.text:GetStringWidth() + ROW + 50)
        else
            r.icon:Hide(); r.num:SetText("")
            r.text:SetText("В сумках нет ядов"); r.text:SetTextColor(0.55, 0.55, 0.55)
        end
        r:Show()
    end
    for i = math.max(#list, 1) + 1, #menu.rows do menu.rows[i]:Hide() end
    menu:SetSize(w, 22 + math.max(#list, 1) * ROW)
    menu:ClearAllPoints(); menu:SetPoint("BOTTOMLEFT", btn, "TOPLEFT", 0, 4)
    menu:Show()
end

-- ---------- время на оружии, прозрачность, «двигать» ----------
local acc, wasMovable = 0, nil
local function Fmt(ms)
    local m = ms / 60000
    if m >= 1 then return math.floor(m + 0.5) .. "м" end
    return math.floor(ms / 1000) .. "с"
end
bar:SetScript("OnUpdate", function(self, el)
    acc = acc + el
    if acc < 0.25 then return end
    acc = 0
    local inCombat = InCombatLockdown()
    local movable = ns.IsMovable("poison")
    if movable ~= wasMovable and not inCombat then wasMovable = movable; ApplySecure() end
    local ok, hasMH, mhExp, mhCh, _, hasOH, ohExp, ohCh = pcall(GetWeaponEnchantInfo)
    local state = {
        { has = hasMH, exp = mhExp, ch = mhCh, weapon = GetInventoryItemID("player", 16) },
        { has = hasOH, exp = ohExp, ch = ohCh, weapon = HasOffWeapon() },
    }
    local warn = false
    for i, b in ipairs(buttons) do
        local st = state[i]
        local txt, low = "", false
        if not st.weapon then
            txt = ""; b:SetAlpha(0.35)
        elseif ok and not issecret(st.has) then
            if st.has then
                if type(st.exp) == "number" and not issecret(st.exp) then
                    txt = Fmt(st.exp); low = st.exp < LOW_MS
                end
                if type(st.ch) == "number" and not issecret(st.ch) and st.ch > 0 then txt = tostring(st.ch) end
            else
                low = true
            end
            b:SetAlpha(1)
        else
            b:SetAlpha(1)
        end
        b.time:SetText(txt)
        if low ~= b.low then
            b.low = low
            local c = low and C_WARN or C_OK
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
        warn = warn or low
    end
    -- в бою — бледнее, если всё нанесено (минимум шума)
    self:SetAlpha((inCombat and not warn and not movable) and 0.45 or 1)
end)

-- ---------- события ----------
local scanQueued = false
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("REPLACE_ENCHANT")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
ev:SetScript("OnEvent", function(_, e)
    if e == "PLAYER_LOGIN" then
        ns.ApplyPoisons()
    elseif e == "REPLACE_ENCHANT" then
        -- «Заменить яд?» — нажали нашу кнопку только что: подтверждаем сами
        if GetTime() - lastApply < 3 and ReplaceEnchant then
            if pcall(ReplaceEnchant) and StaticPopup_Hide then StaticPopup_Hide("REPLACE_ENCHANT") end
        end
    elseif e == "PLAYER_REGEN_ENABLED" then
        if pending then ns.ApplyPoisons() end
    elseif bar:IsShown() and not scanQueued then
        -- сумки / оружие / данные предметов: пересчитать один раз чуть позже (события идут пачками)
        scanQueued = true
        C_Timer.After(0.3, function() scanQueued = false; ScanBags(); Refresh() end)
    end
end)

-- ---------- своя клавиша: нажать кнопку в настройках, затем клавишу ----------
-- Esc — отмена, Backspace — снять клавишу. Сохраняется в привязках игры (видно и в меню Blizzard).
local capture = CreateFrame("Frame", nil, UIParent)
capture:SetFrameStrata("TOOLTIP"); capture:EnableKeyboard(true); capture:Hide()
local MODS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }
ns.poisonCapture = nil -- "MH" / "OH", пока ждём клавишу
capture:SetScript("OnKeyDown", function(self, key)
    if MODS[key] then return end
    local hand, done = ns.poisonCapture, self.done
    self:Hide(); ns.poisonCapture = nil
    if key == "ESCAPE" or not hand or InCombatLockdown() then if done then done() end; return end
    local cmd = ns.POISON_BIND[hand]
    -- старые клавиши этого действия — снять
    while GetBindingKey(cmd) do SetBinding(GetBindingKey(cmd)) end
    if key ~= "BACKSPACE" then
        local full = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "") .. key
        SetBinding(full, cmd)
    end
    local set = GetCurrentBindingSet and GetCurrentBindingSet()
    if set and SaveBindings then SaveBindings(set) end
    if done then done() end
end)
function ns.CapturePoisonKey(hand, done)
    if InCombatLockdown() then return end
    ns.poisonCapture, capture.done = hand, done
    capture:Show()
end
function ns.PoisonKeyText(hand)
    local k = GetBindingKey and GetBindingKey(ns.POISON_BIND[hand])
    return k or "нет"
end
