local cfg = {}
local sim = {
	init = function(config)
		cfg = config or {}
		return true
	end
}

do
	-- 状态对应中文释义
	local e = {
		['RDY']        = '卡已就绪',
		['NORDY']      = '未识别到',
		['SIM_PIN']    = '需要验证',
		['GET_NUMBER'] = '获取号码'
	}

	-- 运营商
	local b = {
		['46000'] = '中国移动',
		['46002'] = '中国移动',
		['46004'] = '中国移动',
		['46007'] = '中国移动',
		['46008'] = '中国移动',
		['46024'] = '中国移动',

		['46001'] = '中国联通',
		['46006'] = '中国联通',
		['46009'] = '中国联通',

		['46003'] = '中国电信',
		['46005'] = '中国电信',
		['46011'] = '中国电信',

		['46015'] = '中国广电'
	}

	-- SIM卡就绪
	sys.subscribe('SIM_IND', function(status, value)

		print('SIM状态', e[status] or '未知', status, value)

		if status ~= 'RDY' then return end	-- 仅关注RDY状态

		local id     = mobile.simid()
		local imsi   = mobile.imsi(id) or mobile.imsi()
		local plmn   = imsi and imsi:sub(1, 5)
		local iccid  = mobile.iccid(id) or mobile.iccid()
		local pf 	 = cfg[iccid] or {}

		sim.id     = id
		sim.imsi   = imsi
		sim.plmn   = plmn
		sim.iccid  = iccid
		sim.brand  = pf.brand or (plmn and b[plmn])
		sim.number = pf.number or mobile.number(id) or mobile.number()

	end)
end

return sim