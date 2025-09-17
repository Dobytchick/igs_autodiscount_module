local function discountNotification(msg, extra)
    IGS.NotifyAll(msg)

    if extra then
        IGS.NotifyAll(extra)
    end

    timer.Create("IGS.Discount", 300, 0, function()
        IGS.NotifyAll(msg)
        if extra then
            IGS.NotifyAll(extra)
        end
    end)
end

local THIS_TIMESTAMP = os.date('*t', os.time())

local function CoFetch()
    local running = coroutine.running()
    local thisYear = os.date("%Y")

    http.Fetch(Format("https://date.nager.at/api/v3/PublicHolidays/%s/RU", thisYear), function(response)
        coroutine.resume(running, response, response:match('%[{"') ~= nil)
    end)

    return coroutine.yield()
end

local HolidaysTable = {}

coroutine.wrap(function()
    local response, isjson = CoFetch()
    if not isjson then
        ErrorNoHalt("IGS_AUTODISCOUNT_MODULE: ", response, " не является json\n")
        return
    end

    local holidays = util.JSONToTable(response)
    if not holidays then return end

    for k, v in pairs(holidays) do
        for _, field in ipairs({"countryCode", "fixed", "global", "type", "name", "launchYear"}) do
            v[field] = nil
        end

        if v.localName == "Новогодние Каникулы" and v.date ~= os.date("%Y-01-01") then -- Удаляем то, чего так много и не должно быть
            holidays[k] = nil
        end
    end

    HolidaysTable = holidays
end)()

local DISCOUNT_BLACKLISTED_CATS = {}

local function AddBlackCategory(sCat)
	DISCOUNT_BLACKLISTED_CATS[sCat] = true
end

local function AddCustomHoliday(sName, sDate)
    if HolidaysTable[#HolidaysTable - 1] and HolidaysTable[#HolidaysTable - 1].localName == sName then return false end
    HolidaysTable[#HolidaysTable + 1] = {localName = sName, date = sDate}
end

local BEFORE_START = 12                 -- За сколько дней до начала праздника будут начинаться скидки

local WEEK_DISCOUNT_ENABLE = true       -- Будут ли действовать скидки по выходным
local WEEK_DISCOUNT = 20                -- Сколько будет действовать процентов скидка на товары
local IGNORE_WEEKEND = true             -- Будут ли игнорироваться скидки по выходным, во время проведения праздничных

local HOLIDAY_DISCOUNT = 50             -- Сколько будет действовать процентов скидка на товары
local HOLIDAY_DURATION = 7              -- Сколько будут действовать скидки после начала праздника (в днях)

--AddBlackCategory('КатегорияНейм') -- Добавление категории, на которую не будут действовать скидки

-- Расскомментишь строку ниже этого коммента, если надо. Все пояснения даны.
--[[
    1 аргумент - имя праздника
    2 аргумент - дата начала праздника:
        ! Указывается в формате: Год / месяц / день
]]

--AddCustomHoliday('Новый год', os.date('%Y-12-31'))

local WEEK_TBL = {
    Saturday = 2,
    Sunday   = 1
}

local now = os.time()
local thisDay = tonumber(os.date("%d", now))
local thisYM  = tonumber(os.date("%Y%m", now))

local holiday, holiday_ds
for _, v in pairs(HolidaysTable) do
    local year, month, day = v.date:match("(%d+)%-(%d+)%-(%d+)")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)

    local startDay = math.max(day - BEFORE_START, 1)
    local endDay   = day + HOLIDAY_DURATION

    if (year * 100 + month) == thisYM and startDay <= thisDay and endDay >= thisDay then
        holiday    = v.localName
        holiday_ds = os.time({year = year, month = month, day = day})
        break
    end
end

-- выключаем скидки по выходным, в случае проведения скидок по праздникам
if IGNORE_WEEKEND and not (holiday and holiday_ds) then
    TMP_DATE, HOLIDAY_TIMESTAMP = nil, nil
else
    WEEK_DISCOUNT_ENABLE = nil
end

local function ApplyDiscount(perc)
    for _, v in ipairs(IGS.GetItems()) do
        if not DISCOUNT_BLACKLISTED_CATS[v.category] then
            local old_price = v.price
            local new_price = old_price * (1 - perc * 0.01)

            v:SetPrice(new_price)
            v:SetDiscountedFrom(old_price)
        end
    end
end

local weekDay = WEEK_TBL[os.date("%A", now)]
if weekDay and WEEK_DISCOUNT_ENABLE then
    ApplyDiscount(WEEK_DISCOUNT)

    if SERVER then
        local end_day   = os.date("%d", now + weekDay * 86400)
        local end_month = os.date(".%m", now)
        discountNotification(
            Format("В автодонате (F6) действуют скидки (%d%%) на все товары.", WEEK_DISCOUNT),
            Format("Скидки продлятся до: %s%s", end_day, end_month)
        )
    end
elseif holiday and holiday_ds then
    ApplyDiscount(HOLIDAY_DISCOUNT)

    if SERVER then
        discountNotification(
            Format('В автодонате (F6) действуют скидки %d%% на все товары в честь праздника "%s".', HOLIDAY_DISCOUNT, holiday),
            Format('Скидки продлятся до %s', os.date('%d.%m.%y', holiday_ds + HOLIDAY_DURATION * 86400))
        )
    end
end

