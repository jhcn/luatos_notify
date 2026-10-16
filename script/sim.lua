local brand = {
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

-- 状态对应中文释义
local status_map = {
	['RDY']        = '已经就绪',
	['NORDY']      = '未识别到',
	['SIM_PIN']    = '需要验证',
	['GET_NUMBER'] = '读取号码'
}

local cfg = {}
local sim = {

	profile = {},

	-- 初始化
	init = function(config)
		cfg = config or {}
		return true
	end

}

-- SIM卡就绪
sys.subscribe('SIM_IND', function(status, value)

	print('SIM卡', status_map[status] or '未知', status, value)

	-- 仅关注RDY状态
	if status ~= 'RDY' then return end

	local id     = mobile.simid()
	local imsi   = mobile.imsi(id) or mobile.imsi()
	local iccid  = mobile.iccid(id) or mobile.iccid()
	local number = mobile.number(id) or mobile.number()
	local plmn   = imsi and imsi:sub(1, 5)
	local pf 	 = cfg[iccid] or {}

	sim.profile = {
		id     = id,
		imsi   = imsi,
		plmn   = plmn,
		iccid  = iccid,
		number = pf.number or number,
		brand  = pf.brand or (plmn and brand[plmn])
	}

end)

return sim