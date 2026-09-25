-- Время и даты определяются часовым поясом сервера.
local BEFORE_START = 12
local HOLIDAY_DURATION = 7
local HOLIDAY_DISCOUNT = 50
local WEEK_DISCOUNT_ENABLE = true
local WEEK_DISCOUNT = 20
local IGNORE_WEEKEND = true -- В выходные праздничная скидка имеет приоритет

assert(type(BEFORE_START) == "number" and BEFORE_START >= 0 and BEFORE_START <= 31 and BEFORE_START % 1 == 0)
assert(type(HOLIDAY_DURATION) == "number" and HOLIDAY_DURATION >= 0 and HOLIDAY_DURATION <= 31 and HOLIDAY_DURATION % 1 == 0)
assert(type(HOLIDAY_DISCOUNT) == "number" and HOLIDAY_DISCOUNT >= 0 and HOLIDAY_DISCOUNT <= 100)
assert(type(WEEK_DISCOUNT) == "number" and WEEK_DISCOUNT >= 0 and WEEK_DISCOUNT <= 100)

local blacklistedCategories = {}
local customHolidays = {}

local function AddBlackCategory(category)
    blacklistedCategories[category] = true
end

local function AddCustomHoliday(name, date)
    assert(type(name) == "string" and name ~= "", "Укажите название праздника")
    assert(type(date) == "string" and date:match("^%d%d%d%d%-%d%d%-%d%d$"), "Дата должна иметь формат ГГГГ-ММ-ДД")
    customHolidays[#customHolidays + 1] = {localName = name, date = date}
end

-- AddBlackCategory("Донат группы")
-- AddCustomHoliday("День сервера", "2026-12-31")

local state = IGS.AutoDiscountState or {originals = {}, remoteHolidays = {}}
IGS.AutoDiscountState = state
state.generation = (state.generation or 0) + 1
state.nextFetch = {}
state.requestId = {}
local generation = state.generation

local function calendarDate(date)
    if type(date) ~= "string" then return nil end
    local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not year then return nil end

    local timestamp = os.time({year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12})
    if not timestamp or os.date("%Y-%m-%d", timestamp) ~= date then return nil end
    return timestamp
end

local function dayAtNoon(parts, offset)
    return os.time({year = parts.year, month = parts.month, day = parts.day + (offset or 0), hour = 12})
end

local function activeHoliday(today)
    local chosen, chosenDate

    local function consider(holiday)
        if type(holiday) ~= "table" or type(holiday.localName) ~= "string" then return end
        local date = calendarDate(holiday.date)
        if not date then return end
        if (holiday.localName == "Новогодние каникулы" or holiday.localName == "Новогодние Каникулы")
            and holiday.date:sub(6) ~= "01-01" then return end

        local parts = os.date("*t", date)
        if today >= dayAtNoon(parts, -BEFORE_START) and today <= dayAtNoon(parts, HOLIDAY_DURATION)
            and (not chosenDate or date > chosenDate) then
            chosen, chosenDate = holiday, date
        end
    end

    for _, holiday in ipairs(customHolidays) do consider(holiday) end
    for _, holidays in pairs(state.remoteHolidays) do
        for _, holiday in ipairs(holidays) do consider(holiday) end
    end
    return chosen, chosenDate
end

local function selectedDiscount()
    local now = os.date("*t")
    local holiday, holidayDate = activeHoliday(dayAtNoon(now))
    local weekend = WEEK_DISCOUNT_ENABLE and (now.wday == 1 or now.wday == 7)

    if holiday and (IGNORE_WEEKEND or not weekend) then
        local endDate = dayAtNoon(os.date("*t", holidayDate), HOLIDAY_DURATION)
        return HOLIDAY_DISCOUNT, "holiday:" .. holiday.date .. ":" .. holiday.localName,
            holiday.localName, os.date("%d.%m.%Y", endDate)
    end
    if weekend then
        local endDate = dayAtNoon(now, now.wday == 7 and 1 or 0)
        return WEEK_DISCOUNT, "weekend", nil, os.date("%d.%m.%Y", endDate)
    end
end

local function applyDiscount(percent)
    for _, item in ipairs(IGS.GetItems()) do
        local original = state.originals[item]
        if percent and not blacklistedCategories[item.category] and not item.getprice
            and (original or (type(item.price) == "number" and item.price >= 0)) then
            if not original then
                original = {price = item.price, discountedFrom = item.discounted_from}
                state.originals[item] = original
            end
            item:SetPrice(original.price * (1 - percent / 100))
            item:SetDiscountedFrom(original.price)
        elseif original then
            item:SetPrice(original.price)
            item:SetDiscountedFrom(original.discountedFrom)
            state.originals[item] = nil
        end
    end
end

local function sendDiscount(player)
    net.Start("IGS.AutoDiscount.Sync")
    net.WriteBool(state.currentPercent ~= nil)
    if state.currentPercent then net.WriteFloat(state.currentPercent) end
    if player then net.Send(player) else net.Broadcast() end
end

local function refreshDiscount()
    if generation ~= state.generation then return end
    local percent, key, name, endDate = selectedDiscount()
    if next(hook.GetTable()["IGS.ItemPriceOverride"] or {})
        or (GAMEMODE and type(GAMEMODE["IGS.ItemPriceOverride"]) == "function") then
        percent, key = nil, nil
    end
    applyDiscount(percent)

    if state.currentPercent ~= percent then
        state.currentPercent = percent
        sendDiscount()
    end
    if state.activeKey == key then return end
    state.activeKey = key
    timer.Remove("IGS.AutoDiscount.Notification")
    if not key then return end

    local message
    if name then
        message = string.format('В автодонате (F6) скидка %d%% в честь праздника "%s" до %s.', percent, name, endDate)
    else
        message = string.format("В автодонате (F6) скидка %d%% на выходных до %s.", percent, endDate)
    end
    IGS.NotifyAll(message)
    timer.Create("IGS.AutoDiscount.Notification", 300, 0, function()
        if generation == state.generation then IGS.NotifyAll(message) end
    end)
end

local function fetchHolidays(year)
    state.nextFetch[year] = os.time() + 3600
    state.requestId[year] = (state.requestId[year] or 0) + 1
    local requestId = state.requestId[year]
    http.Fetch("https://date.nager.at/api/v3/PublicHolidays/" .. year .. "/RU", function(response, _, _, status)
        if generation ~= state.generation or requestId ~= state.requestId[year] then return end
        if status ~= 200 then
            ErrorNoHalt("IGS AutoDiscount: HTTP " .. tostring(status) .. " за " .. year .. "\n")
            return
        end
        local holidays = util.JSONToTable(response)
        if type(holidays) ~= "table" or (next(holidays) and not holidays[1]) then
            ErrorNoHalt("IGS AutoDiscount: неверный ответ Nager.Date за " .. year .. "\n")
            return
        end
        state.remoteHolidays[year] = holidays
        state.nextFetch[year] = os.time() + 86400
        refreshDiscount()
    end, function(errorMessage)
        if generation == state.generation and requestId == state.requestId[year] then
            ErrorNoHalt("IGS AutoDiscount: не удалось загрузить праздники за " .. year .. ": " .. tostring(errorMessage) .. "\n")
        end
    end)
end

local function refreshCalendar()
    if generation ~= state.generation then return end
    local now = os.date("*t")
    local years = {now.year}
    if now.month == 1 then years[#years + 1] = now.year - 1 end
    if now.month == 12 then years[#years + 1] = now.year + 1 end
    for _, year in ipairs(years) do
        if os.time() >= (state.nextFetch[year] or 0) then fetchHolidays(year) end
    end
    refreshDiscount()
end

if SERVER then
    util.AddNetworkString("IGS.AutoDiscount.Sync")
    util.AddNetworkString("IGS.AutoDiscount.Request")
    local lastRequest = setmetatable({}, {__mode = "k"})
    net.Receive("IGS.AutoDiscount.Request", function(_, player)
        if generation ~= state.generation or not IsValid(player) then return end
        local now = os.time()
        if lastRequest[player] and now - lastRequest[player] < 2 then return end
        lastRequest[player] = now
        sendDiscount(player)
    end)

    timer.Remove("IGS.AutoDiscount.Refresh")
    timer.Remove("IGS.AutoDiscount.Notification")
    state.activeKey = nil
    state.currentPercent = nil
    refreshCalendar()
    timer.Create("IGS.AutoDiscount.Refresh", 60, 0, refreshCalendar)
    hook.Add("IGS.Initialized", "IGS.AutoDiscount.Initialized", refreshDiscount)
    hook.Add("PlayerInitialSpawn", "IGS.AutoDiscount.Wake", refreshCalendar)
else
    local ready = false
    local synced = false
    local function requestDiscount()
        if not ready or synced then return end
        if net.Start("IGS.AutoDiscount.Request") then net.SendToServer() end
    end

    local function startRequests()
        if synced then return end
        ready = true
        requestDiscount()
        timer.Create("IGS.AutoDiscount.Request", 5, 0, requestDiscount)
    end

    timer.Remove("IGS.AutoDiscount.Request")
    net.Receive("IGS.AutoDiscount.Sync", function()
        if generation ~= state.generation then return end
        synced = true
        state.clientPercent = net.ReadBool() and net.ReadFloat() or nil
        applyDiscount(state.clientPercent)
        timer.Remove("IGS.AutoDiscount.Request")
    end)
    hook.Add("IGS.Initialized", "IGS.AutoDiscount.Initialized", function()
        applyDiscount(state.clientPercent)
        if IsValid(LocalPlayer()) then startRequests() end
    end)
    hook.Add("InitPostEntity", "IGS.AutoDiscount.Ready", startRequests)
    if IsValid(LocalPlayer()) then startRequests() end
end
