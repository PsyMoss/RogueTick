-- =============================================
-- RogueTick: экономия энергии для WoW Forever (плавный реген, без 2-сек тиков)
--
-- Полоса энергии с маркерами:
--   [ ждём ] -- G -- [ ДЕРЖАТЬ ЗДЕСЬ ] -- | -- [ НЕ ПЕРЕХОДИТЬ ]
--   G   = цена вашего основного удара (выучивается сам или /et gen 45)
--   |   = граница переполнения: max - реген * (ГКД + пинг).
--         Выше неё вы не успеете потратить энергию до капа -> она сгорает.
--   K   = резерв под Kick: пульсирует, когда цель кастует.
--   Внизу тонкая белая полоска — остаток ГКД, вверху голубая — каст цели.
-- Статистика за бой: потеряно энергии (стояли в капе) и эффективность %.
-- =============================================
local ADDON, ns = ...
local issecret, Read, SafeText = ns.issecret, ns.Read, ns.SetText

local ENERGY = 3
local KICK_ID = 1766
local GCD_ID = 61304
local DEFAULT_GEN, DEFAULT_KICK, DEFAULT_REGEN, DEFAULT_GCD = 45, 25, 10, 1.0

-- [[ НАСТРОЙКИ ]]
local DEFAULTS = {
 soundID = 569595, sound = true, width = 260, height = 22,
 x = 0, y = -150, locked = false,
 genCost = "auto",  -- "auto" или число
 kickCost = "auto", -- "auto" или число
 genAutoCost = nil, -- что выучено автоматически
 sndMult = 1,
 showSnD = true, showHUD = false, showCP = true,
 barStyle = "mono", -- "mono" — монохром, "soft" — мягкий цвет
 bars = {},         -- свои полоски: { spell, name, icon, kind = "cd"|"buff"|"debuff", y }
 barIcons = true,   -- маленькие иконки слева от полосок
 sndAlert = true,   -- SnD спал в бою -> полоска горит оранжевым
 sndEndPulse = true, -- последние 3 с SnD: красная, мягко пульсирует
 showMarks = false, -- метки на энергии (цена удара, кап, K) и полупрозрачные зоны
 cpHeight = 6, stripHeight = 6, -- толщина комбо и полосок под полосой
 radius = 3,        -- скругление углов, px (0 — квадратные)
 bgGray = 0, bgAlpha = 0.9,          -- фон: 0 чёрный … 0.5 серый; плотность 0 … 1
 borderStyle = "flat", borderSize = 1, -- рамка: flat | light | shadow | classic | none; толщина 1…4
 energyShadow = true, -- тень: сколько энергии будет через один ГКД
 fightSummary = true, -- итог боя одной строкой (гаснет сам)
 showStats = true,  -- статистика (потери энергии, эффективность) под полосками
 noNumbers = false, -- убрать все цифры с полос (энергия, жизнь, таймеры, проценты над головой)
 fontScale = 1,     -- масштаб шрифтов на панелях
 helpAttack = true, helpSave = true, -- помощник: ячейки «удар» и «защита»
 helpSize = 36, helpCaptions = true, helpHP = 35, helpPotion = true,
 -- над головой: свои полоски вместо стандартных
 npOn = true, npMode = "bar", npWidth = 110, npHP = 8, npName = true, npPct = true,
 npCast = true, npCastH = 5, npAggro = false, npLevel = true, npPoison = true, npSap = true, npCP = true, npCPSize = 6, npEnergy = true, npEnH = 5, npFade = true, npColor = "reaction", npFriendName = true, npRaid = true,
 npCubeW = 34, npCubeH = 16, npCubeName = false,
 helpGlow = true,                    -- аура вокруг цели над головой — цветом совета «Удар»
 helpReserve = true,                 -- против кастеров: совет «Удар» горит, только если после удара останется энергия на Kick
 helpEnergy = true,                  -- удар: показывать ожидание энергии (заполнение + секунды)
 helpSnD = true, helpEvis = true, helpEvisCP = 5, helpSnDRefresh = 1.2, -- правила удара
 helpDisarm = true, -- обезоружить бойца ближнего боя, когда он бьёт вас
 castKickZone = true, -- каст цели: тёмная зона «поздно для Kick» в конце
 poisonBar = true, poisonSize = 30, -- панель ядов (правая / левая рука)
 helpOpener = true, -- в невидимости: чем начать бой (Ambush / Cheap Shot / Garrote)
 helpKick = true, helpEvasion = true, helpVanish = true, helpFeint = true, helpThreat = 90, -- правила защиты
 hudCells = {},     -- боевая панель: какие ячейки включены (пусто = по умолчанию)
 oocAlpha = 0.35,   -- прозрачность панелей вне боя
 minimapAngle = 215, minimapHide = false,
}
EnergyTickSettings = EnergyTickSettings or {}
local function ApplyDefaults()
 for k, v in pairs(DEFAULTS) do
  if EnergyTickSettings[k] == nil then
   if type(v) == "table" then local t = {}; for a, b in pairs(v) do t[a] = b end; v = t end
   EnergyTickSettings[k] = v
  end
 end
end
ApplyDefaults()

local WHITE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

-- Цвета зон
-- Две палитры, без мигания. Монохром: чем ближе к капу, тем светлее.
-- Мягкий цвет: приглушённые тона, ничего не режет глаз.
local PALETTES = {
 mono = {
  wait = {0.36, 0.36, 0.36}, -- ниже цены удара: копим
  hold = {0.60, 0.60, 0.60}, -- рабочая зона
  cap  = {0.90, 0.90, 0.90}, -- за границей: трать немедленно
  kick = {0.70, 0.70, 0.70},
  gen  = {0.60, 0.60, 0.60},
  go   = {0.95, 0.95, 0.95},
  snd  = {0.60, 0.60, 0.60},
  cpOn = {0.55, 0.55, 0.55}, cpFull = {0.92, 0.92, 0.92}, -- комбо: набрано / 5 из 5
  -- энергия — чуть-чуть жёлтая, как привычно в игре (остальное серое)
  fill = { wait = {0.40, 0.40, 0.40}, hold = {0.70, 0.64, 0.42}, cap = {0.88, 0.80, 0.52} }, -- серый: копим
  hp = { hi = {0.50, 0.50, 0.50}, mid = {0.75, 0.75, 0.75}, low = {0.95, 0.95, 0.95} }, -- жизнь: < 50% / < 30%
  -- боевая панель: dim — спокойно, ok — норма, warn — внимание, bad — действуй
  hud = { text = {0.85, 0.85, 0.85}, dim = {0.42, 0.42, 0.42}, ok = {0.68, 0.68, 0.68},
          warn = {0.88, 0.88, 0.88}, bad = {1, 1, 1}, go = {0.95, 0.95, 0.95}, alert = {0.88, 0.50, 0.16} },
  holdBand = 0.05, capBand = 0.10,
 },
 soft = {
  wait = {0.60, 0.50, 0.32},
  hold = {0.40, 0.60, 0.44},
  cap  = {0.96, 0.80, 0.40}, -- кап — та же энергия, только ярче (не красный: красный = «добей»)
  kick = ns.ACT.kick,          -- Kick — бирюзовый
  gen  = {0.85, 0.85, 0.85},
  go   = {0.56, 0.78, 0.60},
  -- У каждой полосы свой тон (все приглушённые), чтобы не сливались:
  --   жизнь — зелёный, энергия — жёлтый, комбо — цветом совета, SnD — оранжевый,
  --   свои полоски — лиловый, свой каст — лавандовый, каст цели/Kick — бирюзовый
  snd  = ns.ACT.snd, -- SnD — оранжевый, как в совете
  strip = {0.76, 0.54, 0.70},
  -- комбо: коралл; на 5/5 — светлее, «добивай»
  cpOn = {0.82, 0.52, 0.44}, cpFull = {0.97, 0.68, 0.56},
  hp = { hi = {0.42, 0.68, 0.46}, mid = {0.86, 0.62, 0.36}, low = {0.78, 0.36, 0.34} },
  -- заливка энергии: всегда «энергия» — мягкий жёлтый; у капа теплее и ярче
  fill = { wait = {0.42, 0.42, 0.42}, hold = {0.82, 0.73, 0.40}, cap = {0.94, 0.80, 0.44} }, -- серый: копим
  hud = { text = {0.85, 0.85, 0.85}, dim = {0.45, 0.45, 0.45}, ok = {0.62, 0.80, 0.64},
          warn = {0.88, 0.74, 0.44}, bad = {0.90, 0.44, 0.40}, go = {0.56, 0.78, 0.60}, alert = {0.88, 0.50, 0.16} },
  holdBand = 0.07, capBand = 0.12,
 },
}
local P = PALETTES.mono
local C_WAIT, C_HOLD, C_CAP, C_KICK = P.wait, P.hold, P.cap, P.kick

-- =============================================
-- Данные игры (всё через безопасное чтение)
-- =============================================
local function SpellEnergyCost(spellID)
 if not spellID then return nil end
 local ok, v = pcall(function()
  local costs
  if C_Spell and C_Spell.GetSpellPowerCost then costs = C_Spell.GetSpellPowerCost(spellID)
  elseif GetSpellPowerCost then costs = GetSpellPowerCost(spellID) end
  if type(costs) ~= "table" then return nil end
  for _, c in ipairs(costs) do
   if c.type == ENERGY and c.cost and c.cost > 0 then return c.cost end
  end
 end)
 if ok and type(v) == "number" then return v end
 return nil
end

-- Реген в секунду: из API, иначе замер по факту, иначе 10
local measuredRegen
local function RegenRate()
 local ok, a, b = pcall(GetPowerRegen)
 if ok and not issecret(a) and not issecret(b) then
  local r = (type(b) == "number" and b > 0 and b) or (type(a) == "number" and a > 0 and a)
  if r then return r end
 end
 return measuredRegen or DEFAULT_REGEN
end

-- ГКД: остаток и длительность (если кулдауны скрыты — считаем 1с)
local gcdLen = DEFAULT_GCD
local function GCDRemaining()
 local ok, s, d = pcall(function()
  if C_Spell and C_Spell.GetSpellCooldown then
   local i = C_Spell.GetSpellCooldown(GCD_ID)
   if i then return i.startTime, i.duration end
   return nil
  end
  if GetSpellCooldown then return GetSpellCooldown(GCD_ID) end
 end)
 if not ok or issecret(s) or issecret(d) or type(s) ~= "number" or type(d) ~= "number" or d <= 0 then return 0 end
 if d <= 1.6 then gcdLen = d end
 return math.max(0, s + d - GetTime())
end

-- Основной удар: самый частый платный (>=15 энергии) каст
local castCount = {}
local function LearnCast(spellID)
 local cost = SpellEnergyCost(spellID)
 if not cost or cost < 15 then return end
 castCount[spellID] = (castCount[spellID] or 0) + 1
 local best, bestN = nil, 0
 for id, n in pairs(castCount) do if n > bestN then best, bestN = id, n end end
 local c = SpellEnergyCost(best)
 if c then EnergyTickSettings.genAutoCost = c end
end

local function GenCost()
 local g = EnergyTickSettings.genCost
 if type(g) == "number" then return g end
 return EnergyTickSettings.genAutoCost or DEFAULT_GEN
end

local kickAuto
local function KickCost()
 local k = EnergyTickSettings.kickCost
 if type(k) == "number" then return k end
 if not kickAuto then kickAuto = SpellEnergyCost(KICK_ID) end
 return kickAuto or DEFAULT_KICK
end

-- =============================================
-- ГЛАВНАЯ ПАНЕЛЬ
-- =============================================
local f = CreateFrame("Frame", "ET_MainFrame", UIParent, BACKDROP)
f:SetSize(EnergyTickSettings.width, EnergyTickSettings.height)
f:SetPoint("CENTER", UIParent, "CENTER", EnergyTickSettings.x, EnergyTickSettings.y)
f:SetFrameStrata("HIGH")
f:SetClampedToScreen(true)
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
-- в бою не двигаем: к полосе привязана защищённая кнопка фрейма игрока (единый блок)
-- В едином блоке главная — жизнь: за неё тянется весь блок, а энергия ходит только вверх-вниз
f:SetScript("OnDragStart", function(self)
 if not ns.IsMovable("main") or InCombatLockdown() then return end
 if ns.DockOn and ns.DockOn() then ns.EnergyDragStart() else self:StartMoving() end
end)
f:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then ns.ToggleUnlock("main") end end)
f:SetScript("OnDragStop", function(self)
 if self.vdrag then ns.EnergyDragStop(); return end
 self:StopMovingOrSizing(); ns.SavePos(self, EnergyTickSettings, "x", "y")
end)
f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1}})
f:SetBackdropColor(0, 0, 0, 1); f:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
ns.Round(f)
local baseLevel = f:GetFrameLevel()

-- Неоновая рамка (как в старом моде): горит, когда энергия за границей
local Neon = ns.RoundRing(f, 2) -- скруглённое кольцо за полосой

-- Полоса энергии
local EnergyBar = CreateFrame("StatusBar", "ET_EnergyBar", f)
EnergyBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1); EnergyBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
EnergyBar:SetStatusBarTexture(WHITE)
EnergyBar:SetStatusBarColor(C_HOLD[1], C_HOLD[2], C_HOLD[3], 0.85)
EnergyBar:SetMinMaxValues(0, 100); EnergyBar:SetValue(0)
EnergyBar:SetFrameLevel(baseLevel + 2)
-- Тень: та же полоса, сдвинутая на «реген за один ГКД». Видна только кусочком за заливкой.
-- Сдвиг — через диапазон (min/max), поэтому работает и со скрытой в бою энергией.
local NextBar = CreateFrame("StatusBar", nil, f)
NextBar:SetAllPoints(EnergyBar); NextBar:SetStatusBarTexture(WHITE)
NextBar:SetMinMaxValues(0, 100); NextBar:SetValue(0)
NextBar:SetFrameLevel(baseLevel + 1)
ns.RoundFill(NextBar, {})
do -- пустая дорожка — как у всех полос (один фон на весь блок)
 local bg = EnergyBar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(EnergyBar); bg:SetColorTexture(1, 1, 1, 0.05)
 ns.RoundFill(EnergyBar, { bg })
end

-- Слой зон (поверх заливки, полупрозрачный)
local zones = CreateFrame("Frame", nil, f)
zones:SetAllPoints(EnergyBar); zones:SetFrameLevel(baseLevel + 3)

local HoldBand = zones:CreateTexture(nil, "ARTWORK")
HoldBand:SetColorTexture(C_HOLD[1], C_HOLD[2], C_HOLD[3], 0.10)
local CapBand = zones:CreateTexture(nil, "ARTWORK")
CapBand:SetColorTexture(C_CAP[1], C_CAP[2], C_CAP[3], 0.22)

-- Слой маркеров (выходят за края полосы, чтобы их было видно и при полной заливке)
local marks = CreateFrame("Frame", nil, f)
marks:SetAllPoints(f); marks:SetFrameLevel(baseLevel + 4)

local allMarks = {}
local function MakeMarker(r, g, b, width, label, labelAbove)
 local line = marks:CreateTexture(nil, "OVERLAY", nil, 6)
 line:SetSize(width, f:GetHeight() + 8)
 line:SetColorTexture(r, g, b, 1)
 local shadow = marks:CreateTexture(nil, "OVERLAY", nil, 5)
 shadow:SetSize(width + 2, f:GetHeight() + 10)
 shadow:SetColorTexture(0, 0, 0, 0.9)
 shadow:SetPoint("CENTER", line, "CENTER")
 local t = marks:CreateFontString(nil, "OVERLAY")
 ns.SetFont(t, 9); t:SetTextColor(r, g, b)
 if labelAbove then t:SetPoint("BOTTOM", line, "TOP", 0, 1) else t:SetPoint("TOP", line, "BOTTOM", 0, -1) end
 t:SetText(label)
 local m = { line = line, shadow = shadow, text = t, x = nil, w = width }
 table.insert(allMarks, m)
 return m
end

-- Высота меток следует за высотой полосы (её можно менять в настройках)
local function ResizeMarkers()
 local h = f:GetHeight()
 for _, m in ipairs(allMarks) do
  m.line:SetSize(m.w, h + 8); m.shadow:SetSize(m.w + 2, h + 10); m.x = nil
 end
end

local GenMark  = MakeMarker(1, 1, 1, 2, "", true)
local CapMark  = MakeMarker(C_CAP[1], C_CAP[2], C_CAP[3], 2, "", true)
local KickMark = MakeMarker(C_KICK[1], C_KICK[2], C_KICK[3], 1, "K", true)

local function PlaceMarker(m, x)
 if m.x and math.abs(m.x - x) < 0.25 then return end
 m.x = x
 m.line:ClearAllPoints(); m.line:SetPoint("CENTER", f, "LEFT", x, 0)
end

-- ГКД (низ) и каст цели (верх)
local GCDBar = CreateFrame("StatusBar", nil, f)
GCDBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1); GCDBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
GCDBar:SetHeight(2); GCDBar:SetStatusBarTexture(WHITE); GCDBar:SetStatusBarColor(1, 1, 1, 0.8)
GCDBar:SetMinMaxValues(0, 1); GCDBar:SetValue(0); GCDBar:SetFrameLevel(baseLevel + 3)
ns.RoundTex(GCDBar, EnergyBar, { GCDBar:GetStatusBarTexture() })

local CastBar = CreateFrame("StatusBar", nil, f)
CastBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1); CastBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
CastBar:SetHeight(3); CastBar:SetStatusBarTexture(WHITE); CastBar:SetStatusBarColor(C_KICK[1], C_KICK[2], C_KICK[3], 1)
CastBar:SetReverseFill(true); CastBar:SetFrameLevel(baseLevel + 3); CastBar:Hide()
ns.RoundTex(CastBar, EnergyBar, { CastBar:GetStatusBarTexture() })

-- Тексты
local top = CreateFrame("Frame", nil, f)
top:SetAllPoints(f); top:SetFrameLevel(baseLevel + 6)
local function MakeText(size, r, g, b)
 local t = top:CreateFontString(nil, "OVERLAY")
 ns.SetFont(t, size); t:SetTextColor(r, g, b); return t
end
local txtEnergy = MakeText(12, 1, 1, 1);        txtEnergy:SetPoint("RIGHT", f, "RIGHT", -4, 0)
local txtNext   = MakeText(11, 1, 1, 1);        txtNext:SetPoint("LEFT", f, "LEFT", 4, 0)
-- Сверху: подписи маркеров и CP; снизу: полоска SnD и статистика
local txtEff    = MakeText(11, 0.9, 0.9, 0.9)
local txtWaste  = MakeText(11, 0.9, 0.9, 0.9)
local txtFight  = MakeText(11, 0.72, 0.72, 0.72); txtFight:SetAlpha(0) -- итог боя

-- =============================================
-- ЖИЗНЬ — верхняя часть той же полосы (единый блок: жизнь сверху, энергия снизу)
-- Рамки сливаются в одну: между ними — одна тонкая линия.
-- =============================================
local hpf = CreateFrame("Frame", "ET_HPFrame", f, BACKDROP)
-- отдельная полоса над энергией; тянется только вверх-вниз (смещение S.hpOffY)
local HP_DEFAULT_Y = 2
local function HPY() return EnergyTickSettings.hpOffY or HP_DEFAULT_Y end
local function PlaceHP()
 local y = HPY()
 hpf:ClearAllPoints()
 hpf:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, y); hpf:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, y)
end
PlaceHP()

-- Энергия тянется вверх-вниз относительно жизни: сама полоса (и всё, что под ней)
-- едет, а жизнь остаётся на месте. Только вне боя: к жизни привязана защищённая кнопка.
local hpDrag = CreateFrame("Frame")
function ns.EnergyDragStart()
 local S = EnergyTickSettings
 if S.x == nil or S.y == nil then ns.SavePos(f, S, "x", "y") end
 local ui = UIParent:GetEffectiveScale()
 local s = f:GetEffectiveScale() / ui
 local _, cy = GetCursorPosition()
 local from, y0, hp0 = cy / ui, S.y, HPY()
 f.vdrag = true
 hpDrag:SetScript("OnUpdate", function()
  if InCombatLockdown() then ns.EnergyDragStop(); return end
  local _, c = GetCursorPosition()
  local hp = hp0 - (c / ui - from) / s
  hp = math.max(-160, math.min(160, hp))
  if math.abs(hp - HP_DEFAULT_Y) < 4 then hp = HP_DEFAULT_Y end -- прилипает под жизнь
  hp = math.floor(hp + 0.5)
  S.hpOffY = hp
  S.y = y0 + (hp0 - hp) * s
  ns.RestorePos(f, S, "x", "y"); PlaceHP()
 end)
end
function ns.EnergyDragStop()
 local S = EnergyTickSettings
 hpDrag:SetScript("OnUpdate", nil)
 f.vdrag = false
 if S.hpOffY == HP_DEFAULT_Y then S.hpOffY = nil end
end
hpf:SetHeight(14)
hpf:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1}})
hpf:SetBackdropColor(0, 0, 0, 1); hpf:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
ns.Round(hpf)
hpf:SetFrameLevel(baseLevel)
local HPBar = CreateFrame("StatusBar", nil, hpf)
HPBar:SetPoint("TOPLEFT", 1, -1); HPBar:SetPoint("BOTTOMRIGHT", -1, 1)
HPBar:SetStatusBarTexture(WHITE); HPBar:SetMinMaxValues(0, 1); HPBar:SetValue(1)
do local bg = HPBar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(HPBar); bg:SetColorTexture(1, 1, 1, 0.05)
 ns.RoundFill(HPBar, { bg }) end
local hpTop = CreateFrame("Frame", nil, hpf); hpTop:SetAllPoints(hpf); hpTop:SetFrameLevel(HPBar:GetFrameLevel() + 2)
local txtHP = hpTop:CreateFontString(nil, "OVERLAY"); ns.SetFont(txtHP, 10)
txtHP:SetPoint("RIGHT", hpf, "RIGHT", -4, 0); txtHP:SetTextColor(1, 1, 1)
local txtAggro = hpTop:CreateFontString(nil, "OVERLAY"); ns.SetFont(txtAggro, 10)
txtAggro:SetPoint("LEFT", hpf, "LEFT", 4, 0)

local function DockOn() return not UF_Settings or UF_Settings.dock ~= false end
ns.DockOn = DockOn
local function DockHeight() return (UF_Settings and UF_Settings.dockHeight) or 12 end

local hpCol, hpAcc = nil, 1
local function SetHPColor(c)
 if c ~= hpCol then hpCol = c; HPBar:SetStatusBarColor(c[1], c[2], c[3], 0.9) end
end
hpf:SetScript("OnUpdate", function(_, el)
 local test, now = ns.testMode, GetTime()
 local pct, ok, cur, max
 if test then pct, ok = 1 - ((now - ns.testStart) * 0.06) % 0.9, true
 else
  local c1, o1 = Read(UnitHealth, "player")
  local m1, o2 = Read(UnitHealthMax, "player")
  if o1 and o2 and m1 and m1 > 0 then pct, ok = c1 / m1, true else cur, max = c1, m1 end
 end
 local H = P.hp
 if ok then
  HPBar:SetMinMaxValues(0, 1); HPBar:SetValue(pct)
  SetHPColor((pct < 0.3 and H.low) or (pct < 0.5 and H.mid) or H.hi)
 else
  pcall(HPBar.SetMinMaxValues, HPBar, 0, max); pcall(HPBar.SetValue, HPBar, cur)
  SetHPColor(H.hi)
 end
 hpAcc = hpAcc + el
 if hpAcc < 0.1 then return end
 hpAcc = 0
 if UF_Settings and UF_Settings.showText == false then txtHP:SetText("")
 elseif ok then txtHP:SetText(math.floor(pct * 100 + 0.5).."%")
 elseif not (UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 and pcall(function()
   txtHP:SetFormattedText("%.0f%%", UnitHealthPercent("player", false, CurveConstants.ScaleTo100)) end)) then
  txtHP:SetText("")
 end
 -- «АГРО» — когда мобы бьют вас (звук играет фрейм игрока)
 local st, sok = Read(UnitThreatSituation, "player")
 if test then st, sok = 3, true end
 local show = sok and type(st) == "number" and st >= 2 and (not UF_Settings or UF_Settings.aggro ~= false)
  and not (ns.InfoAggro and ns.InfoAggro()) -- если «АГРО» показывает инфо-полоса — здесь не дублируем
 if show then local c = H.low; txtAggro:SetTextColor(c[1], c[2], c[3]); txtAggro:SetText("АГРО")
 else txtAggro:SetText("") end
end)

local function LayoutHP()
 local on = DockOn()
 hpf:SetShown(on)
 if on then
  local h = DockHeight()
  -- к полосе жизни привязана защищённая кнопка: размер/место — только вне боя
  if InCombatLockdown() then ns.mainPending = true else hpf:SetHeight(h + 2); PlaceHP() end
  local fs = math.max(8, math.min(12, h - 1))
  ns.SetFont(txtHP, fs); ns.SetFont(txtAggro, fs)
  hpCol = nil
 end
end

-- =============================================
-- КОМБО: 5 серых квадратиков под полосой (без цвета и эффектов)
--   пустой — тёмно-серый, набранный — светло-серый, 5/5 — почти белый.
-- Каждый квадрат — StatusBar с диапазоном (i-1, i): SetValue(cp) работает
-- и с секретным числом комбо, без сравнений.
-- =============================================
local CP_MAX, CP_H, CP_GAP = 5, 6, 2
local CP_ON = 0.55

-- Подложка как у полоски Slice and Dice: затемнённый фон + тонкая рамка
local cpRow = CreateFrame("Frame", nil, f, BACKDROP)
cpRow:SetHeight(CP_H + 2)
cpRow:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1} })
cpRow:SetBackdropColor(0, 0, 0, 0.82)
cpRow:SetBackdropBorderColor(0.12, 0.12, 0.12, 0.95)
ns.Round(cpRow)

local cpBoxes = {}
for i = 1, CP_MAX do
 local b = CreateFrame("StatusBar", nil, cpRow)
 b:SetStatusBarTexture(WHITE); b:SetMinMaxValues(i - 1, i); b:SetValue(0)
 b:SetStatusBarColor(CP_ON, CP_ON, CP_ON, 1)
 local bg = b:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(b); bg:SetColorTexture(1, 1, 1, 0.05) -- дорожка, как у всех
 b.mask = ns.RoundFill(b, { bg })
 -- серый фильтр поверх (энергия скрыта в бою — прозрачность считает игра)
 b.dim = b:CreateTexture(nil, "OVERLAY")
 b.dim:SetAllPoints(b:GetStatusBarTexture()); b.dim:SetColorTexture(1, 1, 1, 1)
 b.dim:AddMaskTexture(b.mask); b.dim:Hide()
 cpBoxes[i] = b
end

local function LayoutCP()
 local w = (f:GetWidth() - 2 - CP_GAP * (CP_MAX - 1)) / CP_MAX
 for i, b in ipairs(cpBoxes) do
  b:ClearAllPoints(); b:SetPoint("TOPLEFT", cpRow, "TOPLEFT", 1 + (i - 1) * (w + CP_GAP), -1); b:SetSize(w, CP_H)
 end
end

LayoutCP()

local cpShade -- текущий цвет (таблица из палитры); сброс — при смене стиля
local CP_WAIT = { 0.40, 0.40, 0.40 } -- энергии меньше порога: комбо серые вместе с энергией
local function SetCP(cp, readable)
 local c = (readable and cp >= CP_MAX) and P.cpFull or P.cpOn
 if ns.energyZone == "wait" then c = CP_WAIT end
 if c ~= cpShade then
  cpShade = c
  for _, b in ipairs(cpBoxes) do b:SetStatusBarColor(c[1], c[2], c[3], 1) end
 end
 for _, b in ipairs(cpBoxes) do
  if readable then b:SetValue(cp or 0) else pcall(b.SetValue, b, cp) end
 end
end


-- =============================================
-- КАСТ ЦЕЛИ (под Kick)
-- =============================================
local castS, castE = nil, nil
local function ReadCastTimes(fn)
 if not fn then return nil end
 local ok, _, _, _, s, e = pcall(fn, "target")
 if not ok then return nil end
 if issecret(s) or issecret(e) then return "secret" end
 if s and e and e > s then return s / 1000, e / 1000 end
 return nil
end
local function RefreshEnemyCast()
 castS, castE = nil, nil
 CastBar:Hide()
 local isChannel = false
 local s, e = ReadCastTimes(UnitCastingInfo)
 if not s then s, e = ReadCastTimes(UnitChannelInfo); isChannel = true end
 if s == "secret" then
  local durFn = isChannel and UnitChannelDuration or UnitCastingDuration
  if durFn and CastBar.SetTimerDuration then
   pcall(function()
    local dur = durFn("target")
    if dur then CastBar:SetTimerDuration(dur); CastBar:Show(); castS, castE = 0, math.huge end
   end)
  end
 elseif s then
  castS, castE = s, e
  CastBar:SetMinMaxValues(0, 1); CastBar:Show()
 end
end
local function TargetCasting(now) return castS ~= nil and now < castE end

-- Цель — кастер? (тогда держим энергию на Kick)
--   кастует прямо сейчас -> да; игрок -> по классу; моб -> есть ли у него мана.
--   Не удалось прочитать (секрет) -> считаем кастером: лучше лишний запас, чем пропущенный каст.
local CASTER_CLASS = { MAGE = true, PRIEST = true, WARLOCK = true, DRUID = true, SHAMAN = true,
                       PALADIN = true, EVOKER = true, MONK = true }
local function TargetIsCaster(now)
 if TargetCasting(now) then return true end
 if not UnitExists("target") then return false end
 if UnitIsPlayer("target") then
  local ok, _, cls = pcall(UnitClass, "target")
  if not ok or issecret(cls) or type(cls) ~= "string" then return true end
  return CASTER_CLASS[cls] or false
 end
 local mana, ok = Read(UnitPowerMax, "target", 0)
 if not ok then return true end
 return type(mana) == "number" and mana > 0
end

-- =============================================
-- УЧЁТ ЭНЕРГИИ ЗА БОЙ
-- =============================================
local stat = { spent = 0, wasted = 0 }
local prevE = nil
local function ResetStats() stat.spent, stat.wasted, stat.measured = 0, 0, false end

-- Итог боя: только то, что можно честно посчитать и при скрытых в бою значениях
local fight = { t0 = nil, snd = 0, sndSeen = false, kicks = 0, kickHit = 0, kickAt = 0 }
local fightHideAt
local function FightStart()
 fight.t0, fight.snd, fight.sndSeen, fight.kicks, fight.kickHit, fight.kickAt = GetTime(), 0, false, 0, 0, 0
end
local function FightEnd()
 local t0 = fight.t0
 fight.t0 = nil
 if not t0 or EnergyTickSettings.fightSummary == false or ns.testMode then return end
 local dur = GetTime() - t0
 if dur < 6 then return end -- короткие стычки не считаем
 local parts = { string.format("бой %d с", math.floor(dur + 0.5)) }
 if fight.sndSeen then parts[#parts + 1] = string.format("SnD %d%%", math.floor(fight.snd / dur * 100 + 0.5)) end
 if fight.kicks > 0 then parts[#parts + 1] = string.format("Kick %d/%d", fight.kickHit, fight.kicks) end
 if stat.measured and stat.wasted >= 5 then parts[#parts + 1] = string.format("кап -%d", math.floor(stat.wasted)) end
 txtFight:SetText(table.concat(parts, "  ·  "))
 fightHideAt = GetTime() + 5
end

-- Замер регена по факту (если API не отдал): прирост за окна без трат
local mAcc, mGain = 0, 0
local function MeasureRegen(dE, el, atCap)
 if atCap or dE < 0 then mAcc, mGain = 0, 0; return end
 mAcc, mGain = mAcc + el, mGain + dE
 if mAcc >= 1 then
  local r = mGain / mAcc
  if r > 2 and r < 60 then measuredRegen = measuredRegen and (measuredRegen * 0.7 + r * 0.3) or r end
  mAcc, mGain = 0, 0
 end
end

-- =============================================
-- СОБЫТИЯ
-- =============================================
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED",
  "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
 f:RegisterUnitEvent(ev, "target")
end
f:SetScript("OnEvent", function(self, ev, unit, ...)
 if ev == "PLAYER_REGEN_DISABLED" then ResetStats(); FightStart()
 elseif ev == "PLAYER_REGEN_ENABLED" then FightEnd()
 elseif ev == "PLAYER_TARGET_CHANGED" then RefreshEnemyCast()
 elseif ev == "UNIT_SPELLCAST_SUCCEEDED" then
  local spellID = select(2, ...)
  if not issecret(spellID) then LearnCast(spellID) end
  local okK, isKick = pcall(function() return spellID == KICK_ID end)
  if okK and isKick and fight.t0 then fight.kicks = fight.kicks + 1; fight.kickAt = GetTime() end
 else
  -- каст цели прерван сразу после нашего Kick — значит, сбили
  if ev == "UNIT_SPELLCAST_INTERRUPTED" and fight.t0 and GetTime() - fight.kickAt < 0.6 and fight.kickAt > 0 then
   fight.kickHit = fight.kickHit + 1; fight.kickAt = 0
  end
  RefreshEnemyCast()
 end
end)

-- =============================================
-- ОТРИСОВКА
-- =============================================
local zoneState, lastBeep = nil, 0
local lastBandKey

local function SetZone(state, inCombat, now)
 if state == zoneState then return end
 local prev = zoneState
 zoneState = state
 ns.energyZone = state -- для энергии над головой цели
 local c = (state == "cap" and C_CAP) or (state == "hold" and C_HOLD) or (state == "wait" and C_WAIT) or {0.5, 0.5, 0.5}
 if P.fill and P.fill[state] then c = P.fill[state] end
 EnergyBar:SetStatusBarColor(c[1], c[2], c[3], 0.85)
 Neon:SetShown(state == "cap")
 -- Сигнал: только при входе за границу, в бою, не чаще раза в 2с
 if state == "cap" and prev ~= "cap" and inCombat and not ns.testMode
   and EnergyTickSettings.sound and now - lastBeep > 2 then
  lastBeep = now
  ns.PlayTick(EnergyTickSettings.soundID, "Master")
 end
end

f:SetScript("OnUpdate", function(self, el)
 ns.UpdateLatency(el)
 local now = GetTime()
 local inCombat = UnitAffectingCombat("player")
 local e, eOK = Read(UnitPower, "player", ENERGY)
 local maxE, mOK = Read(UnitPowerMax, "player", ENERGY)
 local cp, cpOK = Read(UnitPower, "player", 4)

 local test = ns.testMode
 if test then
  local demoT = now - ns.testStart
  local p = (demoT % 8) / 8
  e, eOK, maxE, mOK = math.floor((p < 0.5 and p * 2 or (1 - p) * 2) * 100 + 0.5), true, 100, true
  cp, cpOK = math.floor(demoT / 1.5) % 6, true
 end
 local rawMax = maxE
 if mOK and maxE and maxE > 0 then ns.lastMaxE = maxE end
 if not (mOK and maxE and maxE > 0) then maxE, mOK = ns.lastMaxE or 100, false end

 f:SetAlpha((test or inCombat) and 1 or EnergyTickSettings.oocAlpha)

 local regen = RegenRate()
 local gcdLeft = GCDRemaining()
 local gen, kick = GenCost(), KickCost()
 -- порог «можно бить» = цена удара из совета (с запасом на Kick), иначе основной удар + запас
 gen = ns.adviceNeed or (gen + (ns.KickReserve and ns.KickReserve(now, test) or 0))
 local capLine = math.max(gen, maxE - regen * (gcdLen + ns.Latency()))
 ns.energyNeed, ns.energyMax = gen, maxE

 -- Маркеры и зоны (пересчёт только при изменении)
 local W = f:GetWidth() - 2
 local function X(v) return 1 + W * math.max(0, math.min(1, v / maxE)) end
 local bandKey = string.format("%.1f|%.1f|%.1f|%.0f|%.0f", gen, capLine, kick, W, maxE)
 if bandKey ~= lastBandKey then
  lastBandKey = bandKey
  local gx, cx = X(gen), X(capLine)
  HoldBand:ClearAllPoints()
  HoldBand:SetPoint("TOPLEFT", f, "TOPLEFT", gx, -1); HoldBand:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", cx, 1)
  CapBand:ClearAllPoints()
  CapBand:SetPoint("TOPLEFT", f, "TOPLEFT", cx, -1); CapBand:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
  PlaceMarker(GenMark, gx);  GenMark.text:SetText(math.floor(gen + 0.5))
  PlaceMarker(CapMark, cx);  CapMark.text:SetText(math.floor(capLine + 0.5))
  PlaceMarker(KickMark, X(kick))
 end

 -- Kick: пульсирует, когда цель кастует; рамка мигает, если энергии на Kick нет
 local casting = TargetCasting(now)
 if casting then
  KickMark.line:SetAlpha(1); KickMark.text:SetAlpha(1) -- без мигания: просто становится ярче
  if castE ~= math.huge then CastBar:SetValue(math.max(0, math.min(1, (castE - now) / (castE - castS)))) end
 else
  KickMark.line:SetAlpha(0.45); KickMark.text:SetAlpha(0.45)
  if castS and castE ~= math.huge then castS, castE = nil, nil; CastBar:Hide() end
 end

 -- ГКД
 GCDBar:SetValue(gcdLen > 0 and math.min(1, gcdLeft / gcdLen) or 0)

 -- Энергия
 if eOK then
  EnergyBar:SetMinMaxValues(0, maxE); EnergyBar:SetValue(e)
  txtEnergy:SetText(e)

  local state
  if e >= capLine then state = "cap" elseif e >= gen then state = "hold" else state = "wait" end
  SetZone(state, inCombat, now)
  if state == "cap" then
   Neon:SetBackdropBorderColor(C_CAP[1], C_CAP[2], C_CAP[3], 0.8) -- ровная рамка, без мигания
  end

  -- Через сколько можно бить основным ударом (энергия и ГКД)
  local need = math.max(0, (gen - e) / regen, gcdLeft)
  if need <= 0.05 then txtNext:SetTextColor(P.go[1], P.go[2], P.go[3]); txtNext:SetText("GO")
  else txtNext:SetTextColor(1, 1, 1); txtNext:SetText(string.format("%.1f", need)) end

  -- Учёт за бой
  if inCombat and not test then
   if e >= maxE then stat.wasted = stat.wasted + regen * el end
   if prevE and e < prevE then stat.spent = stat.spent + (prevE - e) end
  end
  if prevE and not test then MeasureRegen(e - prevE, el, e >= maxE) end
  prevE = e
 else
  pcall(EnergyBar.SetMinMaxValues, EnergyBar, 0, rawMax)
  pcall(EnergyBar.SetValue, EnergyBar, e)
  SafeText(txtEnergy, e, "")
  SetZone("secret", inCombat, now)
  txtNext:SetText("")
  -- энергия скрыта (бой): цвет зоны считает игра по доле энергии — серый / жёлтый / у капа
  local F = P.fill or {}
  local w, h, c = F.wait or C_WAIT, F.hold or C_HOLD, F.cap or C_CAP
  local col = ns.PowerCurveColor("player", ENERGY, "en", string.format("%.0f|%.0f|%.0f|%s", gen, capLine, maxE, tostring(P)),
   { { 0, { w[1], w[2], w[3], 0.85 } }, { gen / maxE, { h[1], h[2], h[3], 0.85 } }, { capLine / maxE, { c[1], c[2], c[3], 0.85 } } })
  ns.PaintCurve(EnergyBar, "SetStatusBarColor", col)
 end

 -- Тень: энергия через один ГКД (диапазон сдвинут на реген за ГКД; значение может быть скрытым)
 if EnergyTickSettings.energyShadow ~= false then
  local d = regen * gcdLen
  NextBar:SetMinMaxValues(-d, maxE - d)
  if not pcall(NextBar.SetValue, NextBar, e) then NextBar:SetValue(-d) end
  local F = P.fill or {}
  local h = F.hold or C_HOLD
  NextBar:SetStatusBarColor(h[1], h[2], h[3], 0.22)
  NextBar:Show()
 else
  NextBar:Hide()
 end

 -- Итог боя: аптайм SnD (по своей оценке — работает и со скрытыми баффами), плавное угасание строки
 if fight.t0 and inCombat and not test then
  local _, sexp = ns.GetSnD()
  if sexp and sexp > now then fight.snd = fight.snd + el; fight.sndSeen = true end
  if eOK then stat.measured = true end
 end
 if fightHideAt then
  local left = fightHideAt - now
  if left <= 0 then fightHideAt = nil; txtFight:SetAlpha(0)
  else txtFight:SetAlpha(math.min(1, left / 1.2)) end
 end

 -- Комбо-поинты
 SetCP(cp, cpOK)
 -- Комбо цветом совета — как над головой: синий SS / оранжевый SnD / красный Eviscerate; нет энергии — серые
 local akey = EnergyTickSettings.helpGlow ~= false and ns.advice
 local A = ns.ACT
 local zone = ns.energyZone
 local dimCol
 if akey and A then
  local hidden = akey == "cp"
  local base = A[hidden and "ss" or akey] or A.ss
  local dimNow = zone == "wait" or (zone ~= "secret" and ns.adviceDim)
  if dimNow then base = CP_WAIT end
  if test then base = A[akey] or base end
  for _, b in ipairs(cpBoxes) do b:SetStatusBarColor(base[1], base[2], base[3], 1) end
  cpShade = nil
  if hidden and not dimNow then
   local evisN = EnergyTickSettings.helpEvisCP or 5
   local st = { { 0, A.ss } }
   if ns.adviceSnD then st[#st + 1] = { 0.5 / 5, A.snd } end
   if EnergyTickSettings.helpEvis ~= false then st[#st + 1] = { (evisN - 0.5) / 5, A.evis } end
   local col = ns.PowerCurveColor("player", 4, "mainAdv", (ns.adviceSnD and "s" or "-")..evisN..tostring(EnergyTickSettings.helpEvis), st)
   if col then for _, b in ipairs(cpBoxes) do ns.PaintCurve(b, "SetStatusBarColor", col) end end
  end
  if zone == "secret" and ns.energyNeed then
   dimCol = ns.PowerCurveColor("player", ENERGY, "mainDim", string.format("%.0f|%.0f", gen, maxE),
    { { 0, { 0.42, 0.42, 0.42, 0.92 } }, { gen / maxE, { 0, 0, 0, 0 } } })
  end
 end
 for _, b in ipairs(cpBoxes) do
  if dimCol and ns.PaintCurve(b.dim, "SetVertexColor", dimCol) then b.dim:Show() else b.dim:Hide() end
 end
 -- совета нет, энергия скрыта: комбо серые/цветные тоже по кривой энергии (вместе с ней)
 if not (akey and A) and zone == "secret" then
  local on = P.cpOn
  local col = ns.PowerCurveColor("player", ENERGY, "cpEn", string.format("%.0f|%.0f|%s", gen, maxE, tostring(P)),
   { { 0, { CP_WAIT[1], CP_WAIT[2], CP_WAIT[3], 1 } }, { gen / maxE, { on[1], on[2], on[3], 1 } } })
  if col then
   for _, b in ipairs(cpBoxes) do ns.PaintCurve(b, "SetStatusBarColor", col) end
   cpShade = nil -- когда энергия снова читается — перекрасится обычным путём
  end
 end

 -- Статистика
 local total = stat.spent + stat.wasted
 if total > 0 then
  local eff = math.floor(stat.spent / total * 100 + 0.5)
  local c = (eff >= 97 and C_HOLD) or (eff >= 90 and C_WAIT) or C_CAP
  txtEff:SetTextColor(c[1], c[2], c[3]); txtEff:SetText(eff.."%")
  txtWaste:SetText(stat.wasted >= 1 and ("-"..math.floor(stat.wasted).." en") or "")
 else
  txtEff:SetText(""); txtWaste:SetText("")
 end
end)

-- =============================================
-- ПОЛОСКИ: комбо и свои полоски (кулдаун / бафф на мне / дебафф на цели).
-- Slice and Dice — просто одна из полосок (у разбойника добавлена сама),
-- у других классов там будет своё.
-- Стопка держится за ЖИЗНЬ (в едином блоке): если тянуть энергию, полоски стоят.
-- Ширина как у блока, двигаются только вверх-вниз.
-- Полоска показывает оставшееся время: пустая = баффа нет / кулдаун готов.
-- Опции бафф/дебафф-полоски:
--   alert — спал в бою: ровно горит оранжевым;
--   pulse — последние 3 с: своим цветом, мягко пульсирует.
-- =============================================
local STRIP_H, STRIP_GAP, DRAG_RANGE = 6, 2, 160
local MAX_STRIPS = 6
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local KINDS = { cd = "Кулдаун", buff = "Бафф на мне", debuff = "Дебафф на цели" }
ns.STRIP_KINDS, ns.MAX_STRIPS = KINDS, MAX_STRIPS

local ALERT_COL = { 0.88, 0.50, 0.16 }       -- «спал» (оранжевый)
local END_S = 3 -- последние секунды: полоска пульсирует своим цветом
local SND_IDS = { [5171] = true, [6774] = true } -- Slice and Dice (ранги)

local function NewStrip()
 local s = CreateFrame("Frame", nil, f, BACKDROP)
 s:SetHeight(STRIP_H)
 s:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1} })
 s:SetBackdropColor(0, 0, 0, 0.82)
 s:SetBackdropBorderColor(0.12, 0.12, 0.12, 0.95)
 s.bar = CreateFrame("StatusBar", nil, s)
 s.bar:SetPoint("TOPLEFT", 1, -1); s.bar:SetPoint("BOTTOMRIGHT", -1, 1)
 s.bar:SetStatusBarTexture(WHITE); s.bar:SetMinMaxValues(0, 1); s.bar:SetValue(0)
 local track = s.bar:CreateTexture(nil, "BACKGROUND"); track:SetAllPoints(s.bar); track:SetColorTexture(1, 1, 1, 0.05)
 ns.Round(s); s.barMask = ns.RoundFill(s.bar, { track })
 -- «спал»: ровная оранжевая заливка поверх
 s.alert = s.bar:CreateTexture(nil, "OVERLAY")
 s.alert:SetAllPoints(s.bar)
 s.alert:SetColorTexture(ALERT_COL[1], ALERT_COL[2], ALERT_COL[3], 0.85)
 s.alert:AddMaskTexture(s.barMask)
 s.alert:Hide()
 -- маленькая иконка слева, за краем полосы (ширина полосы не меняется)
 s.icon = s:CreateTexture(nil, "ARTWORK")
 s.icon:SetSize(STRIP_H + 2, STRIP_H + 2); s.icon:SetPoint("RIGHT", s, "LEFT", -2, 0)
 s.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
 s.mode = "none"
 return s
end

local strips = {}
for i = 1, MAX_STRIPS do strips[i] = NewStrip() end

local function BaseColor(def) return (def and def.snd and P.snd) or P.strip or P.snd end

local function SetAlertOn(st, on)
 if on == st.alertOn then return end
 st.alertOn = on
 st.alert:SetShown(on and true or false)
 if on then st:SetBackdropBorderColor(ALERT_COL[1], ALERT_COL[2], ALERT_COL[3], 1)
 else ns.ResetBorder(st) end
end
table.insert(ns.styleHooks, function() for _, st in ipairs(strips) do st.alertOn = nil end end)

-- Стопка крепится к жизни (единый блок) или к энергии (если блока нет).
-- Смещения y — относительно низа энергии на её обычном месте, поэтому старые позиции не прыгают.
local function StackBase()
 if DockOn() then return hpf, -(HP_DEFAULT_Y + f:GetHeight()) end
 return f, 0
end

local function Place(frame, y)
 local b, off = StackBase()
 frame:ClearAllPoints()
 frame:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, y + off); frame:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, y + off)
end

-- Всё, что стоит в стопке, по порядку
local function Entries()
 local S = EnergyTickSettings
 local list = {
  { frame = cpRow, h = CP_H + 2, shown = S.showCP ~= false,
    get = function() return S.cpY end, set = function(v) S.cpY = v end },
 }
 for i, def in ipairs(S.bars) do
  if strips[i] then
   list[#list + 1] = { frame = strips[i], h = strips[i]:GetHeight(), shown = not def.hidden, -- скрытая: настройки остаются
    get = function() return def.y end, set = function(v) def.y = v end }
  end
 end
 return list
end

-- Места в стопке для тех, кого не двигали (и для 'treatAuto', которого сейчас тянут)
local function Slots(treatAuto)
 local slots, cursor = {}, -2
 for _, e in ipairs(Entries()) do
  if e.shown and (e.get() == nil or e.frame == treatAuto) then
   slots[e.frame] = cursor
   cursor = cursor - e.h - STRIP_GAP
  end
 end
 return slots, cursor
end

local function LayoutStrips()
 local slots, cursor = Slots()
 for i = 1, MAX_STRIPS do strips[i]:Hide() end
 for _, e in ipairs(Entries()) do
  e.frame:SetShown(e.shown)
  if e.shown then Place(e.frame, e.get() or slots[e.frame]) end
 end
 -- статистика — под стопкой
 local b, off = StackBase()
 txtEff:ClearAllPoints();   txtEff:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, cursor - 2 + off)
 txtWaste:ClearAllPoints(); txtWaste:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, cursor - 2 + off)
 txtFight:ClearAllPoints(); txtFight:SetPoint("TOP", b, "BOTTOM", 0, cursor - 18 + off)
end

-- Перетаскивание только по вертикали; рядом со своим местом в стопке — прилипает
local function MakeVDrag(frame)
 frame:SetScript("OnMouseDown", function(self, button)
  if button ~= "LeftButton" or not ns.IsMovable("main") then return end
  local entry
  for _, e in ipairs(Entries()) do if e.frame == self then entry = e end end
  if not entry then return end
  local snap = Slots(self)[self] or -2
  local sc = self:GetEffectiveScale()
  local _, cy = GetCursorPosition()
  local fromY, startY = cy / sc, entry.get() or snap
  self.dragEntry, self.dragSnap = entry, snap
  self:SetScript("OnUpdate", function()
   local _, y = GetCursorPosition()
   local v = startY + (y / sc - fromY)
   v = math.max(-DRAG_RANGE, math.min(DRAG_RANGE, v))
   if math.abs(v - snap) < 4 then v = snap end
   v = math.floor(v + 0.5)
   entry.set(v); Place(self, v)
  end)
 end)
 frame:SetScript("OnMouseUp", function(self, button)
  if button == "RightButton" then ns.ToggleUnlock("main"); return end
  self:SetScript("OnUpdate", nil)
  local e = self.dragEntry
  if not e then return end
  if e.get() == self.dragSnap then e.set(nil) end -- вернули на место -> снова в стопке
  self.dragEntry = nil
  if ns.ApplyMain then ns.ApplyMain() end
 end)
end
MakeVDrag(cpRow)
for i = 1, MAX_STRIPS do MakeVDrag(strips[i]) end

-- ---------- данные ----------
local function SetTimer(bar, durObj)
 local dir = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime
 if dir and pcall(bar.SetTimerDuration, bar, durObj, nil, dir) then return true end
 return pcall(bar.SetTimerDuration, bar, durObj)
end

local function ReadAura(def)
 local unit = (def.kind == "buff") and "player" or "target"
 local filter = (def.kind == "buff") and "HELPFUL" or "HARMFUL|PLAYER"
 local ok, a = pcall(function()
  if def.kind == "buff" and C_UnitAuras.GetPlayerAuraBySpellID then
   local r = C_UnitAuras.GetPlayerAuraBySpellID(def.spell)
   if r then return r end
  end
  return C_UnitAuras.GetAuraDataBySpellName(unit, def.name, filter)
 end)
 if ok then return a, unit end
end

-- Перечитать состояние полоски (по событиям, не каждый кадр)
local function RefreshStrip(st, def)
 if def.snd then return end -- у SnD своя логика (с оценкой, когда бафф скрыт игрой)
 local mode, s, d = "none", nil, nil
 if def.kind == "cd" then
  local ok, info = pcall(C_Spell.GetSpellCooldown, def.spell)
  if ok and type(info) == "table" then
   local a, b = info.startTime, info.duration
   if not issecret(a) and not issecret(b) then
    if type(a) == "number" and type(b) == "number" and b > 1.6 then mode, s, d = "num", a, b end -- ГКД не считаем
   elseif C_Spell.GetSpellCooldownDuration then
    local ok2, dur = pcall(C_Spell.GetSpellCooldownDuration, def.spell)
    if ok2 and dur and SetTimer(st.bar, dur) then mode = "timer" end
   end
  end
 else
  local a, unit = ReadAura(def)
  if a then
   local dd, e = a.duration, a.expirationTime
   if not issecret(dd) and not issecret(e) then
    if type(dd) == "number" and dd > 0 and type(e) == "number" then mode, s, d = "num", e - dd, dd end
   elseif C_UnitAuras.GetUnitAuraDuration then
    local ok2, dur = pcall(C_UnitAuras.GetUnitAuraDuration, unit, a.auraInstanceID)
    if ok2 and dur and SetTimer(st.bar, dur) then mode = "timer" end
   end
  end
 end
 st.mode, st.s, st.d = mode, s, d
 if mode ~= "timer" then st.bar:SetMinMaxValues(0, 1) end
 if mode == "none" then st.bar:SetValue(0) end
end

local stripsDirty, stripsT = true, 0

-- Вид полоски: цвет (обычный / красный под конец), пульсация, «спал»
local function Paint(st, def, left, missing, est, now, fight)
 local aura = def.kind ~= "cd"
 local ending = aura and def.pulse and left and left <= END_S
 if ending ~= st.ending then
  st.ending = ending
  local c = BaseColor(def) -- под конец — тот же цвет, только пульс (красный = «добей», не путать)
  st.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
 end
 local a = 1
 if def.snd and not ending then a = 0.7 end -- SnD идёт — спокойнее; кончается — ярко и пульсирует
 if ending then a = 0.55 + 0.45 * (0.5 + 0.5 * math.cos(now * math.pi * 4)) -- 2 раза в секунду
 elseif not aura and left and left <= END_S then a = 0.5 end                 -- кулдаун почти готов: тускнеет
 st.bar:SetAlpha(a * (est and 0.6 or 1))
 -- «спал»: только в бою; дебафф — только когда есть враждебная цель
 local want = aura and def.alert and missing and fight
 if want and def.kind == "debuff" and not (UnitExists("target") and UnitCanAttack("player", "target")) then want = false end
 SetAlertOn(st, want and true or false)
end

local stripDriver = CreateFrame("Frame", nil, f)
stripDriver:SetScript("OnUpdate", function()
 local now = GetTime()
 local S = EnergyTickSettings
 local test = ns.testMode
 local fight = test or UnitAffectingCombat("player")

 if not test and (stripsDirty or now - stripsT > 1) then
  stripsDirty, stripsT = false, now
  for i, def in ipairs(S.bars) do if strips[i] then RefreshStrip(strips[i], def) end end
 end
 for i, def in ipairs(S.bars) do
  local st = strips[i]
  if st then
   local left, missing, est
   if test then
    -- демо: (6+3i)с действует, последняя четверть — «спал»
    local T = 6 + i * 3
    local p = ((now - ns.testStart) / T) % 1
    missing = p > 0.75
    if not missing then left = T * 0.75 * (1 - p / 0.75) end
    st.bar:SetMinMaxValues(0, 1); st.bar:SetValue(missing and 0 or (1 - p / 0.75))
   elseif def.snd then
    local duration, exp
    duration, exp, est = ns.GetSnD()
    st.bar:SetMinMaxValues(0, 1)
    if duration and exp and exp > now then
     left = exp - now
     st.bar:SetValue(math.min(1, left / (duration > 0 and duration or 30)))
    else
     st.bar:SetValue(0); missing = true
    end
   elseif st.mode == "num" then
    left = st.s + st.d - now
    if left <= 0 then st.mode = "none"; st.bar:SetValue(0); left = nil; missing = true
    else st.bar:SetValue(left / st.d) end
   elseif st.mode == "none" then
    missing = true
   end
   Paint(st, def, left, missing, est, now, fight)
  end
 end
end)

local stripEvents = CreateFrame("Frame")
stripEvents:RegisterUnitEvent("UNIT_AURA", "player", "target")
stripEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
stripEvents:RegisterEvent("SPELL_UPDATE_COOLDOWN")
stripEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
stripEvents:SetScript("OnEvent", function() stripsDirty = true end)

-- ---------- API для меню ----------
local function ResolveSpell(text)
 text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
 if text == "" then return nil end
 local id = tonumber(text)
 local ok, info = pcall(C_Spell.GetSpellInfo, id or text)
 if ok and type(info) == "table" and info.spellID then
  return info.spellID, info.name, info.iconID
 end
 if id then return id, tostring(id), nil end
end

local sndName
local function IsSnD(id, name)
 if SND_IDS[id] then return true end
 if not sndName then
  local ok, n = pcall(function() return C_Spell.GetSpellName(5171) end)
  sndName = (ok and type(n) == "string") and n or "Slice and Dice"
 end
 return name == sndName
end

-- Возвращает true или false + причину
function ns.AddStrip(text, kind)
 local S = EnergyTickSettings
 if #S.bars >= MAX_STRIPS then return false, "максимум "..MAX_STRIPS.." полосок" end
 if not KINDS[kind] then kind = "cd" end
 local id, name, icon = ResolveSpell(text)
 if not id then return false, "не нашёл способность: проверьте название или ID" end
 for _, d in ipairs(S.bars) do
  if d.spell == id and d.kind == kind then return false, name.." уже есть" end
 end
 local snd = kind == "buff" and IsSnD(id, name) or nil
 table.insert(S.bars, { spell = id, name = name, icon = icon, kind = kind, snd = snd,
  pulse = kind ~= "cd" or nil, alert = snd or nil })
 stripsDirty = true
 return true, name
end

function ns.RemoveStrip(i)
 local S = EnergyTickSettings
 if S.bars[i] then table.remove(S.bars, i); stripsDirty = true end
end

-- Поменять порядок: dir = -1 (выше) / 1 (ниже)
function ns.MoveStrip(i, dir)
 local bars = EnergyTickSettings.bars
 local j = i + dir
 if not (bars[i] and bars[j]) then return end
 bars[i], bars[j] = bars[j], bars[i]
 for _, st in ipairs(strips) do st.mode, st.alertOn, st.ending = "none", nil, nil end
 stripsDirty = true
end

-- Сменить тип полоски по кругу: откат -> бафф на мне -> дебафф на цели
local KIND_ORDER = { "cd", "buff", "debuff" }
function ns.CycleStripKind(i)
 local def = EnergyTickSettings.bars[i]
 if not def then return end
 for n, k in ipairs(KIND_ORDER) do
  if k == def.kind then def.kind = KIND_ORDER[n % #KIND_ORDER + 1]; break end
 end
 def.snd = (def.kind == "buff" and IsSnD(def.spell, def.name)) or nil
 if def.kind == "cd" then def.alert, def.pulse = nil, nil
 elseif def.pulse == nil then def.pulse = true end
 if strips[i] then strips[i].mode, strips[i].alertOn, strips[i].ending = "none", nil, nil end
 stripsDirty = true
end

-- Переключить опцию полоски ("alert" / "pulse" / "hidden")
function ns.ToggleStripOpt(i, key)
 local def = EnergyTickSettings.bars[i]
 if def then def[key] = not def[key] or nil end
end

-- Разбойник: Slice and Dice — полоска по умолчанию (один раз; старые настройки SnD переносим)
local function SeedDefaultStrips()
 local S = EnergyTickSettings
 if S.sndSeeded then return end
 S.sndSeeded = true
 local _, cls = UnitClass("player")
 if cls ~= "ROGUE" or S.showSnD == false then return end
 for _, d in ipairs(S.bars) do if d.snd or SND_IDS[d.spell] then d.snd = true; return end end
 if #S.bars >= MAX_STRIPS then return end
 local name, icon = "Slice and Dice", "Interface\\Icons\\Ability_Rogue_SliceDice"
 local ok, info = pcall(C_Spell.GetSpellInfo, 5171)
 if ok and type(info) == "table" then name, icon = info.name or name, info.iconID or icon end
 table.insert(S.bars, 1, { spell = 5171, name = name, icon = icon, kind = "buff", snd = true,
  alert = S.sndAlert ~= false or nil, pulse = S.sndEndPulse ~= false or nil, y = S.sndOffY })
 S.sndOffY = nil
end

local function ApplyStripLook()
 local S = EnergyTickSettings
 local showIcons = S.barIcons ~= false
 for i, st in ipairs(strips) do
  local def = S.bars[i]
  local c = BaseColor(def)
  st.bar:SetStatusBarColor(c[1], c[2], c[3], 1); st.ending = nil
  st.icon:SetTexture(def and def.icon or QUESTION)
  st.icon:SetShown(showIcons)
 end
 stripsDirty = true
end

-- =============================================
-- БОЕВАЯ ПАНЕЛЬ
-- Ячейки слева направо по приоритету: сначала «чтобы жить», потом ротация.
-- Принцип: спокойное значение — тусклое; ярко только то, на что надо
-- среагировать прямо сейчас. Цвета из палитры, без мигания.
-- =============================================
local SPELL = { kick = KICK_ID, evasion = 5277, vanish = 1856, feint = 1966 }

-- Порядок = приоритет. on — включена по умолчанию.
local HUD_CELLS = {
 { key = "hp",     head = "ЖИЗНЬ", on = true,  tip = "Ваше здоровье, %. Ярче при < 50%, красное при < 30%." },
 { key = "threat", head = "АГРО",  on = true,  tip = "Ваша угроза на цели, %. Жёлтое от 70%, красное от 90% — Финт/Исчезновение." },
 { key = "snd",    head = "SND",   on = true,  tip = "Сколько осталось Slice and Dice. В бою без него — оранжевое «НЕТ»." },
 { key = "cp",     head = "КОМБО", on = true,  tip = "Комбо-очки. 5 — зелёное: пора добивающий." },
 { key = "energy", head = "ЭНЕРГ", on = true,  tip = "Энергия цветом зоны: копим / рабочая / у капа — трать." },
 { key = "next",   head = "УДАР",  on = true,  tip = "Через сколько секунд хватит энергии и ГКД на основной удар." },
 { key = "kick",   head = "KICK",  on = true,  tip = "Готовность Kick. Бирюзовое, когда цель кастует и Kick готов." },
 { key = "evasion",head = "УКЛОН", on = true,  tip = "Ускользание. Загорается, когда здоровье < 35% и оно готово." },
 { key = "vanish", head = "ИСЧЕЗ", on = true,  tip = "Исчезновение. Загорается при угрозе ≥ 90% (или < 20% HP), если готово." },
 { key = "feint",  head = "ФИНТ",  on = false, tip = "Финт. Загорается при угрозе ≥ 80%, если готов." },
 { key = "target", head = "ЦЕЛЬ",  on = false, tip = "Здоровье цели, %. Ниже 20% — жёлтое: не тратьте очки на длинный SnD." },
}
ns.HUD_CELLS = HUD_CELLS

local HUD_W, HUD_PAD = 44, 6

local hud = CreateFrame("Frame", "ET_StatsHUD", UIParent, BACKDROP)
hud:SetSize(300, 40)
hud:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
hud:SetFrameStrata("MEDIUM")
hud:SetClampedToScreen(true)
hud:SetMovable(true); hud:EnableMouse(true); hud:RegisterForDrag("LeftButton")
hud:SetScript("OnDragStart", function(self) if ns.IsMovable("hud") then self:StartMoving() end end)
hud:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then ns.ToggleUnlock("hud") end end)
hud:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); ns.SavePos(self, EnergyTickSettings, "hudX", "hudY") end)
hud:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1} })
hud:SetBackdropColor(0, 0, 0, 0.75); hud:SetBackdropBorderColor(0.15, 0.15, 0.15, 1)
ns.Round(hud)

local cells = {}
for _, def in ipairs(HUD_CELLS) do
 local c = {}
 c.head = hud:CreateFontString(nil, "OVERLAY"); ns.SetFont(c.head, 9)
 c.head:SetText(def.head); c.head:SetTextColor(0.45, 0.45, 0.45)
 c.val = hud:CreateFontString(nil, "OVERLAY"); ns.SetFont(c.val, 15)
 c.head:SetWidth(HUD_W); c.val:SetWidth(HUD_W)
 c.head:SetJustifyH("CENTER"); c.val:SetJustifyH("CENTER")
 cells[def.key] = c
end

local function CellOn(key)
 local t = EnergyTickSettings.hudCells
 if t and t[key] ~= nil then return t[key] end
 for _, d in ipairs(HUD_CELLS) do if d.key == key then return d.on end end
end

local function LayoutHUD()
 local n = 0
 for _, def in ipairs(HUD_CELLS) do
  local c = cells[def.key]
  local on = CellOn(def.key) and true or false
  c.head:SetShown(on); c.val:SetShown(on)
  if on then
   local x = HUD_PAD + n * HUD_W
   c.head:ClearAllPoints(); c.head:SetPoint("TOPLEFT", hud, "TOPLEFT", x, -5)
   c.val:ClearAllPoints();  c.val:SetPoint("TOPLEFT", hud, "TOPLEFT", x, -18)
   n = n + 1
  end
 end
 hud:SetWidth(HUD_PAD * 2 + math.max(1, n) * HUD_W)
end

-- Цвета состояний (из палитры: в монохроме это яркость, в мягком — тон)
local function Tone(kind)
 local t = (kind == "kick" and P.kick) or P.hud[kind] or P.hud.text -- «сбить» — бирюзовый, как везде
 return t[1], t[2], t[3]
end
local function Put(key, text, kind)
 local v = cells[key].val
 v:SetTextColor(Tone(kind or "text")); v:SetText(text)
end
-- Секретное число: показать как есть, нейтральным цветом
local function PutSecret(key, v, fmt)
 local fs = cells[key].val
 fs:SetTextColor(Tone("dim"))
 if not pcall(fs.SetFormattedText, fs, fmt or "%.0f", v) then fs:SetText("?") end
end

-- Кулдаун: left (сек), known. GCD (≤ 1.6с) не считаем.
local spellName = {}
local function CDLeft(id, now)
 local name = spellName[id]
 if name == nil then
  local ok, n = pcall(C_Spell and C_Spell.GetSpellName or GetSpellInfo, id)
  name = (ok and n) or false; spellName[id] = name
 end
 local known = IsPlayerSpell and IsPlayerSpell(id)
 if not known and name then
  local ok, info = pcall(C_Spell and C_Spell.GetSpellInfo or GetSpellInfo, name)
  known = ok and info ~= nil
 end
 if not known then return nil, false end
 local s, d
 if C_Spell and C_Spell.GetSpellCooldown then
  local ok, info = pcall(C_Spell.GetSpellCooldown, name or id)
  if ok and type(info) == "table" then s, d = info.startTime, info.duration end
 elseif GetSpellCooldown then
  local ok, a, b = pcall(GetSpellCooldown, name or id)
  if ok then s, d = a, b end
 end
 if issecret(s) or issecret(d) then return nil, true end -- скрыто в бою
 if type(s) ~= "number" or type(d) ~= "number" or d <= 1.6 or s == 0 then return 0, true end
 return math.max(0, s + d - now), true
end

local function Pct(unit)
 local h, okh = Read(UnitHealth, unit)
 local m, okm = Read(UnitHealthMax, unit)
 if okh and okm and h and m and m > 0 then return h / m * 100, true end
 if UnitHealthPercent then
  local curve = CurveConstants and CurveConstants.ScaleTo100
  local ok, p = pcall(UnitHealthPercent, unit, false, curve)
  if ok and p ~= nil then return p, not issecret(p) end
 end
 return nil, false
end

-- Готов / секунды; hot — подсветить как «нажми сейчас»
local function PutCD(key, id, now, hot)
 local left, known = CDLeft(id, now)
 if not known then Put(key, "—", "dim")
 elseif left == nil then Put(key, "?", "dim")
 elseif left <= 0 then Put(key, "ок", hot and (key == "kick" and "kick" or "bad") or "ok")
 else Put(key, left >= 60 and (math.floor(left / 60 + 0.5).."м") or math.floor(left + 0.5), "dim") end
end

local hudAcc = 0
hud:SetScript("OnUpdate", function(self, elapsed)
 hudAcc = hudAcc + elapsed
 if hudAcc < 0.1 then return end
 hudAcc = 0
 local now, test = GetTime(), ns.testMode
 local inCombat = UnitAffectingCombat("player")
 self:SetAlpha((test or inCombat) and 1 or EnergyTickSettings.oocAlpha)

 -- Живучесть
 local hp, hpOK = Pct("player")
 if test then hp, hpOK = 100 - ((now - ns.testStart) * 6) % 90, true end
 if hpOK then
  Put("hp", math.floor(hp + 0.5), (hp < 30 and "bad") or (hp < 50 and "warn") or "dim")
 elseif hp ~= nil then PutSecret("hp", hp) else Put("hp", "-", "dim") end

 local thr, thrOK
 if test then thr, thrOK = ((now - ns.testStart) * 9) % 110, true
 elseif UnitExists("target") and UnitCanAttack("player", "target") then
  local ok, _, _, scaled = pcall(UnitDetailedThreatSituation, "player", "target")
  if ok and scaled ~= nil then thr, thrOK = scaled, not issecret(scaled) end
 end
 if thrOK then
  Put("threat", math.floor(thr + 0.5), (thr >= 90 and "bad") or (thr >= 70 and "warn") or "dim")
 elseif thr ~= nil then PutSecret("threat", thr) else Put("threat", "-", "dim") end

 -- Ротация
 local _, exp, est = ns.GetSnD()
 local t = exp and (exp - now) or 0
 if test then t = 12 - ((now - ns.testStart) % 15) end
 if t > 0 then
  Put("snd", (est and "~" or "")..math.floor(t), t <= 3 and "warn" or "ok")
 else
  Put("snd", "НЕТ", inCombat and "alert" or "dim")
 end

 local cp, cpOK = Read(UnitPower, "player", 4)
 if test then cp, cpOK = math.floor((now - ns.testStart) / 1.5) % 6, true end
 if cpOK then Put("cp", cp or 0, (cp or 0) >= 5 and "go" or ((cp or 0) > 0 and "text" or "dim"))
 else PutSecret("cp", cp) end

 local e, eOK = Read(UnitPower, "player", ENERGY)
 if test then e, eOK = math.floor(((now - ns.testStart) * 12) % 100), true end
 if eOK then
  Put("energy", e, (zoneState == "cap" and "bad") or (zoneState == "hold" and "ok") or "dim")
 else PutSecret("energy", e) end

 local nt = txtNext:GetText()
 if nt == "GO" then Put("next", "GO", "go")
 elseif nt and nt ~= "" then Put("next", nt, "dim")
 else Put("next", "-", "dim") end

 local casting = TargetCasting(now)
 PutCD("kick", SPELL.kick, now, casting)
 PutCD("evasion", SPELL.evasion, now, hpOK and hp < 35)
 PutCD("vanish", SPELL.vanish, now, (thrOK and thr >= 90) or (hpOK and hp < 20))
 PutCD("feint", SPELL.feint, now, thrOK and thr >= 80)

 if cells.target.val:IsShown() then
  if UnitExists("target") or test then
   local p, ok = Pct("target")
   if test then p, ok = 100 - ((now - ns.testStart) * 5) % 100, true end
   if ok then Put("target", math.floor(p + 0.5), p < 20 and "warn" or "dim")
   elseif p ~= nil then PutSecret("target", p) else Put("target", "-", "dim") end
  else Put("target", "-", "dim") end
 end
end)

-- =============================================
-- ПОМОЩНИК: две иконки-подсказки рядом с блоком (как Hekili, но проще)
--   УДАР:   нет комбо -> Sinister Strike; есть комбо и нет SnD -> Slice and Dice;
--           5 комбо и SnD висит -> Eviscerate; иначе -> Sinister Strike.
--           Не хватает энергии — иконка тусклая (ждите).
--   ЗАЩИТА: цель кастует и Kick готов -> Kick;
--           мало жизни -> Ускользание, если на КД -> Исчезновение, если и оно на КД -> зелье;
--           высокая угроза -> Финт.  Нечего советовать — ячейка пустая.
-- =============================================
local H_SPELL = { ss = 1752, snd = 5171, evis = 2098, kick = KICK_ID, evasion = 5277, vanish = 1856, feint = 1966,
                  ambush = 8676, cheap = 1833, garrote = 703 }
-- начало боя из невидимости: цвет совета — как у удара (набирает комбо)
local OPENER = { ambush = 60, cheap = 60, garrote = 50 } -- запасные цены
local H_TEXT = { ss = "Удар", snd = "Slice and Dice", evis = "Потрошение", kick = "Kick!", disarm = "Обезоружить",
                 evasion = "Ускользание", vanish = "Исчезновение", feint = "Финт", potion = "Зелье",
                 ambush = "Ambush (со спины)", cheap = "Cheap Shot", garrote = "Garrote (со спины)" }
-- Зелья лечения и камни здоровья (от сильных к слабым)
local POTIONS = { 33447, 22829, 32947, 13446, 3928, 1710, 929, 858, 118,
                  19013, 19012, 19011, 19010, 19009, 19008, 19007, 19006, 19005, 19004, 5512 }

local helper = CreateFrame("Frame", "ET_Helper", f)
helper:SetFrameLevel(baseLevel + 8)
helper:SetMovable(true); helper:SetClampedToScreen(true)

local function NewCell(name)
 local c = CreateFrame("Frame", nil, helper, BACKDROP)
 c:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = WHITE, edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1} })
 c:SetBackdropColor(0, 0, 0, 0.6); c:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
 ns.Round(c)
 c.tex = c:CreateTexture(nil, "ARTWORK")
 c.tex:SetPoint("TOPLEFT", 1, -1); c.tex:SetPoint("BOTTOMRIGHT", -1, 1)
 c.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
 ns.RoundTex(c, c, { c.tex }, -1)
 c.cap = c:CreateFontString(nil, "OVERLAY"); ns.SetFont(c.cap, 9)
 c.cap:SetPoint("TOP", c, "BOTTOM", 0, -2)
 -- ожидание энергии: тёмная шторка сверху уходит вверх по мере набора; в центре — секунды
 c.wait = c:CreateTexture(nil, "OVERLAY")
 c.wait:SetColorTexture(0, 0, 0, 0.65)
 c.wait:SetPoint("TOPLEFT", c.tex, "TOPLEFT"); c.wait:SetPoint("TOPRIGHT", c.tex, "TOPRIGHT")
 c.wait:Hide()
 ns.RoundTex(c, c, { c.wait }, -1)
 c.waitTxt = c:CreateFontString(nil, "OVERLAY"); ns.SetFont(c.waitTxt, 12)
 c.waitTxt:SetPoint("CENTER", c, "CENTER", 0, 0)
 c.key = nil
 return c
end
local cellAtk = NewCell("atk")
local cellDef = NewCell("def")

local iconCache = {}
local function SpellIcon(id)
 if iconCache[id] == nil then
  local ok, t = pcall(function()
   if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
   return GetSpellTexture(id)
  end)
  iconCache[id] = (ok and t) or false
 end
 return iconCache[id] or QUESTION
end

local function Known(id)
 if IsPlayerSpell and IsPlayerSpell(id) then return true end
 local _, known = CDLeft(id, GetTime())
 return known
end

-- Готово? Скрытый игрой кулдаун (left == nil) считаем готовым — лучше подсказать, чем промолчать
-- Запас на Kick: против кастеров, если Kick скоро доступен (откат <= 3 с)
-- Обезоружить: Dismantle (если есть), иначе Riposte (срабатывает после парирования)
local DISARM_IDS = { 51722, 14251 }
local DEFAULT_DISARM = { [51722] = 25, [14251] = 10 }
local disarmCost = {}
local function DisarmID(now)
 for _, id in ipairs(DISARM_IDS) do
  local _, known = CDLeft(id, now)
  if known then return id end
 end
end
local function DisarmCost(id)
 if disarmCost[id] == nil then disarmCost[id] = SpellEnergyCost(id) or DEFAULT_DISARM[id] or 25 end
 return disarmCost[id]
end

-- Запас энергии под «сбить»: против кастера — на Kick, против бойца — на обезоруживание
-- (только если приём скоро доступен: откат <= 3 с)
local function KickReserve(now, test)
 if EnergyTickSettings.helpReserve == false then return 0 end
 if test or TargetIsCaster(now) then
  local left, known = CDLeft(KICK_ID, now)
  if not known or (left and left > 3) then return 0 end
  return KickCost()
 end
 if EnergyTickSettings.helpDisarm == false or not UnitExists("target") then return 0 end
 local id = DisarmID(now)
 if not id then return 0 end
 local left = CDLeft(id, now)
 if left and left > 3 then return 0 end
 return DisarmCost(id)
end
ns.KickReserve = KickReserve
ns.KickLeft = function(now) return CDLeft(KICK_ID, now) end

local function Ready(id, now)
 local left, known = CDLeft(id, now)
 if not known then return false end
 return left == nil or left <= 0
end

-- Лучшее доступное зелье/камень: id, иконка (или nil)
local function BestPotion(now)
 for _, id in ipairs(POTIONS) do
  local okc, n = pcall(function()
   if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) end
   return GetItemCount(id)
  end)
  if okc and type(n) == "number" and not issecret(n) and n > 0 then
   local okd, s, d = pcall(function()
    if C_Container and C_Container.GetItemCooldown then return C_Container.GetItemCooldown(id) end
    return GetItemCooldown(id)
   end)
   local ready = not okd or issecret(s) or issecret(d) or type(s) ~= "number" or s == 0 or (s + d - now) <= 0
   if ready then
    local oki, icon = pcall(function()
     if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
     return GetItemIcon(id)
    end)
    return id, (oki and icon) or QUESTION
   end
  end
 end
end

-- Шторка ожидания: frac — сколько ещё не хватает (0…1), secs — секунд до удара
local function SetWait(c, frac, secs)
 if not frac or frac <= 0 then c.wait:Hide(); c.waitTxt:SetText(""); return end
 local h = c.tex:GetHeight()
 if not h or issecret(h) or h <= 0 then h = (EnergyTickSettings.helpSize or 36) - 2 end
 c.wait:SetHeight(math.max(1, h * math.min(1, frac))); c.wait:Show()
 c.waitTxt:SetText(secs and secs > 0.05 and string.format("%.1f", secs) or "")
end

local function Show(c, key, icon, dim, captions)
 if not key then
  c.key = nil; c.tex:SetTexture(nil); c.cap:SetText("")
  SetWait(c, nil)
  c:SetAlpha(c.placeholder and 0.6 or 0)
  return
 end
 if key ~= c.key then
  c.key = key
  c.tex:SetTexture(icon)
 end
 c:SetAlpha(1)
 c.tex:SetDesaturated(dim and true or false)
 c.tex:SetAlpha(dim and 0.45 or 1)
 c.cap:SetText(captions and (H_TEXT[key] or "") or "")
end

local function S_SndWanted(sndLeft)
 local S = EnergyTickSettings
 return S.helpSnD ~= false and sndLeft <= (S.helpSnDRefresh or 1.2) + ns.Latency() and Known(H_SPELL.snd) and true or false
end
-- Кинжал в правой руке? (Ambush — только с кинжалом)
local function MainHandDagger()
 local id = GetInventoryItemID and GetInventoryItemID("player", 16)
 if not id or issecret(id) then return false end
 local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
 if not fn then return false end
 local ok, _, _, _, _, _, classID, subID = pcall(fn, id)
 return ok and classID == 2 and subID == 15
end
-- В невидимости и цель враждебна, жива: чем начать. Стоите ли вы за спиной — игра не говорит,
-- поэтому подпись напоминает «со спины». Нет ни одного приёма — обычный совет.
local function OpenerAdvice()
 if EnergyTickSettings.helpOpener == false then return nil end
 local st, okS = Read(IsStealthed)
 if not okS or not st then return nil end
 if not (UnitExists("target") and UnitCanAttack("player", "target")) then return nil end
 local dead, okD = Read(UnitIsDeadOrGhost, "target")
 if okD and dead then return nil end
 if MainHandDagger() and Known(H_SPELL.ambush) then return "ambush" end
 if Known(H_SPELL.cheap) then return "cheap" end
 if Known(H_SPELL.garrote) then return "garrote" end
end

local function AttackAdvice(now, test)
 if not test then
  local op = OpenerAdvice()
  if op then return op end
 end
 local cp, cpOK = Read(UnitPower, "player", 4)
 local _, exp = ns.GetSnD()
 local sndLeft = exp and (exp - now) or 0
 if test then
  local p = math.floor((now - ns.testStart) / 2) % 3
  return ({ "ss", "snd", "evis" })[p + 1]
 end
 if not cpOK then
  -- комбо скрыты игрой: цвет совета выберет кривая по числу комбо (Nameplates.lua)
  ns.adviceSnD = S_SndWanted(sndLeft)
  return "cp"
 end
 local S = EnergyTickSettings
 cp = cp or 0
 if cp == 0 then return "ss" end
 if S_SndWanted(sndLeft) then return "snd" end
 if S.helpEvis ~= false and cp >= (S.helpEvisCP or 5) and Known(H_SPELL.evis) then return "evis" end
 return "ss"
end

-- Обезоружить сейчас? Цель — боец (не кастер), бьёт именно вас, приём готов (Riposte — только после парирования)
local function DisarmNow(now)
 if EnergyTickSettings.helpDisarm == false then return nil end
 if TargetIsCaster(now) then return nil end
 local onMe, okMe = Read(UnitIsUnit, "targettarget", "player")
 if not okMe or not onMe then return nil end
 local id = DisarmID(now)
 if not id or not Ready(id, now) then return nil end
 local okU, usable = pcall(function()
  if C_Spell and C_Spell.IsSpellUsable then return C_Spell.IsSpellUsable(id) end
  return IsUsableSpell(id)
 end)
 if okU and not issecret(usable) and usable == false then return nil end
 return id
end

-- смена стиля рамок перекрашивает рамку ячейки — вернуть бирюзовую при следующем обновлении
table.insert(ns.styleHooks, function() cellDef.hitCol = false end)

local function SaveAdvice(now, test)
 if test then
  local p = math.floor((now - ns.testStart) / 2) % 5
  local k = ({ "kick", "disarm", "evasion", "vanish", "potion" })[p + 1]
  if k == "disarm" then H_SPELL.disarm = DisarmID(now) or 51722 end
  return k
 end
 local S = EnergyTickSettings
 local hostile = UnitExists("target") and UnitCanAttack("player", "target")
 if S.helpKick ~= false and hostile and TargetCasting(now) and Ready(H_SPELL.kick, now) then return "kick" end
 local hp, hpOK = Pct("player")
 if hpOK and hp < (S.helpHP or 35) then
  if S.helpEvasion ~= false and Ready(H_SPELL.evasion, now) then return "evasion" end
  if S.helpVanish ~= false and Ready(H_SPELL.vanish, now) then return "vanish" end
  if S.helpPotion ~= false then
   local id, icon = BestPotion(now)
   if id then return "potion", icon end
  end
 end
 if hostile then
  local id = DisarmNow(now)
  if id then H_SPELL.disarm = id; return "disarm" end
 end
 if hostile then
  local ok, _, _, pct = pcall(UnitDetailedThreatSituation, "player", "target")
  if S.helpFeint ~= false and ok and type(pct) == "number" and not issecret(pct) and pct >= (S.helpThreat or 90)
    and Ready(H_SPELL.feint, now) then
   return "feint"
  end
 end
end

-- Совет «Удар» для ауры вокруг цели над головой (Nameplates.lua):
-- ns.advice = "ss" / "snd" / "evis" или nil, ns.adviceDim = не хватает энергии
ns.advice, ns.adviceDim = nil, false

local helpAcc = 0
helper:SetScript("OnUpdate", function(self, el)
 helpAcc = helpAcc + el
 if helpAcc < 0.1 then return end
 helpAcc = 0
 local S = EnergyTickSettings
 local now, test = GetTime(), ns.testMode
 local inCombat = UnitAffectingCombat("player")
 local hostile = UnitExists("target") and UnitCanAttack("player", "target")
 local active = test or inCombat or hostile
 local captions = S.helpCaptions ~= false

 -- удар (совет считается и без иконки — для ауры над головой)
 local wantAura = S.helpGlow ~= false
 if (S.helpAttack ~= false or wantAura) and active then
  local key = AttackAdvice(now, test)
  local id = H_SPELL[key]
  local dim, frac, secs = false, nil, nil
  local e, eOK = Read(UnitPower, "player", ENERGY)
  -- один порог на всё: «Цена удара» из меню (авто — по вашим ударам). Ниже — энергия серая,
  -- комбо цветом удара под серым фильтром («жди»); выше — жёлтая энергия и яркие комбо.
  local cost = GenCost()
  -- запас на Kick: бить, только если после удара Kick ещё можно нажать.
  -- Kick в долгом откате (> 3 с) — запас не держим, он всё равно недоступен.
  if OPENER[key] then cost = SpellEnergyCost(id) or OPENER[key] -- из невидимости: цена приёма, без запаса
  elseif cost then cost = cost + KickReserve(now, test) end
  ns.adviceNeed = cost
  if test then
   local p = ((now - ns.testStart) % 2) / 2
   if p < 0.6 then frac, secs = 1 - p / 0.6, (0.6 - p) * 2 end
  elseif eOK and cost and e < cost then
   dim = true -- не хватает энергии: ждите
   frac = (cost - e) / cost
   secs = (cost - e) / math.max(1, RegenRate())
  end
  if S.helpAttack ~= false then
   local shown = key == "cp" and "ss" or key -- иконка при скрытых комбо — основной удар
   Show(cellAtk, shown, SpellIcon(H_SPELL[shown]), dim, captions)
   if S.helpEnergy ~= false then SetWait(cellAtk, frac, secs) else SetWait(cellAtk, nil) end
  else
   Show(cellAtk, nil)
  end
  if wantAura then ns.advice, ns.adviceDim = (OPENER[key] and "ss" or key), dim else ns.advice = nil end
 else
  Show(cellAtk, nil)
  ns.advice, ns.adviceNeed = nil, nil
 end

 -- защита
 if S.helpSave ~= false and (active or test) then
  local key, icon = SaveAdvice(now, test)
  if key == "potion" then icon = icon or SpellIcon(H_SPELL.evasion)
  elseif key then icon = SpellIcon(H_SPELL[key]) end
  Show(cellDef, key, icon, false, captions)
  local hit = (key == "kick" or key == "disarm") and ns.ACT.kick
  if hit ~= cellDef.hitCol then
   cellDef.hitCol = hit
   if hit then cellDef:SetBackdropBorderColor(hit[1], hit[2], hit[3], 1) else cellDef:SetBackdropBorderColor(0.2, 0.2, 0.2, 1) end
  end
 else
  Show(cellDef, nil)
 end
end)

-- Раскладка: две квадратные ячейки рядом [защита][удар], слева от блока.
-- Тянется целиком (в режиме перемещения); позиция — смещение от центра энергии.
local function LayoutHelper()
 local S = EnergyTickSettings
 local sz = S.helpSize or 36
 local showA, showD = S.helpAttack ~= false, S.helpSave ~= false
 cellAtk:SetSize(sz, sz); cellDef:SetSize(sz, sz)
 cellAtk:SetShown(showA); cellDef:SetShown(showD)
 cellAtk:ClearAllPoints(); cellDef:ClearAllPoints()
 local n = (showA and 1 or 0) + (showD and 1 or 0)
 helper:SetSize(math.max(1, n * sz + (n - 1) * 4), sz)
 if showA then cellAtk:SetPoint("RIGHT", helper, "RIGHT", 0, 0) end
 if showD then
  if showA then cellDef:SetPoint("RIGHT", cellAtk, "LEFT", -4, 0) else cellDef:SetPoint("RIGHT", helper, "RIGHT", 0, 0) end
 end
 helper:SetShown(n > 0 or S.helpGlow ~= false) -- без иконок работает ради ауры над головой
 helper:ClearAllPoints()
 if S.helpX and S.helpY then
  helper:SetPoint("CENTER", f, "CENTER", S.helpX, S.helpY)
 else
  -- по умолчанию: слева от блока, по центру между жизнью и энергией
  local dy = DockOn() and (HPY() + DockHeight() + 2) / 2 or 0
  helper:SetPoint("RIGHT", f, "LEFT", -8, dy)
 end
end

helper:SetScript("OnMouseDown", function(self, button)
 if button ~= "LeftButton" or not ns.IsMovable("main") then return end
 self:StartMoving()
end)
helper:SetScript("OnMouseUp", function(self, button)
 if button == "RightButton" then ns.ToggleUnlock("main"); return end
 self:StopMovingOrSizing()
 local cx, cy = self:GetCenter()
 local fx, fy = f:GetCenter()
 if cx and fx then
  EnergyTickSettings.helpX, EnergyTickSettings.helpY = math.floor(cx - fx + 0.5), math.floor(cy - fy + 0.5)
 end
 LayoutHelper()
end)

-- В режиме перемещения пустые ячейки видны (чтобы было за что взяться)
local function HelperPlaceholders(on)
 cellAtk.placeholder, cellDef.placeholder = on, on
end

-- =============================================
-- КОМАНДЫ
-- =============================================
-- Голубая подсветка = можно двигать. Закреплённые панели ловят только ПКМ:
-- левый клик проходит сквозь них в мир (вне боя; в бою игра это менять не даёт).
local glows = {}
local function GlowFor(fr, pad) glows[fr] = glows[fr] or ns.MoveGlow(fr, pad); return glows[fr] end

local function SetMouse(fr, movable, selected)
 fr:EnableMouse(true)
 if movable then pcall(fr.SetPassThroughButtons, fr)
 else pcall(fr.SetPassThroughButtons, fr, "LeftButton") end
 GlowFor(fr, fr == f and 2 or 1):SetShown(selected)
end

local function ApplyLock()
 local main, h = ns.IsMovable("main"), ns.IsMovable("hud")
 local mSel, hSel = ns.IsSelected("main"), ns.IsSelected("hud")
 SetMouse(f, main, mSel); SetMouse(hud, h, hSel)
 -- комбо и полоски тянутся вверх-вниз вместе с «main»
 SetMouse(cpRow, main, mSel)
 for _, st in ipairs(strips) do SetMouse(st, main, mSel) end
 SetMouse(helper, main, mSel)
 HelperPlaceholders(main)
end
table.insert(ns.unlockHooks, function(key)
 if key == nil or key == "main" or key == "hud" then ApplyLock() end
end)

local function DefaultHUDPos() hud:ClearAllPoints(); hud:SetPoint("CENTER", UIParent, "CENTER", 0, -200) end

-- =============================================
-- API для окна настроек
-- =============================================
ns.GenCost, ns.KickCost = GenCost, KickCost

local function ApplyPalette(style)
 P = PALETTES[style] or PALETTES.mono
 C_WAIT, C_HOLD, C_CAP, C_KICK = P.wait, P.hold, P.cap, P.kick
 HoldBand:SetColorTexture(C_HOLD[1], C_HOLD[2], C_HOLD[3], P.holdBand)
 CapBand:SetColorTexture(C_CAP[1], C_CAP[2], C_CAP[3], P.capBand)
 for m, c in pairs({ [GenMark] = P.gen, [CapMark] = C_CAP, [KickMark] = C_KICK }) do
  m.line:SetColorTexture(c[1], c[2], c[3], 1); m.text:SetTextColor(c[1], c[2], c[3])
 end
 CastBar:SetStatusBarColor(C_KICK[1], C_KICK[2], C_KICK[3], 1)
 zoneState, cpShade = nil, nil -- заливка и комбо перекрасятся на следующем кадре
end

-- Применить размеры/вид/расположение/блокировку главной полосы и всего, что под ней
function ns.ApplyMain()
 local S = EnergyTickSettings
 ApplyPalette(S.barStyle)
 ApplyStripLook()
 -- размер полосы в бою не трогаем (к ней привязан защищённый фрейм игрока) — после боя
 if InCombatLockdown() then
  ns.mainPending = true
 else
  f:SetSize(S.width, S.height)
 end
 ResizeMarkers(); lastBandKey = nil
 -- метки и зоны на энергии — по желанию (по умолчанию чистая полоса)
 marks:SetShown(S.showMarks and true or false); zones:SetShown(S.showMarks and true or false)
 -- толщина комбо и полосок
 CP_H = math.max(2, S.cpHeight or 6)
 cpRow:SetHeight(CP_H + 2)
 -- толщина: SnD отдельно; свои полоски — по типу (кулдаун / бафф-дебафф)
 local function SetStripH(st, h) h = math.max(2, h or 6); st:SetHeight(h); st.icon:SetSize(h + 2, h + 2) end
 local base = S.stripHeight or 6
 for i, st in ipairs(strips) do
  local def = S.bars[i]
  local kindH = def and ((def.kind == "cd") and S.cdHeight or S.auraHeight)
  SetStripH(st, kindH or base)
 end
 LayoutHP()
 LayoutCP()
 LayoutStrips()
 hud:SetShown(S.showHUD ~= false)
 LayoutHUD()
 -- без цифр: прячем прозрачностью (текст остаётся — его читает HUD)
 local num = S.noNumbers and 0 or 1
 txtEnergy:SetAlpha(num); txtNext:SetAlpha(num); txtHP:SetAlpha(num)
 GenMark.text:SetAlpha(num); CapMark.text:SetAlpha(num)
 cellAtk.waitTxt:SetAlpha(num); cellDef.waitTxt:SetAlpha(num)
 txtEff:SetShown(S.showStats ~= false and not S.noNumbers); txtWaste:SetShown(S.showStats ~= false and not S.noNumbers)
 LayoutHelper()
 ApplyLock()
 ns.ApplyRound()
end

local afterCombat = CreateFrame("Frame")
afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
afterCombat:SetScript("OnEvent", function()
 if ns.mainPending then
  ns.mainPending = false
  ns.ApplyMain()
  if ns.ApplyUF then ns.ApplyUF() end
 end
end)

function ns.ResetMainPositions()
 if InCombatLockdown() then print("|cffffff00RogueTick:|r сброс позиций — после боя"); return end
 local S = EnergyTickSettings
 S.x, S.y = DEFAULTS.x, DEFAULTS.y
 S.hudX, S.hudY = nil, nil
 S.cpY, S.hpOffY = nil, nil
 S.helpX, S.helpY = nil, nil
 S.poisonX, S.poisonY = nil, nil -- панель ядов — снова посередине
 if ns.ApplyPoisons then ns.ApplyPoisons() end
 for _, d in ipairs(S.bars) do d.y = nil end
 ns.RestorePos(f, S, "x", "y")
 DefaultHUDPos()
 ns.ApplyMain()
end

-- Рекомендуемые толщины по важности (энергия главная, остальное тоньше) и порядок:
-- инфо/каст -> жизнь -> ЭНЕРГИЯ -> комбо -> полоски. Позиции стопки сбрасываются на свои места.
local function RecommendedTarget()
 if not UF_Settings then return end
 UF_Settings.tHpH, UF_Settings.tCastH, UF_Settings.tPowH = 16, 13, 4 -- жизнь цели, каст/инфо, её ресурс
 UF_Settings.auraSize = 18           -- дебаффы на цели — второстепенные
 UF_Settings.tInfoY, UF_Settings.tPowY = nil, nil -- каст вплотную над жизнью, ресурс под ней
end
function ns.RecommendedSizes(silent)
 local S = EnergyTickSettings
 RecommendedTarget()
 S.height = 16                       -- энергия
 S.cpHeight = 7                      -- комбо
 S.stripHeight, S.cdHeight, S.auraHeight = 5, 5, 5 -- откаты и баффы
 S.cpY, S.hpOffY = nil, nil          -- комбо сразу под энергией, жизнь вплотную сверху
 for _, d in ipairs(S.bars or {}) do d.y = nil end
 if UF_Settings then
  UF_Settings.dockHeight = 10        -- жизнь в блоке
  UF_Settings.castHeight = 9         -- инфо / свой каст
 end
 S.layoutV = 2
 if not silent then
  ns.ApplyMain()
  if ns.ApplyUF then ns.ApplyUF() end
 end
end

-- Для профилей и полного сброса
function ns.ApplyETDefaults()
 ApplyDefaults()
 local S = EnergyTickSettings
 if type(S.bars) ~= "table" then S.bars = {} end
 S.minimalV = S.minimalV or 1
end
ns.SeedDefaultStrips = SeedDefaultStrips
function ns.ReapplyMainPositions()
 if InCombatLockdown() then return end
 local S = EnergyTickSettings
 f:SetSize(S.width, S.height)
 if not ns.RestorePos(f, S, "x", "y") then f:ClearAllPoints(); f:SetPoint("CENTER", UIParent, "CENTER", 0, -150) end
 if not ns.RestorePos(hud, S, "hudX", "hudY") then DefaultHUDPos() end
end

-- =============================================
-- КОМАНДЫ
-- =============================================
local function PrintHelp()
 local g = EnergyTickSettings.genCost
 print("|cffffff00RogueTick|r /et config | lock | reset | test | sound | gen <цена|auto> | kick <цена|auto>")
 print("  |cff40cc59Зелёная зона|r — держите энергию здесь: хватает на удар, переполнения нет.")
 print("  |cfff23333Красная зона|r — не заходите: не успеете потратить до капа, энергия сгорит. Звук при входе.")
 print("  Белая метка — цена основного удара ("..math.floor(GenCost())..(type(g) == "number" and ", вручную" or ", авто")..").")
 print("  |cff4dd9ffK|r — резерв на Kick, мигает, когда цель кастует.")
 print("  Слева в полосе — через сколько секунд можно бить (GO = сейчас). Внизу — % эффективности и сгоревшая энергия за бой.")
 print("  Настройки: /et config или иконка у мини-карты.")
end

-- Диагностика в бою: /et debug — живая строка, что аддон читает (скрыто ли значение, зона, совет)
local dbg
local function YN(v) return v and "|cffd08060скрыто|r" or "|cff80c080видно|r" end
local function ToggleDebug()
 if not dbg then
  dbg = CreateFrame("Frame", nil, UIParent)
  dbg:SetSize(10, 10); dbg:SetPoint("TOP", UIParent, "TOP", 0, -120)
  dbg.t = dbg:CreateFontString(nil, "OVERLAY"); ns.SetFont(dbg.t, 12); dbg.t:SetPoint("TOP")
  dbg.acc = 0
  dbg:SetScript("OnUpdate", function(self, el)
   self.acc = self.acc + el; if self.acc < 0.2 then return end; self.acc = 0
   local e, eOK = Read(UnitPower, "player", ENERGY)
   local cp, cpOK = Read(UnitPower, "player", 4)
   self.t:SetText(string.format("энергия: %s %s | комбо: %s %s | зона: %s | порог: %s | совет: %s%s | серый: %s | кривые: %s",
    eOK and tostring(e) or "?", YN(not eOK), cpOK and tostring(cp) or "?", YN(not cpOK),
    tostring(ns.energyZone), tostring(ns.energyNeed and math.floor(ns.energyNeed + 0.5)),
    tostring(ns.advice), ns.advice == "cp" and (ns.adviceSnD and " (SnD)" or "") or "",
    tostring(ns.adviceDim), (C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitPowerPercent) and "есть" or "нет"))
  end)
  dbg:Show()
 else
  dbg:SetShown(not dbg:IsShown())
 end
 print("|cffffff00RogueTick:|r диагностика "..(dbg:IsShown() and "ВКЛ (/et debug — выключить)" or "ВЫКЛ"))
end

SLASH_ET1 = "/et"; SLASH_ET2 = "/roguetick"; SlashCmdList["ET"] = function(msg)
 msg = (msg or ""):lower()
 local cmd, arg = msg:match("^(%S*)%s*(.-)$")
 if cmd == "debug" or cmd == "dbg" then ToggleDebug(); return end
 if cmd == "config" or cmd == "menu" or cmd == "options" or cmd == "opt" then
  if ns.ToggleConfig then ns.ToggleConfig() end
 elseif cmd == "lock" then
  if ns.SetLocked then ns.SetLocked(not EnergyTickSettings.locked)
  else EnergyTickSettings.locked = not EnergyTickSettings.locked; ApplyLock() end
  print("ET: "..(EnergyTickSettings.locked and "Locked" or "Unlocked"))
 elseif cmd == "reset" then
  ns.ResetMainPositions()
  if ns.ResetUFPositions then ns.ResetUFPositions() end
 elseif cmd == "test" then
  ns.SetTest(not ns.testMode)
  print("ET test mode: "..(ns.testMode and "ON" or "OFF"))
 elseif cmd == "sound" then
  EnergyTickSettings.sound = not EnergyTickSettings.sound
  print("ET sound: "..(EnergyTickSettings.sound and "ON" or "OFF"))
 elseif cmd == "gen" or cmd == "kick" then
  local key = cmd == "gen" and "genCost" or "kickCost"
  local n = tonumber(arg)
  if n and n > 0 and n <= 200 then EnergyTickSettings[key] = n
  elseif arg == "auto" then EnergyTickSettings[key] = "auto"; if cmd == "gen" then wipe(castCount) end end
  print("ET "..cmd..": "..tostring(EnergyTickSettings[key]).." -> "..math.floor(cmd == "gen" and GenCost() or KickCost()))
 else PrintHelp() end
end

-- Сохранённые настройки грузятся ПОСЛЕ выполнения файлов -> применяем их тут
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
 if name ~= ADDON then return end
 ApplyDefaults()
 local S = EnergyTickSettings
 -- настройки от старой тиковой версии больше не нужны
 S.delay, S.lead, S.tickMode, S.showEnergyText = nil, nil, nil, nil
 -- минималистичный режим (v2.2): один раз выключаем HUD, дальше решает галочка в настройках
 if not S.minimalV then S.showHUD = false; S.minimalV = 1 end
 -- один раз: толщины по важности (дальше — ползунки или кнопка «Рекомендуемые толщины»)
 -- уже установленный аддон (не новый): порог 30 — Sinister Strike с талантом (авто видит базовую цену 40)
 if S.layoutV and not S.genFixV and S.genCost == "auto" then S.genCost = 30 end
 S.genFixV = 1
 -- полосы над головой: цвет — кто это (класс / враг / нейтрал), длина — жизнь
 if (S.npColorV or 0) < 2 then S.npColor = "reaction"; S.npColorV = 2 end
 if (S.layoutV or 0) < 1 then ns.RecommendedSizes(true)
 elseif S.layoutV < 2 then RecommendedTarget(); S.layoutV = 2 end
 if S.helpSnDRefresh == 1 then S.helpSnDRefresh = 1.2 end -- было «за 1 с»: с ГКД и пингом не успевали
 f:SetSize(S.width, S.height)
 if S.point then
  f:ClearAllPoints(); f:SetPoint(S.point, UIParent, S.relPoint or S.point, S.x, S.y)
  if ns.SavePos(f, S, "x", "y") then S.point, S.relPoint = nil, nil end
 else
  ns.RestorePos(f, S, "x", "y")
 end
 S.sndX, S.sndY = nil, nil -- старая свободная позиция SnD больше не нужна
 if type(S.bars) ~= "table" then S.bars = {} end
 SeedDefaultStrips() -- разбойник: SnD — полоска по умолчанию
 ns.RestorePos(hud, S, "hudX", "hudY")
 ns.ApplyMain()
 self:UnregisterEvent("ADDON_LOADED")
end)
