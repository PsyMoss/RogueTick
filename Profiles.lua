-- =============================================
-- Профили настроек.
--   Профиль = снимок всех настроек (полосы, цель, полоски, вид, позиции).
--   Хранятся на весь аккаунт (RogueTickDB) — доступны любому персонажу.
--   Персонажу можно назначить профиль (RogueTickChar): он загружается при входе
--   и сохраняется при выходе — так у каждого персонажа свои настройки.
--   Экспорт/импорт — строкой: скопировать на другом аккаунте или компьютере.
-- =============================================
local ADDON, ns = ...

RogueTickDB = RogueTickDB or {}
RogueTickChar = RogueTickChar or {}

local function DB()
    RogueTickDB.profiles = RogueTickDB.profiles or {}
    return RogueTickDB.profiles
end

local function DeepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = DeepCopy(x) end
    return t
end

-- Скопировать содержимое src в dst, сохранив саму таблицу dst (на неё ссылается аддон)
local function CopyInto(dst, src)
    wipe(dst)
    for k, v in pairs(src) do dst[k] = DeepCopy(v) end
end

local function Snapshot()
    return { v = 1, et = DeepCopy(EnergyTickSettings), uf = DeepCopy(UF_Settings) }
end

-- Применить снимок к текущим настройкам и перерисовать всё
local function ApplySnapshot(snap)
    if InCombatLockdown() then return false, "в бою нельзя — попробуйте после боя" end
    if type(snap) ~= "table" or type(snap.et) ~= "table" or type(snap.uf) ~= "table" then
        return false, "профиль повреждён"
    end
    CopyInto(EnergyTickSettings, snap.et)
    CopyInto(UF_Settings, snap.uf)
    ns.ReapplyAll()
    return true
end

-- Заполнить пропуски значениями по умолчанию и применить всё (размеры, вид, позиции, шрифты)
function ns.ReapplyAll()
    if ns.ApplyETDefaults then ns.ApplyETDefaults() end
    if ns.ApplyUFDefaults then ns.ApplyUFDefaults() end
    if ns.SeedDefaultStrips then ns.SeedDefaultStrips() end
    if ns.ReapplyMainPositions then ns.ReapplyMainPositions() end
    if ns.ApplyMain then ns.ApplyMain() end
    if ns.ApplyUF then ns.ApplyUF() end
    if ns.ApplyMinimap then ns.ApplyMinimap() end
    ns.ApplyFonts()
    if ns.ApplyNameplates then ns.ApplyNameplates() end
    if ns.ApplyCombatText then ns.ApplyCombatText() end
    if ns.RefreshConfig then ns.RefreshConfig() end
end

-- ---------- профили ----------
function ns.ProfileList()
    local list = {}
    for name in pairs(DB()) do list[#list + 1] = name end
    table.sort(list)
    return list
end

local function CleanName(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return name ~= "" and name or nil
end

function ns.SaveProfile(name)
    name = CleanName(name)
    if not name then return false, "введите название профиля" end
    DB()[name] = Snapshot()
    return true, name
end

function ns.LoadProfile(name)
    local snap = DB()[name]
    if not snap then return false, "нет такого профиля" end
    local ok, err = ApplySnapshot(snap)
    if not ok then return false, err end
    return true, name
end

function ns.DeleteProfile(name)
    if not DB()[name] then return false end
    DB()[name] = nil
    if RogueTickChar.profile == name then RogueTickChar.profile = nil end
    return true
end

-- Профиль этого персонажа (загружается при входе, сохраняется при выходе)
function ns.CharProfile() return RogueTickChar.profile end
function ns.SetCharProfile(name)
    if name and not DB()[name] then return end
    RogueTickChar.profile = name
end

-- ---------- сброс ----------
function ns.ResetAll()
    if InCombatLockdown() then return false, "в бою нельзя — попробуйте после боя" end
    wipe(EnergyTickSettings); wipe(UF_Settings)
    ns.ReapplyAll()
    return true
end

-- ---------- экспорт / импорт ----------
-- Свой простой формат (без выполнения кода): n<число>; s<длина>:<текст>; t/f; {…}
local function Ser(v, out)
    local tv = type(v)
    if tv == "number" then out[#out + 1] = "n"..tostring(v)..";"
    elseif tv == "string" then out[#out + 1] = "s"..#v..":"..v
    elseif tv == "boolean" then out[#out + 1] = v and "t" or "f"
    elseif tv == "table" then
        out[#out + 1] = "{"
        for k, x in pairs(v) do
            local tk, tx = type(k), type(x)
            if (tk == "string" or tk == "number") and (tx ~= "function" and tx ~= "userdata") then
                Ser(k, out); Ser(x, out)
            end
        end
        out[#out + 1] = "}"
    end
end

local function Deser(s, i)
    local c = s:sub(i, i)
    if c == "n" then
        local j = s:find(";", i, true); if not j then error("bad") end
        local n = tonumber(s:sub(i + 1, j - 1)); if not n then error("bad") end
        return n, j + 1
    elseif c == "s" then
        local j = s:find(":", i, true); if not j then error("bad") end
        local len = tonumber(s:sub(i + 1, j - 1)); if not len then error("bad") end
        return s:sub(j + 1, j + len), j + len + 1
    elseif c == "t" then return true, i + 1
    elseif c == "f" then return false, i + 1
    elseif c == "{" then
        local t = {}
        i = i + 1
        while s:sub(i, i) ~= "}" do
            if i > #s then error("bad") end
            local k, v
            k, i = Deser(s, i)
            v, i = Deser(s, i)
            t[k] = v
        end
        return t, i + 1
    end
    error("bad")
end

-- В строке только 0-9a-f — её можно спокойно копировать и вставлять в чат/файл
local function ToHex(s) return (s:gsub(".", function(ch) return string.format("%02x", ch:byte()) end)) end
local function FromHex(h)
    if #h % 2 ~= 0 or h:find("[^0-9a-fA-F]") then return nil end
    return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

function ns.ExportString()
    local out = {}
    Ser(Snapshot(), out)
    return "RT1:"..ToHex(table.concat(out))
end

function ns.ImportString(str)
    str = (str or ""):gsub("%s+", "")
    local body = str:match("^RT1:(.+)$")
    if not body then return false, "это не строка профиля RogueTick (должна начинаться с RT1:)" end
    local raw = FromHex(body)
    if not raw then return false, "строка повреждена" end
    local ok, snap = pcall(function() return (Deser(raw, 1)) end)
    if not ok or type(snap) ~= "table" then return false, "строка повреждена" end
    return ApplySnapshot(snap)
end

-- ---------- вход / выход персонажа ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function(_, e)
    local name = RogueTickChar.profile
    if not name then return end
    if e == "PLAYER_LOGIN" then
        if DB()[name] then ns.LoadProfile(name) else RogueTickChar.profile = nil end
    elseif e == "PLAYER_LOGOUT" then
        if DB()[name] then DB()[name] = Snapshot() end -- изменения персонажа — в его профиль
    end
end)
