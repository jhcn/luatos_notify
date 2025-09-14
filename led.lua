local     led = {}
local     cfg = config.system.led

local   event = gpio.setup(cfg.event.gpio, 0)
local network = gpio.setup(cfg.network.gpio, 1)

local state = {
    network = nil,
    event   = 0
}

-- 网络
function led.network(x)
    x = x == 1 and 1 or 0
    if state.network ~= x then
        state.network = x
        network(x)
    end
end

-- 事件
function led.event()
    if state.event ~= 0 then return end
    sys.taskInit(function()
        state.event = 1
        for _ = 1, cfg.event.total * 2 do
            gpio.toggle(cfg.event.gpio)
            sys.wait(cfg.event.wait)
        end
        event(0)
        state.event = 0
    end)
end

return led