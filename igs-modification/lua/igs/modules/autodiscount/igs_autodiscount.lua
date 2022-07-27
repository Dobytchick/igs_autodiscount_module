local function disountNotification(...)
    local unpack_arguments = {...}
	
    IGS.NotifyAll(unpack_arguments[1])
	
    if unpack_arguments[2] then
        IGS.NotifyAll(unpack_arguments[2])
    end
	
	timer.Create("Discount", 300, 0, function()
        IGS.NotifyAll(unpack_arguments[1])
        if unpack_arguments[2] then
            IGS.NotifyAll(unpack_arguments[2])
        end
	end)
end

local THIS_TIMESTAMP = os.date("*t", os.time())

http.Fetch("https://date.nager.at/api/v3/PublicHolidays/" .. os.date("%Y", os.time()) .. "/RU", function(code)
    HOLIDAYS_TBL = util.JSONToTable(code)

    for k,v in pairs(HOLIDAYS_TBL) do
        v.countryCode = nil
        v.fixed = nil
        v.global = nil
        v.type = nil
        v.name = nil
        v.launchYear = nil
        if v.localName == "Новогодние Каникулы" and v.date ~= os.date("%Y-01-01", os.time()) then
            HOLIDAYS_TBL[k] = nil -- Удаляем то, чего так много и не должно быть
        end
    end

    hook.Call("Holiday.Create", GAMEMODE)
end)

local DISCOUNT_BLACKLISTED_CATS = {}
HOLIDAYS_TBL = HOLIDAYS_TBL or {}

local function AddBlackCategory(sCat)
	DISCOUNT_BLACKLISTED_CATS[sCat] = true
end

local function AddCustomHoliday(sName, sDate)
    if HOLIDAYS_TBL[#HOLIDAYS_TBL - 1].localName == sName then return false end
    HOLIDAYS_TBL[#HOLIDAYS_TBL + 1] = {localName = sName, date = sDate}
end

local BEFORE_START = 12                 -- За сколько дней до начала праздника будут начинаться скидки, если время проведения б
 
local WEEK_DISCOUNT_ENABLE = true       -- Будут ли действовать скидки по выходным
local WEEK_DISCOUNT = 20                -- Сколько будет действовать процентов скидка на товары
local IGNORE_WEEKEND = true             -- Будут ли игнорироваться скидки по выходным, во время проведения праздничных

local HOLIDAY_DISCOUNT = 50             -- Сколько будет действовать процентов скидка на товары
local HOLIDAY_DURATION = 7              -- Сколько будут действовать скидки после начала праздника (в днях)

--AddBlackCategory("КатегорияНейм") -- Добавление категории, на которую не будут действовать скидки

-- Расскомментишь строку ниже, если надо. Все пояснения даны.
--[[
    1 аргумент - имя праздника
    2 аргумент - дата начала праздника:
        ! Указывается в формате: Год / месяц / день
]]

hook.Add("Holiday.Create", "CUSTOM.HOLIDAYS", function() 
    AddCustomHoliday("Новый год", os.date("%Y-12-31"))
end)

local HOLIDAY, HOLIDAY_DATE_STAMP

local WEEK_TBL = {}
WEEK_TBL["Saturday"] = 2
WEEK_TBL["Sunday"] = 1

local THIS_DAY =  os.date("*t", os.time())["day"]

for k,v in pairs(HOLIDAYS_TBL) do
    local TMP_DATE = string.Split(v.date, "-")
    TMP_DATE[3] = tonumber(TMP_DATE[3])

    local START_DAY = TMP_DATE[3] - BEFORE_START > 0 and TMP_DATE[3] - BEFORE_START or 1
    local END_DAY = TMP_DATE[3] + HOLIDAY_DURATION
    
    if TMP_DATE[1] .. TMP_DATE[2] == os.date("%Y%m", os.time()) and START_DAY <= THIS_DAY and END_DAY >= THIS_DAY then
        HOLIDAY, HOLIDAY_DATE_STAMP = v.localName, os.time({
            year = tonumber(TMP_DATE[1]),
            month = tonumber(TMP_DATE[2]), 
            day = TMP_DATE[3]
        })
		
        break
    end
end

if IGNORE_WEEKEND then
    if HOLIDAY and HOLIDAY_DATE_STAMP then
        WEEK_DISCOUNT_ENABLE = nil -- выключаем скидки по выходным, в случае проведения скидок по праздникам
    else
        TMP_DATE = nil
        HOLIDAY_TIMESTAMP = nil
    end
end

if WEEK_TBL[os.date("%A", os.time())] and WEEK_DISCOUNT_ENABLE then
    for k,v in ipairs(IGS.GetItems()) do
        if !DISCOUNT_BLACKLISTED_CATS[v.category] then
            local old_price = v.price
            local new_price = old_price * (1 - (WEEK_DISCOUNT * 0.01))

            v:SetPrice(new_price)
            v:SetDiscountedFrom(old_price)
        end
    end

    if SERVER then
        disountNotification("В автодонате(F6) действуют скидки (" .. WEEK_DISCOUNT .. "%) на все товары.", "Скидки продлятся до: " .. os.date("%d", os.time() + (WEEK_TBL[os.date("%A", os.time())] * 86400)) .. os.date(".%m", os.time()))
    end
else
    if HOLIDAY and HOLIDAY_DATE_STAMP then
        for k,v in ipairs(IGS.GetItems()) do
            if !DISCOUNT_BLACKLISTED_CATS[v.category] then
                local old_price = v.price
                local new_price = old_price * (1 - (HOLIDAY_DISCOUNT * 0.01))

                v:SetPrice(new_price)
                v:SetDiscountedFrom(old_price)
            end
        end

        if SERVER then
            disountNotification("В автодонате(F6) действуют скидки " .. tostring(HOLIDAY_DISCOUNT) .. [[% на все товары. в честь праздника "]] .. HOLIDAY .. [["]], [[ Скидки продлятся до ]] .. os.date("%d.%m.%y", HOLIDAY_DATE_STAMP + (HOLIDAY_DURATION * 86400)))
        end
    end
end
