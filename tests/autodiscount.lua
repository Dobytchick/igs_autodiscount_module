local source = assert(arg[1], "Укажите путь к igs_autodiscount.lua")
local realDate, realTime = os.date, os.time
local current
os.date = function(format, timestamp) return realDate(format, timestamp or current) end
os.time = function(parts) return parts and realTime(parts) or current end

local function setDate(date)
    local year, month, day = date:match("(%d+)%-(%d+)%-(%d+)")
    current = realTime({year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12})
end

local function item(price, category, discountedFrom)
    return {
        price = price, category = category, discounted_from = discountedFrom,
        SetPrice = function(self, value) self.price = value end,
        SetDiscountedFrom = function(self, value) self.discounted_from = value end
    }
end

local regular = item(100, "Основное", 120)
local dynamic = item(100, "Динамическая")
dynamic.getprice = function() return 75 end
local playerReady = false
LocalPlayer = function() return playerReady and {} or nil end
IsValid = function(value) return value ~= nil end
local notices, errors, requests, timers, hooks, messages = {}, {}, {}, {}, {}, {}
SERVER = true
IGS = {
    GetItems = function() return {regular, dynamic} end,
    NotifyAll = function(message) notices[#notices + 1] = message end
}
ErrorNoHalt = function(message) errors[#errors + 1] = message end
timer = {
    Create = function(name, _, _, callback) timers[name] = callback end,
    Remove = function(name) timers[name] = nil end
}
hook = {
    Add = function(event, name, callback) hooks[event .. ":" .. name] = callback end,
    GetTable = function() return {} end
}
local receivers, currentMessage = {}, nil
net = {
    Receive = function(name, callback) receivers[name] = callback end,
    Start = function(name) currentMessage = {name = name}; return true end,
    WriteBool = function(value) currentMessage.active = value end,
    WriteFloat = function(value) currentMessage.percent = value end,
    Broadcast = function() messages[#messages + 1] = currentMessage end,
    Send = function() messages[#messages + 1] = currentMessage end,
    SendToServer = function() messages[#messages + 1] = currentMessage end,
    ReadBool = function() return currentMessage.active end,
    ReadFloat = function() return currentMessage.percent end
}
http = {
    Fetch = function(url, success, failure)
        requests[#requests + 1] = {url = url, success = success, failure = failure}
    end
}
local responses = {}
util = {
    JSONToTable = function(body) return responses[body] end,
    AddNetworkString = function() end
}

local function expect(actual, wanted, label)
    assert(actual == wanted, label .. ": ожидалось " .. tostring(wanted) .. ", получено " .. tostring(actual))
end

local function reply(year, holidays, code)
    local request
    for i = #requests, 1, -1 do
        if requests[i].url:find("/" .. year .. "/RU", 1, true) then
            request = requests[i]
            break
        end
    end
    assert(request, "Нет HTTP-запроса за " .. year)
    local body = "response-" .. tostring(#requests)
    responses[body] = holidays
    request.success(body, #body, {}, code or 200)
end

setDate("2026-12-18")
dofile(source)
expect(regular.price, 100, "до ответа API цена не меняется")
reply(2027, {
    {date = "2027-01-01", localName = "Новый год"},
    {date = "2027-01-02", localName = "Новогодние каникулы"},
    {date = "2027-01-06", localName = "Новогодние каникулы"}
})
expect(regular.price, 100, "до начала акции цена не меняется")

setDate("2026-12-20")
timers["IGS.AutoDiscount.Refresh"]()
expect(regular.price, 50, "акция начинается в декабре")
expect(regular.discounted_from, 100, "исходная цена зачёркнута")
expect(dynamic.price, 100, "товар с динамической ценой не меняется")
expect(dynamic.discounted_from, nil, "динамической цене не рисуется ложная скидка")
expect(#notices, 1, "одно уведомление при включении")
expect(messages[#messages].percent, 50, "сервер передал скидку")

dofile(source)
expect(regular.price, 50, "перезагрузка не умножает скидку")

setDate("2027-01-08")
timers["IGS.AutoDiscount.Refresh"]()
expect(regular.price, 50, "последний день акции включён")

setDate("2027-01-11")
hooks["PlayerInitialSpawn:IGS.AutoDiscount.Wake"]()
expect(regular.price, 100, "после акции цена восстановлена")
expect(regular.discounted_from, 120, "исходная зачёркнутая цена восстановлена")
expect(timers["IGS.AutoDiscount.Notification"], nil, "уведомления остановлены")
expect(messages[#messages].active, false, "сервер передал окончание акции")

setDate("2027-01-16")
timers["IGS.AutoDiscount.Refresh"]()
expect(regular.price, 80, "скидка выходного дня")
GAMEMODE = {["IGS.ItemPriceOverride"] = function() return 40 end}
timers["IGS.AutoDiscount.Refresh"]()
expect(regular.price, 100, "при переопределении цены скидка отключена")
expect(regular.discounted_from, 120, "ложное зачёркивание убрано")
GAMEMODE = nil
timers["IGS.AutoDiscount.Refresh"]()
expect(regular.price, 80, "после снятия переопределения скидка возвращена")

setDate("2027-01-18")
timers["IGS.AutoDiscount.Refresh"]()
expect(regular.price, 100, "после выходных цена восстановлена")

setDate("2027-12-24")
timers["IGS.AutoDiscount.Refresh"]()
reply(2028, {}, 500)
expect(regular.price, 100, "ошибка HTTP не включает скидку")
assert(#errors > 0, "ошибка HTTP записана")

local clientItem = item(100, "Основное")
IGS.GetItems = function() return {clientItem} end
IGS.AutoDiscountState = nil
SERVER = false
local requestCount = #requests
dofile(source)
expect(#requests, requestCount, "клиент не обращается к календарю")
expect(timers["IGS.AutoDiscount.Request"], nil, "до готовности клиента запроса нет")
playerReady = true
hooks["InitPostEntity:IGS.AutoDiscount.Ready"]()
expect(messages[#messages].name, "IGS.AutoDiscount.Request", "запрос после InitPostEntity")
assert(timers["IGS.AutoDiscount.Request"], "запрос повторяется до ответа")
currentMessage = {active = true, percent = 50}
receivers["IGS.AutoDiscount.Sync"]()
expect(clientItem.price, 50, "клиент применил цену сервера")
expect(timers["IGS.AutoDiscount.Request"], nil, "повторы запроса остановлены")
hooks["IGS.Initialized:IGS.AutoDiscount.Initialized"]()
expect(timers["IGS.AutoDiscount.Request"], nil, "поздний хук не возвращает повторы")
currentMessage = {active = false}
receivers["IGS.AutoDiscount.Sync"]()
expect(clientItem.price, 100, "клиент восстановил цену по сигналу сервера")

print("autodiscount: OK")
