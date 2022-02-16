local charts = require("charts")
local term = require("term")
local event = require("event")
local component = require("component")
local controller = component.me_controller
local matrix = component.induction_matrix
local reactors = {}
local fuel_controller = {}
local fuel_keys = {
    [1] = "LEU-235-Ox",
    [2] = "MOX-241",
    [3] = "TBU-Ox",
    [4] = "HEU-233-Ox"
}
local fuel_names = {
    ["LEU-235-Ox"] = "LEU-235 Oxide Fuel",
    ["MOX-241"] = "MOX=241 Fuel",
    ["TBU-Ox"] = "TBU Oxide Fuel",
    ["HEU-233-Ox"] = "HEU-233 Oxide Fuel"
}

local cache = {}

local function findValue(tbl, key)
    if cache[key] == nil then
        local value
        for k, v in pairs(tbl) do
            if v == key then
                value = k
            end
        end
        cache[key] = value
    end
    return cache[key]
end

-- change these depending on how many monitors / reactors you have
width = 80 -- 56 is for 5x4 monitor w/ 4 reactors
height = 9 -- 5 is for 5x4 monitor w/ 4 reactors

for address, _ in component.list("nc_fission_reactor") do
    table.insert(reactors, component.proxy(address))
end

for address, _ in component.list("inventory_controller") do
    table.insert(fuel_controller, component.proxy(address))
end

function getRFLevel(reactor)
    return reactor.getEnergyStored() / reactor.getMaxEnergyStored()
end

function getHeatLevel(reactor)
    return reactor.getHeatLevel() / reactor.getMaxHeatLevel()
end

function control()
    safe = true
    for _, reactor in pairs(reactors) do
        if safe == false then
            reactor.deactivate()
        end
        if getHeatLevel(reactor) < 0.5 then
            if getRFLevel(reactor) < 0.99 then
                reactor.activate()
            else
                reactor.deactivate()
            end
        else
            reactor.deactivate()
        end
    end
    if safe == false then
        os.exit()
    end
end

local main_power_bar = charts.Container {
    x = 3,
    y = 3,
    width = width - 36,
    height = 2,
    payload = charts.ProgressBar {
        direction = charts.sides.RIGHT,
        value = 0,
        colorFunc = function(_, percent)
            if percent >= 0.92 then
                return 0x00ff00
            elseif percent >= 0.85 then
                return 0x2bff00
            elseif percent >= 0.77 then
                return 0x55ff00
            elseif percent >= 0.69 then
                return 0x80ff00
            elseif percent >= 0.62 then
                return 0xaaff00
            elseif percent >= 0.54 then
                return 0xd5ff00
            elseif percent >= 0.46 then
                return 0xffff00
            elseif percent >= 0.38 then
                return 0xffd500
            elseif percent >= 0.31 then
                return 0xffaa00
            elseif percent >= 0.23 then
                return 0xff8000
            elseif percent >= 0.15 then
                return 0xff5500
            elseif percent >= 0.08 then
                return 0xff2b00
            else
                return 0xff0000
            end
        end
    }
}

local induction_power_bar = charts.Container {
    x = 3,
    y = 7,
    width = main_power_bar.width,
    height = 2,
    payload = charts.ProgressBar {
        direction = charts.sides.RIGHT,
        value = 0,
        colorFunc = main_power_bar.payload.colorFunc
    }
}

local reactor_power_bars = {}
local fuel_bars = {}

for i = 1, #reactors do
    table.insert(reactor_power_bars,
            charts.Container {
                x = 3,
                y = 7 + 4 * i,
                width = main_power_bar.width,
                height = 2,
                payload = charts.ProgressBar {
                    direction = charts.sides.RIGHT,
                    value = 0,
                    colorFunc = main_power_bar.payload.colorFunc
                }
            }
    )
    fuel_bars[fuel_keys[i]] =
            charts.Container {
                x = 50,
                y = 7 + 4 * i,
                width = 27,
                height = 2,
                payload = charts.ProgressBar {
                    direction = charts.sides.RIGHT,
                    value = 0,
                    colorFunc = main_power_bar.payload.colorFunc
                }
            }
end

fuel_bars["MISSING FUEL"] =
        charts.Container {
            x = 50,
            y = 3,
            width = 27,
            height = 2,
            payload = charts.ProgressBar {
                direction = charts.sides.RIGHT,
                value = 100,
                colorFunc = function()
                    return 0xff0000
                end
            }
        }

term.clear()
component.gpu.setResolution(width, height + #reactors * 4)

local fuel_index = {}
local tflop = false
local missing = false
local fuel_amount

while true do
    control()
    me_value = math.min(controller.getStoredPower()/controller.getMaxStoredPower(), 1)
    induction_value = math.min(matrix.getEnergy()/matrix.getMaxEnergy(), 1)
    main_power_bar.gpu.set(3, 2, "ME Available Power: " .. ("%.2f"):format(me_value*100) .. "%     ")
    induction_power_bar.gpu.set(3, 6, "Induction Matrix Power: " .. ("%.2f"):format(induction_value*100) .. "%     ")
    main_power_bar.payload.value = me_value
    induction_power_bar.payload.value = induction_value
    main_power_bar:draw()
    induction_power_bar:draw()
    for j = 1, #reactors do
        fuel_item = fuel_controller[j].getStackInSlot(5, 1)
        table.insert(fuel_index, findValue(fuel_keys, findValue(fuel_names, fuel_item)))
        print(fuel_index[j])
    end
    for i = 1, #reactors do
        power = getRFLevel(reactors[i])
        fuel = reactors[i].getFissionFuelName()
        fuel_item = fuel_controller[i].getStackInSlot(5, 1)
        if fuel == nil then
            fuel_amount = 0
            tflop = not tflop
            if tflop then
                fuel_amount = 64
            end
            missing = true
        else
            fuel_amount = fuel_item.size
        end
        fuel_bars[fuel].payload.value = fuel_amount / 64
        if missing then
            fuel_bars["MISSING FUEL"].gpu.set(50, 2, "MISSING FUEL")
            fuel_bars["MISSING FUEL"]:draw()
            fuel_amount = 0
        end
        fuel_bars[fuel].gpu.set(50, 6 + i * 4, fuel .. ": " .. ("%.2f"):format(fuel_amount/64*100) .. "%     ")
        fuel_bars[fuel]:draw()
        reactor_power_bars[i].gpu.set(3, 6 + i * 4, "Reactor " .. i .. ": " .. ("%.2f"):format(power*100) .. "%     ")
        reactor_power_bars[i].payload.value = power
        reactor_power_bars[i]:draw()
    end
    if event.pull(0.05, "interrupted") then
        term.clear()
        os.exit()
    end
end