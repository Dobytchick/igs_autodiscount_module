local holiday_enabled = false
local holiday_name = ""
local holiday_before = ""
local holiday_discount = 50

local weekTable = {}
weekTable[6] = 2
weekTable[0] = 1
weekTable["holidays"] = {enable = holiday_enabled, discount = holiday_discount, holiday = holiday_name, before = holiday_before}

local function getWeekNum()
    return tonumber(os.date("%w", os.time()))
end

local function disountNotification(arg1,arg2)
    IGS.NotifyAll(arg1)
    if arg2 then
        IGS.NotifyAll(arg2)
    end
	timer.Create("Discount", 1300, 0, function()
        IGS.NotifyAll(arg1)
        if arg2 then
            IGS.NotifyAll(arg2)
        end
	end)
end

local function dayManipulation(plus_arg)
    return tostring(tonumber(os.date("%d", os.time())) + plus_arg)
end

if weekTable["holidays"].enable == false then
    if getWeekNum() == 0 or getWeekNum() == 6 then
        for k,v in ipairs(IGS.GetItems()) do
            local old_price = v:Price()
            local new_price = old_price * 0.8
    
            v:SetPrice(new_price)
            v:SetDiscountedFrom(old_price)
        end

        if SERVER then
            if weekTable[getWeekNum()] then
                disountNotification("В автодонате действуют скидки (20%) на все товары.", "Скидки продлятся до: "..dayManipulation(weekTable[getWeekNum()])..os.date(".%m", os.time()))
            end
        end
    end
else
    for k,v in ipairs(IGS.GetItems()) do
        local old_price = v:Price()
        local new_price = old_price * ((100 - weekTable["holidays"].discount) * 0.01)

        v:SetPrice(new_price)
        v:SetDiscountedFrom(old_price)
    end

    if SERVER then
        disountNotification("В автодонате(F6) действуют скидки "..tostring(weekTable["holidays"].discount).."% на все товары.", "Скидки продлятся до "..weekTable["holidays"].before)
    end
end
