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
local   config = require 'config'
local   module = require 'module'
local      sim = require 'sim'
local      led = require 'led'
local cellular = require 'cellular'
local      fwd = require 'fwd'

-- do end块可限制变量作用域

-- 日志
do
	local s = config.system.log or {}
	log.setLevel(s.level or 2)						-- 日志级别，https://docs.openluat.com/osapi/core/log/#_4
    log.style(s.style or 0)							-- 日志风格，https://docs.openluat.com/osapi/core/log/#43-logstyleval
end

mobile.ipv6(config.network.IPv6 == 1)       		-- IPv6开关，true/false
mobile.setAuto(1000 * 5, 1000 * 10, 5)              -- SIM脱离后自动恢复/ms，搜索周围小区信息周期/ms，超时/s
pm.power(pm.WORK_MODE, 0)                           -- 休眠模式，不休眠

-- IO
do
	local d = config.io.default or {}
	gpio.setDefaultPull(d.pull or 0)                -- IO默认电平
	pm.ioVol(pm.IOVOL_ALL_GPIO, d.volt or 3300)     -- IO高电平时电压
end

-- 关闭供电，https://docs.openluat.com/osapi/core/pm/#_2
for _, mod in ipairs({pm.GPS, pm.GPS_ANT, pm.CAMERA}) do
	pm.power(mod, false)
end

-- USB data，1开，0关
-- 如关闭，开机2分钟后执行，而非立刻
if config.usb.dpdm ~= 1 then
	sys.timerStart(pm.power, 1000 * 60 * 2, pm.USB, false)
end

-- USB网卡，RNDIS 3，ECM 7
if config.usb.nic == 1 then
	mobile.config(mobile.CONF_USB_ETHERNET, 3)
end

-- 随机种子
sys.taskInit(function()
	sys.waitUntil('IP_READY')
	math.randomseed(mcu.ticks() or os.clock())
end)

-- SIM卡配置
if sim.init(config.sim or {}) then
	print('SIM卡配置', '初始化结束')
end

-- io电平
for _, item in ipairs(config.io.custom or {}) do
	gpio.setup(item.gpio, item.pull == 1 and 1 or 0)
end

-- LED指示灯
if led then
	local succ, ret = led.init(config.io.led or {})
	print('LED指示灯', json.encode(succ and ret or {}))
end

-- 转发通道初始化
if fwd then
	local h = fwd.init.http(config.forward.http or {})
	print('通知通道', 'HTTP', json.encode(h or {}))
	local s = fwd.init.smtp(config.forward.smtp or {})
	print('通知通道', 'SMTP', json.encode(s or {}))
end

-- !!! 注意，初始化结束不代表成功

-- sms.debug(true)

local ip_status = {
	onl = false,        -- 联网状态
	dis = 0             -- 断网次数
}

-- 手机号码校验
local function is_mobile(num)
	return (#num == 11 and num:match('^1[3-9]'))
end

-- 对时，如开启，默认基站
-- 使用sntp需满足下列全部条件
-- 1，基站对时不成功
-- 2，允许使用sntp
-- 3，有配置ntp服务器
do
	local c = config.time or {}
	local o = c.sync == 1

	mobile.syncTime(o)
	if not o then return end
	sys.taskInit(function()
		sys.waitUntil('IP_READY')
		sys.wait(1000 * 5)

		if not c.sntp or os.time() > 1770000000 then return end

		local t = c.sntp
		local e = t.enabled == 1 and 1 or 0
		local s = t.server or {}
		if e == 1 and next(s) then
			print(json.encode(s))
			socket.sntp(s)
		end
	end)
end

-- 等待IP_READY，超时则重置LTE使系统重发SIM_IND
-- 场景 1，开机未联网 2，断网未恢复联网
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

-- 等待SMS_READY
-- SIM卡RDY一定时间内没等到将重启LTE协议栈
do
	-- 例外型号，不参与SMS_READY等待
	local m = {
		Air780PV = true,
		EC718PV	 = true
	}

	if m[module.name] then
		return
	end

	sys.subscribe('IP_LOSE', function()
		sys.taskInit(function()
			local succ = sys.waitUntil('SMS_READY', 1000 * 20)
			if not succ then
				mobile.reset()
				print('网络重置', '原因', '短信功能超时未就绪')
			else
				print('短信', '功能就绪')
			end
		end)
	end)
	-- 需关注底层版本号，不正确的底层将造成严重故障(周期性重启LTE协议栈)
	-- https://gitee.com/openLuat/LuatOS/releases/tag/v1118.ec618.release
	-- https://gitee.com/openLuat/LuatOS/releases/tag/v2020.ec7xx.release
	-- V1118 起支持SMS_READY Air780E/Air780EG
	-- V2020 起支持SMS_READY Air780EPM/EHM/Air8000/Air780EP
end

-- SIM卡RDY
sys.subscribe('SIM_IND', function(status, value)
	if status == 'RDY' then
		mobile.config(mobile.CONF_STATICCONFIG, 1)	-- 开启静态网络优化
		mobile.config(mobile.CONF_QUALITYFIRST, 2)	-- 网络切换以信号质量优先
		sys.publish('IP_LOSE')
	end
end)

-- 指令
do
	-- 管理员号码
	local admins = {}

	-- 构建管理员号码名单
	for _, n in pairs(config.system.admin or {}) do
		admins[n] = true
	end

	-- 短信指令
	sys.subscribe('SMS_INC', function(from, content)
		-- 短信控制模块：名单为空或来信号码在名单内
		if next(admins) and not admins[from] then return end

		-- 以##为关键词分割短信内容
		local parts = content:split('##')

		if #parts < 2 or parts[1]:lower() ~= 'cmd' then return end
		table.remove(parts, 1)

		-- 指令类型，号码
		local cmd, num = parts[1]:lower(), parts[2]

		-- 重启系统，示例cmd##reboot
		if cmd == 'reboot' then
			print('短信指令', '重启系统')
			sys.publish('sys_reboot')
		end

		-- 发出短信，示例，cmd##sms##10001##108
		-- 需满足所列全部条件 1，第一个值是SMS 2，数组值不少于3个 3，第二个值是数字
		if cmd == 'sms' and #parts > 2 and tonumber(num) then
			local txt = table.concat(parts, '##', 3)
			print('短信指令', '发送短信', num, txt)
			sms.send(num, txt, false)
		end
	end)
end

-- 收到短信
sys.subscribe('SMS_INC', function(num, txt)
	fwd.add({
		typ     = 'sms',
		content = txt,
		from    = num,
		me      = sim.number
	})
end)

-- VOLTE功能
do
	local e = {
		['READY']            = '功能就绪',
		['PLAY']             = '正在振铃',
		['INCOMINGCALL']     = '有人致电',
		['CONNECTED']        = '通话开始',
		['SPEECH_START']     = '通话建立',
		['DISCONNECTED']     = '通话断开',
		['ANSWER_CALL_DONE'] = '接听电话，已执行',
		['HANGUP_CALL_DONE'] = '挂断电话，已执行'
	}

	local s = {
		incoming = false,   -- 被叫状态
		count    = 0        -- 振铃次数，挂断后重置为0
	}

	-- 更新状态
	-- 值为1时，振铃，振铃数加1
	-- 值为0时，挂断，振铃数归0
	local function r(v)
		s.incoming = v == 1
		s.count    = v == 1 and s.count + 1 or 0
	end

	sys.subscribe('CC_IND', function(status)
			if status == 'READY' then cc.init(0)
		elseif status == 'HANGUP_CALL_DONE'
			or status == 'DISCONNECTED' then r(0)
		elseif status == 'INCOMINGCALL' then
			-- 首次振铃
			if not s.incoming then
				fwd.add({
					typ     = 'call',
					content = '有人致电',
					from    = cc.lastNum(),
					me      = sim.number
				})
			end
			r(1)
		end
		print('VOLTE功能', e[status] or status, cc.lastNum(), json.encode(s), status)
	end)
end

-- IP_READY，设置DNS
sys.subscribe('IP_READY', function(ip, adapter)
	-- 系统未联网，IP_READY时，执行
	-- 系统已联网，IP_READY时，跳过
	if not ip_status.onl then
		ip_status.onl = true
		print('成功联网', ip, adapter)
		print('网络详情', socket.localIP())
		local dns = config.network.dns or {}
		for i, ns in ipairs(dns) do
			socket.setDNS(adapter, i, ns)
			print('网卡', adapter, 'DNS', i, ns)
		end
	end
end)

-- 开机通知
if config.forward.start_msg == 1 then
	sys.taskInit(function()
		sys.waitUntil('IP_READY')
		local content = {
			imsi    = sim.imsi,
			plmn    = sim.plmn,
			iccid   = sim.iccid,
			number  = sim.number,
			brand 	= sim.brand,
			apn     = cellular.apn(),
			rsrp    = cellular.rsrp(),
			csq     = cellular.csq(),
			muid    = module.muid,
			imei    = module.imei,
			vbat    = module.vbat(),
			temp    = module.temp(),
			uptime  = module.uptime()
		}
		-- 转为字符串
		local txt = {}
		for k, v in pairs(content) do
			txt[#txt + 1] = string.format('%-10s%s', k, v)
		end
		fwd.add({
			typ     = 'msg',
			content = table.concat(txt, '\n'),
			from    = module.name
		})
	end)
end

-- 重启模块
sys.subscribe('sys_reboot', function()
	if fwd.job_cnt() > 0 then
		sys.timerStart(sys.publish, 1000 * 3, 'sys_reboot')
	else
		pm.reboot()
	end
end)

-- 定时重启，小时
do
	local t = config.system.auto.reboot
	if t > 0 then
		sys.timerStart(sys.publish, 1000 * 60 * 60 * t, 'sys_reboot')
	end
end

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
	if state == 1 then
		mobile.config(mobile.CONF_MAX_TX_POWER, 23)
	end
	-- print('CSCON', state)
end)

print('项目详情', PROJECT, VERSION)

sys.run()