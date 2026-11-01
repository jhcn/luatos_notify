local module = {

	name = hmeta.model(),   -- 模组型号
	hw   = hmeta.hwver(),   -- 硬件版本
	imei = mobile.imei(),   -- IMEI
	muid = mobile.muid(),   -- MUID
	chip = type(hmeta.chip) == 'function' and hmeta.chip() or nil, -- 芯片型号

	-- os
	os = function()
		-- 固件，版本，编译日
		local fws = rtos.firmware():split('_')
		return table.concat({fws[1], fws[2], rtos.buildDate()}, ' ')
	end,

	-- CPU温度
	temp = function()
		adc.open(adc.CH_CPU)
		local x = adc.get(adc.CH_CPU)
		adc.close(adc.CH_CPU)
		return string.format('%.3f', x / 1000)
	end,

	-- vbus电压
	vbat = function()
		adc.open(adc.CH_VBAT)
		local x = adc.get(adc.CH_VBAT)
		adc.close(adc.CH_VBAT)
		return string.format('%.3f', x / 1000)
	end,

	-- ram，lua区
	ram = function()
		local total, used, _ = rtos.meminfo('lua')
		local pct = (used / total) * 100
		return string.format('%.2f%%', pct)
	end,

	-- 运行时长
	uptime = function()
		local x = 0
		if mcu.ticks() and mcu.hz() then
			x = math.floor((mcu.ticks() * 1000) / mcu.hz())
		end
		return x
	end

}

return module