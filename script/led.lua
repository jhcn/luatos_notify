local role = {}

-- 开关led
-- LED名称，最终状态(1亮，0灭)，循环次数
local function sw(name, final, loops)
	local target = role[name]
	if not target then return end
	sys.taskInit(function()
		local state = 1
		for _ = 1, (loops or 0) * 2 do
			target(state)
			sys.wait(60)
			state = 1 - state
		end
		target(final)
	end)
end

sys.subscribe('led_rdy', function()
	sys.timerLoopStart(function()
		sw('event', 0, 1)
	end, 1000 * 3)
end)

local led = {
	-- 初始化led
	init = function(cfg)
		local l = {}
		for _, item in ipairs(cfg) do
			local r, n, p = item.role, item.gpio, item.pull == 1 and 1 or 0
			gpio.debounce(n, 0)
			role[r] = gpio.setup(n, p)
			l[r] = n
		end
		sys.publish('led_rdy')
		return next(l) ~= nil, l
	end
}

-- LED名称，最终状态(1亮，0灭)，循环次数
sys.subscribe('IP_READY', function() sw('network', 1)  end) -- 联网，LED开/关
sys.subscribe('IP_LOSE',  function() sw('network', 0)  end) -- 断网，LED开/关
sys.subscribe('job_enq',  function() sw('event', 0, 4) end) -- 事件，LED闪烁

return led