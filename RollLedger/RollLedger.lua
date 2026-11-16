local addon = CreateFrame("Frame")
local plates, retry = {}, {}
local db, pending, timer
local nextSend = 0
local pump
local function wake(delay)
    if timer then timer:Cancel() end
    timer = C_Timer.NewTimer(math.max(0.05, delay), function() timer = nil; pump() end)
end
local function valid(unit)
    return UnitExists(unit) and UnitIsPlayer(unit) and not UnitIsUnit(unit, "player") and UnitIsFriend("player", unit)
end
local function style(p)
    p.text:ClearAllPoints()
    p.text:SetPoint("LEFT", p.frame, "RIGHT", db.x, db.y)
    p.text:SetFont(STANDARD_TEXT_FONT, db.font, "OUTLINE")
end
local function draw(p)
    p.text:Hide()
    if not valid(p.unit) or UnitGUID(p.unit) ~= p.guid or not p.frame:IsShown() then return end
    local c = db.cache[p.guid]
    if not c or time() - c.at >= 86400 or time() < c.at then return end
    local value = c.need / c.runs
    p.text:SetText(string.format("%.1f", value))
    if value < 3 then p.text:SetTextColor(0, 1, 0)
    elseif value <= 5 then p.text:SetTextColor(1, 1, 0)
    else p.text:SetTextColor(1, 0, 0) end
    p.text:Show()
end
local function finish(failed)
    if pending then
        if failed then retry[pending.guid] = GetTime() + 60 end
        pending = nil
    end
end
pump = function()
    if not db then return end
    local now, delay = GetTime(), nil
    if pending then
        if now >= pending.deadline then finish(true)
        else wake(pending.deadline - now); return end
    end
    for unit, p in pairs(plates) do
        draw(p)
        if valid(unit) and UnitGUID(unit) == p.guid and p.frame:IsShown() then
            local c = db.cache[p.guid]
            local remaining = c and (86400 - (time() - c.at)) or 0
            if c and time() < c.at then remaining = 0 end
            if remaining > 0 then
                delay = math.min(delay or remaining, remaining)
            elseif not (AchievementFrame and AchievementFrame:IsShown()) then
                local wait = math.max(nextSend, retry[p.guid] or 0) - now
                if wait <= 0 then
                    pending = { guid = p.guid, unit = unit, deadline = now + 5 }
                    nextSend = now + 3
                    ClearAchievementComparisonUnit()
                    local ok, result = pcall(SetAchievementComparisonUnit, unit)
                    if not ok or result == false then finish(true); wake(3)
                    else wake(5) end
                    return
                end
                delay = math.min(delay or wait, wait)
            end
        end
    end
    if delay then wake(delay) end
end
local function number(value)
    if type(value) == "string" then value = value:gsub(",", "") end
    local n = tonumber(value)
    if n and n >= 0 and n < math.huge then return n end
end
local function attachAchievement()
    if AchievementFrame and not addon.achievementHooked then
        addon.achievementHooked = true
        AchievementFrame:HookScript("OnShow", function() finish(true); wake(0.05) end)
        AchievementFrame:HookScript("OnHide", function() wake(0.05) end)
    end
end
addon:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" then
        if arg == "RollLedger" then
            RollLedgerDB = RollLedgerDB or {}
            db = RollLedgerDB
            db.cache = db.cache or {}
            db.font, db.x, db.y = db.font or 12, db.x or 6, db.y or 0
            for guid, c in pairs(db.cache) do
                if type(c) ~= "table" or not number(c.need) or not number(c.runs) or c.runs <= 0 or type(c.at) ~= "number" or time() - c.at >= 86400 then db.cache[guid] = nil end
            end
        end
        attachAchievement()
    elseif event == "NAME_PLATE_UNIT_ADDED" and db then
        if not valid(arg) then return end
        if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
        local frame = C_NamePlate.GetNamePlateForUnit(arg)
        if not frame then return end
        local text = frame.RollLedgerText or frame:CreateFontString(nil, "OVERLAY")
        frame.RollLedgerText = text
        local p = { unit = arg, guid = UnitGUID(arg), frame = frame, text = text }
        plates[arg] = p
        style(p); draw(p); wake(0.05)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if plates[arg] then plates[arg].text:Hide(); plates[arg] = nil end
        wake(0.05)
    elseif event == "INSPECT_ACHIEVEMENT_READY" then
        if not pending or arg ~= pending.guid or UnitGUID(pending.unit) ~= pending.guid then return end
        local need, runs = number(GetComparisonStatistic(1044)), number(GetComparisonStatistic(932))
        if need and runs and runs > 0 then
            db.cache[pending.guid] = { need = need, runs = runs, at = time() }
            retry[pending.guid] = nil
            finish(false)
        else finish(true) end
        wake(0.05)
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then
            print("RollLedger：当前客户端缺少姓名板接口，无法自动查询，请反馈客户端版本。")
        end
        wake(0.05)
    elseif event == "UNIT_FACTION" then wake(0.05) end
end)
for _, event in ipairs({"ADDON_LOADED", "PLAYER_ENTERING_WORLD", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "INSPECT_ACHIEVEMENT_READY", "UNIT_FACTION"}) do addon:RegisterEvent(event) end
SLASH_ROLLLEDGER1 = "/rollledger"
SlashCmdList.ROLLLEDGER = function(message)
    if not db then return end
    local command, a, b = message:match("^(%S*)%s*(%S*)%s*(%S*)%s*$")
    a, b = tonumber(a), tonumber(b)
    if command == "font" and a and a >= 8 and a <= 32 then db.font = a
    elseif command == "offset" and a and b and math.abs(a) <= 100 and math.abs(b) <= 100 then db.x, db.y = a, b
    elseif command == "reset" then db.font, db.x, db.y = 12, 6, 0
    else print("RollLedger：/rollledger font 12（8–32）；offset 6 0（各−100至100）；reset") return end
    for _, p in pairs(plates) do style(p); draw(p) end
end
