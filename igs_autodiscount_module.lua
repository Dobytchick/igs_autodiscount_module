local function disountNotification(...)
    local unpack_arguments = {...}
    IGS.NotifyAll(unpack_arguments[1])
    if unpack_arguments[2] then
        IGS.NotifyAll(unpack_arguments[2])
    end
	timer.Create("Discount", 30, 0, function()
        IGS.NotifyAll(unpack_arguments[1])
        if unpack_arguments[2] then
            IGS.NotifyAll(unpack_arguments[2])
        end
	end)
end

http.Fetch("https://date.nager.at/api/v2/PublicHolidays/" .. os.date("%Y", os.time()) .. "/RU", function(code) 
    HolidaysTable = util.JSONToTable(code)
end)

local DiscountBlacklist = {}
HolidaysTable = HolidaysTable or {}

local function AddBlackCategory(sCat)
	DiscountBlacklist[sCat] = true
end

local function AddCustomHoliday(Sname, Sdate)
    if HolidaysTable[#HolidaysTable - 1].localName == Sname then return false end
    HolidaysTable[#HolidaysTable + 1] = {localName = Sname, date = Sdate}
end

local WeekendDiscountEnabled = true     -- Будут ли действовать скидки по выходным
local WeekendDiscount = 20            -- Сколько будет действовать процентов скидка на товары

local HolidayDiscount = 50              -- Сколько будет действовать процентов скидка на товары
local HolidayDuration = 7               -- Сколько будут действовать скидки после начала праздника (в днях)

AddBlackCategory("КатегорияНейм") -- Добавление категории, на которую не будут действовать скидки

-- Убираем нахуй никому ненужные данные в таблице ¯\_(ツ)_/¯
for k,v in pairs(HolidaysTable) do
    v.countryCode = nil
    v.fixed = nil
    v.global = nil
    v.type = nil
    v.name = nil
    v.launchYear = nil
end

--[[
    1 аргумент - имя праздника
    2 аргумент - дата начала праздника:
        ! Указывается в формате: Год / месяц / день
]]
--AddCustomHoliday("test", "2021-06-11")

local weekTable = {}
weekTable["Saturday"] = 2
weekTable["Sunday"] = 1

if weekTable[os.date("%A", os.time())] and WeekendDiscountEnabled then
    for k,v in ipairs(IGS.GetItems()) do
	if !DiscountBlacklist[v.category] then
		local old_price = v:Price()
		local new_price = old_price * 0.8

		v:SetPrice(new_price)
		v:SetDiscountedFrom(old_price)
	end
    end

    if SERVER then
        disountNotification("В автодонате(F6) действуют скидки (20%) на все товары.", "Скидки продлятся до: " .. os.date("%d", os.time() + (weekTable[os.date("%A", os.time())] * 86400)) .. os.date(".%m", os.time()))
    end
else
    for k,v in pairs(HolidaysTable) do
        if v.date == os.date("%Y-%m-%d", os.time()) then
            local holiday_timestamp = os.time({year = tonumber(string.sub(v.date, 1, 4)), month = tonumber(string.sub(v.date, 6, 7)), day = tonumber(string.sub(v.date, 9))})

            for k,v in ipairs(IGS.GetItems()) do
		if !DiscountBlacklist[v.category] then
			local old_price = v:Price()
			local new_price = old_price * (1 - (HolidayDiscount * 0.01))

			v:SetPrice(new_price)
			v:SetDiscountedFrom(old_price)
		end
            end

            if SERVER then
                disountNotification("В автодонате(F6) действуют скидки " .. tostring(HolidayDiscount) .. [[% на все товары. в честь праздника "]] .. v.localName .. [["]], [[ Скидки продлятся до ]] .. os.date("%d.%m.%y", holiday_timestamp + (HolidayDuration * 86400)))
            end
        end
    end
end
