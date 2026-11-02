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

-- do end块可限制变量作用域

-- 日志
do
	local s = config.system.log or {}
	log.setLevel(s.level or 2)						-- 日志级别，参考https://docs.openluat.com/osapi/core/log/#_4
    log.style(s.style or 0)							-- 日志风格，参考https://docs.openluat.com/osapi/core/log/#43-logstyleval
end

mobile.ipv6(config.network.IPv6 == 1)       		-- IPv6开关，true/false
mobile.setAuto(1000 * 5, 1000 * 10, 5)              -- SIM脱离后自动恢复/ms，搜索周围小区信息周期/ms，超时/s
pm.power(pm.WORK_MODE, 0)                           -- 休眠模式，不休眠

-- IO
do
	local d = config.io.default or {}
	pm.ioVol(pm.IOVOL_ALL_GPIO, d.vol or 3300)      -- IO高电平时电压
	gpio.setDefaultPull(d.pull or 0)                -- IO默认电平
end

-- 关闭供电，参考https://docs.openluat.com/osapi/core/pm/#_2
for _, mod in ipairs({pm.GPS, pm.GPS_ANT, pm.CAMERA}) do
	pm.power(mod, false)
end

-- USB电源，1开，0关
-- 如关闭，会在开机2分钟后关闭，而非立即关闭
do
	local x = config.usb.dpdm == 1
	sys.timerStart(pm.power, 1000 * 60 * 2, pm.USB, x)
end

-- USB网卡，RNDIS 3，ECM 7
if config.usb.net == 1 then
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
	local n, p = item.gpio, item.pull == 1 and 1 or 0
	print('gpio', n, p)
	gpio.setup(n, p)
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

local ip_status = {     -- 网络状态
	onl = false,        -- 联网状态
	dis = 0             -- 断网次数
}

-- 设备信息
-- 务必在联网后调用
local function details()
	return {
		imsi    = sim.imsi,
		plmn    = sim.plmn,
		iccid   = sim.iccid,
		sim_id  = sim.id,
		number  = sim.number,
		brand 	= sim.brand,
		apn     = cellular.apn(),
		rsrp    = cellular.rsrp(),
		csq     = cellular.csq(),
		muid    = module.muid,
		imei    = module.imei,
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

-- 等待IP_READY
-- 重置LTE协议栈，需符合下列条件之一
-- 1，开机一定时间内未联网
-- 2，断网一定时间内未恢复联网
-- 重置LTE协议栈会使底层重发SIM_IND消息
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

	if m[hmeta.model()] then
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
	-- V1118 之前版本无SMS_READY消息。 Air780E
	-- V2020 之前版本无SMS_READY消息。 Air780EPM/EHM/Air8000/Air780EP
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

	-- 构建可控制模块的号码清单
	for _, n in pairs(config.system.admin or {}) do
		admins[n] = true
	end

	-- 短信指令
	sys.subscribe('SMS_INC', function(from, content)
		-- 满足以下条件其一可短信控制本模块
		-- 1，名单为空
		-- 2，来信号码存在于名单内
		if not next(admins) or admins[from] then
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
	-- 值非1时，挂断，振铃数归0
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

-- 网络就绪，设置DNS
-- IP_READY会在双栈网络中重复出现
-- IP_READY首次出现时标记已联网能有效避免代码重复执行
sys.subscribe('IP_READY', function(ip, adapter)
	if not ip_status.onl then				-- 未联网适用
		ip_status.onl = true                -- 标记已联网
		print('成功联网', ip, adapter)
		print('网络详情', socket.localIP())

		-- DNS设置
		local dns = config.network.dns or {}
		for i, ns in ipairs(dns) do
			socket.setDNS(adapter, i, ns)
			print('网卡', adapter, 'DNS', i, ns)
		end
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

		fwd.add({
			typ     = 'msg',
			content = txt,
			from    = hmeta.model()
		})
	end)
end

-- 重启模块
sys.subscribe('sys_reboot', function()
	sys.taskInit(function()
		if fwd.job_cnt() < 1 then
			pm.reboot()
		else
			sys.wait(1000 * 3)
			sys.publish('sys_reboot')
		end
	end)
end)

-- 定时重启，小时
do
	local t = config.system.auto.reboot
	if t > 0 then
		sys.timerStart(sys.publish, 1000 * 60 * 60 * t, 'sys_reboot')
	end
end

print('项目详情', PROJECT, VERSION)

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

sys.run()