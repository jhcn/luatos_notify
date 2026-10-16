PROJECT = 'Test_Project'                          -- 项目名，不能有空格
VERSION = '0.06.1'                                -- 版本号，不能有空格

-- 全局变量，系统库
_G.sys     = require 'sys'
_G.sysplus = require 'sysplus'

-- 关闭异常日志上报
if errDump then
	errDump.config(false)
end

-- 看门狗
if wdt then
	wdt.init(1000 * 9)
	sys.timerLoopStart(wdt.feed, 1000 * 3)
end

-- 局部变量，用户库
local    config = require 'config'
local    module = require 'module'
local       sim = require 'sim'
local       led = require 'led'
local  cellular = require 'cellular'
local       fwd = require 'fwd'

log.setLevel(config.system.log.level)               -- 输出日志级别，SILENT，DEBUG，INFO，WARN，ERROR，FATAL 0,1,2,3,4,5
log.style(config.system.log.style)                  -- 日志风格

mobile.ipv6(config.network.IPv6 == 1)       		-- IPv6开关，true/false
mobile.setAuto(1000 * 5, 1000 * 10, 5)              -- SIM脱离后自动恢复/ms，搜索周围小区信息周期/ms，超时/s

local ioc = config.io.default
pm.ioVol(pm.IOVOL_ALL_GPIO, ioc.vol)                -- IO高电平时电压
gpio.setDefaultPull(ioc.pull)                       -- IO默认电平
pm.power(pm.WORK_MODE, 0)                           -- 休眠模式，不休眠

-- USB电源
-- 如关闭，会在开机2分钟后关闭，而非立即关闭
if config.usb.dpdm == 0 then
	sys.timerStart(function()
		pm.power(pm.USB, false)
	end, 1000 * 60 * 3)
end

-- 随机种子
sys.taskInit(function()
	sys.waitUntil('IP_READY')
	math.randomseed(mcu.ticks() or os.clock())
end)

-- USB网卡
-- RNDIS
if config.usb.net == 1 then
	sys.taskInit(function()
		sys.waitUntil('IP_READY')
		mobile.flymode(sim.id, true)
		mobile.config(mobile.CONF_USB_ETHERNET, 3)
		mobile.flymode(sim.id, false)
	end)
end

-- SIM卡配置
if sim.init(config.sim or {}) then
	print('SIM卡配置', '初始化结束')
end

-- LED指示灯
if led then
	local succ, ret = led.init(config.io.led or {})
	print('LED指示灯', json.encode(succ and ret or {}))
end

-- gpio.setup(27, 1)
-- gpio.setup(30, 1)

-- 转发通道初始化
if fwd then
	local h = fwd.init.http(config.forward.http or {})
	print('通知通道', 'HTTP', json.encode(h or {}))
	local s = fwd.init.smtp(config.forward.smtp or {})
	print('通知通道', 'SMTP', json.encode(s or {}))
end

-- !!! 注意，初始化结束不代表成功

local pow_off = {
	pm.GPS,         -- gps
	pm.GPS_ANT,     -- gps天线
	pm.CAMERA       -- camera
}

-- 关闭供电
for _, mod in ipairs(pow_off) do
	pm.power(mod, 0)
end

-- sms.debug(true)

local sys_cfg = {       -- 系统设置
	admin = {}          -- 控制模块的号码清单
}

local ip_status = {     -- 网络状态
	onl = false,        -- 联网状态
	dis = 0             -- 断网次数
}

-- 语音电话
local call = {
	event = {
		['READY']            = '功能就绪',
		['PLAY']             = '正在振铃',
		['INCOMINGCALL']     = '有人致电',
		['CONNECTED']        = '通话开始',
		['SPEECH_START']     = '通话建立',
		['DISCONNECTED']     = '通话断开',
		['ANSWER_CALL_DONE'] = '接听电话，已执行',
		['HANGUP_CALL_DONE'] = '挂断电话，已执行'
	},
	status = {
		incoming = false,   -- 被叫状态
		count    = 0        -- 振铃次数，挂断后重置为0
	}
}

-- 构建可控制模块的号码清单
if next(config.system.admin) then
	for _, v in pairs(config.system.admin) do
		sys_cfg.admin[v] = true
	end
end

-- 设备信息
-- 务必在联网后调用
local function details()
	local pf = sim.profile
	return {
		muid    = module.muid,
		imei    = module.imei,
		imsi    = pf.imsi,
		plmn    = pf.plmn,
		iccid   = pf.iccid,
		sim_id  = pf.id,
		number  = pf.number,
		brand 	= pf.brand,
		apn     = cellular.apn(),
		rsrp    = cellular.rsrp(),
		csq     = cellular.csq(),
		ram     = module.ram(),
		vbat    = module.vbat(),
		temp    = module.temp(),
		uptime  = module.uptime(),
		os      = module.os()
	}
end

-- 手机号码校验
local function is_mobile(num)
	return (#num == 11 and num:match('^1[3-9]'))
end

-- 本机号码
local my_number = function()
	-- return nil
	return sim.profile.number
end

-- 对时
-- 默认基站，如失败且sntp开启则使用ntp服务器
sys.taskInit(function()
	local cfg = config.time or {}
	local  on = cfg.sync == 1
	mobile.syncTime(on)
	if not on then return end
	sys.waitUntil('IP_READY')
	sys.wait(1000 * 5)
	if os.time() > 1770000000 then
		return
	end
	local srv = cfg.sntp.server
	local  en = cfg.sntp.enabled
	if en == 1 and next(srv) then
		print(json.encode(srv))
		socket.sntp(srv)
	end
end)

-- 重启LTE协议栈，需符合下列条件之一
-- 1，开机一定时间后未联网
-- 2，断网一定时间后未恢复联网
-- 重启LTE协议栈会使底层重发SIM_IND消息
sys.subscribe('IP_LOSE', function()
	sys.taskInit(function()
		ip_status = {
			onl = false,
			dis = ip_status.dis + 1
		}
		local succ = sys.waitUntil('IP_READY', 1000 * 10)
		if not succ then
			mobile.reset()
			print('网络重置', '原因', '开机/断网后 未联网')
		end
	end)
end)

-- SIM卡就绪，等待联网，仅关注状态RDY
sys.subscribe('SIM_IND', function(status, value)
	if status ~= 'RDY' then
		return
	end
	mobile.config(mobile.CONF_STATICCONFIG, 1)	-- 开启静态网络优化
	mobile.config(mobile.CONF_QUALITYFIRST, 2)	-- 网络切换以信号质量优先
	sys.publish('IP_LOSE')
end)

-- 短信指令
sys.subscribe('SMS_INC', function(from, content)
	-- 满足以下条件其一可短信控制本模块
	-- 1，名单为空
	-- 2，来信号码存在于名单内
	if not next(config.system.admin) or sys_cfg.admin[from] then
		-- 内容含字符##
		if not content:match('##') then return end
		-- 以##为关键词分割
		local parts = content:split('##')
		-- 满足以下全部条件的短信内容将判定为短信发送指令
		-- 1，数组值不少于3个
		-- 2，第一个值是SMS
		-- 3，第二个值是数字
		if #parts < 3 then return end
		local cmd = parts[1]:lower()
		local num = parts[2]
		if cmd == 'sms' and tonumber(num) then
			local send_txt = table.concat(parts, '##', 3)
			local send_to  = num
			print('发送短信', send_to, send_txt)
			sms.send(send_to, send_txt, false)
		end
		-- 示例，sms##10001##108
	end
end)

-- 收到短信
sys.subscribe('SMS_INC', function(num, txt)
	fwd.start({
		typ     = 'sms',
		content = txt,
		from    = num,
		me      = my_number()
	})
end)

-- 重置cc状态
local function cc_reset()
	call.status = {
		incoming = false,
		count    = 0
	}
end

-- VOLTE功能
sys.subscribe('CC_IND', function(status)
		if status == 'READY' then cc.init(0)
	elseif status == 'HANGUP_CALL_DONE' or status == 'DISCONNECTED' then cc_reset()
	elseif status == 'INCOMINGCALL' then

		local sts = call.status

		-- 首次振铃
		if not sts.incoming then
			fwd.start({
				typ     = 'call',
				content = '有人致电',
				from    = cc.lastNum(),
				me      = my_number()
			})
		end

		-- 更新状态
		-- 改值而非新table覆盖之，可提升性能。但我不喜欢
		call.status = {
			incoming = true,
			count    = sts.count + 1
		}

	end
	print('VOLTE功能', call.event[status] or status, cc.lastNum(), json.encode(call.status), status)
end)

-- 网络就绪
-- IP_READY会在双栈网络中重复出现
-- IP_READY首次出现时标记已联网能有效避免代码重复执行
sys.subscribe('IP_READY', function(ip, adapter)

	if ip_status.onl then return end    -- 已联网则退出
	ip_status.onl = true                -- 标记已联网

	print('成功联网', ip, adapter)
	print('网络详情', socket.localIP())

	-- DNS设置
	local dns = config.network.dns or {}
	for i, ns in ipairs(dns) do
		socket.setDNS(adapter, i, ns)
		print('网卡', adapter, 'DNS', i, ns)
	end

end)

-- 开机通知
if config.forward.startup == 1 then
	sys.taskInit(function()
		sys.waitUntil('IP_READY')
		local content = details()
		-- 转为字符串
		local txt = ''
		for k, v in pairs(content) do
			txt = string.format('%s%-10s%s%s', txt, k, v, '\n')
		end

		fwd.start({
			typ     = 'msg',
			content = txt,
			from    = hmeta.model()
		})
	end)
end

-- 重启模块
sys.subscribe('sys_reboot', function()
	sys.taskInit(function()
		if not call.status.incoming then
			pm.reboot()
		else
			sys.wait(1000 * 3)
			sys.publish('sys_reboot')
		end
	end)
end)

-- 定时重启，小时
local reboot = config.system.auto.reboot
if reboot > 0 then
	sys.timerStart(sys.publish, 1000 * 60 * 60 * reboot, 'sys_reboot')
end

print('项目详情', PROJECT, VERSION)
-- print('系统设置', json.encode(sys_cfg))

-- 短信功能
sys.subscribe('SMS_READY', function()
	print('短信', '功能就绪')
end)

-- 短信功能
sys.subscribe('SMS_SENT', function(result)
	print('发送短信', (result and '成功' or '失败'))
end)

-- 时间更新
-- 通过基站或NTP服务器同步成功皆会发布NTP_UPDATE
sys.subscribe('NTP_UPDATE', function()
	print('时间同步', '成功', os.time(), os.date())
end)

-- RRC状态
sys.subscribe('CSCON', function(state)
	-- if state == 1 then
	--     mobile.config(mobile.CONF_MAX_TX_POWER, 0)
	-- end
	-- print('CSCON', state)
end)

sys.run()