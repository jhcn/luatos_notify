-- 队列
local jobs = {}

-- 设置
local setting = {
	http = {},
	smtp = {}
}

-- 编码为base64
local function b64e(str)
	str = tostring(str)
	return string.toBase64(str)
end

local build = {

	-- 返回 method, url, headers, body

	-- 微信
	wecom = function(cfg, data)
		return 'POST', cfg.url, {
			['Content-Type'] = 'application/json; charset=utf-8'
		}, json.encode({
			text = {
				content = table.concat({data.content or '', data.from or '', data.me or ''}, '\n')
			},
			msgtype = 'text'
		})
	end,

	-- 飞书
	feishu = function(cfg, data)
		return 'POST', cfg.url, {
			['Content-Type'] = 'application/json; charset=utf-8'
		}, json.encode({
			content = {
				text = table.concat({data.content or '', data.from or '', data.me or ''}, '\n')
			},
			msg_type = 'text'
		})
	end,

	-- dingtalk/钉钉
	dingtalk = function(cfg, data)
		return 'POST', cfg.url, {
			['Content-Type'] = 'application/json; charset=utf-8'
		}, json.encode({
			text = {
				content = table.concat({data.content or '', data.from or '', data.me or ''}, '\n')
			},
			msgtype = 'text'
		})
	end,

	-- bark
	bark = function(cfg, data)
		return 'POST', cfg.url, {
			['Content-Type'] = 'application/json; charset=utf-8'
		}, json.encode({
			group = data.typ,
			body  = table.concat({data.content or '', data.from or '', data.me or ''}, '\n')
		})
	end,

	-- TelegramBot
	telegram = function(cfg, data)
		local content, from, me = data.content, data.from, data.me
		return 'POST', cfg.url:gsub('{token}', cfg.token), {
			['Content-Type'] = 'application/json; charset=utf-8'
		}, json.encode({
			parse_mode = 'MarkdownV2',
			chat_id    = tonumber(cfg.id),
			text       = table.concat({
				content and string.format('`%s`', content) or '',
				from 	and string.format('`%s`', from)    or '',
				me 		and string.format('||%s||', me)    or ''
			}, '\n')
		})
	end,

	-- Discord
	discord = function(cfg, data)
		return 'POST', string.format('%s%s', cfg.url, '?wait=true'), {
			['Content-Type'] = 'application/json; charset=utf-8',
		}, json.encode({
			username = data.typ,
			content  = table.concat({data.content or '', data.from or '', data.me or ''}, '\n')
		})
	end,

	-- 私人接口
	huaiot = function(cfg, data)
		return 'POST', string.format('%s/%s/', cfg.url, data.typ or 'msg'), {
			['Content-Type'] = 'application/json; charset=utf-8',
			['X-Auth'] = cfg.auth
		}, json.encode({
			['content'] = tostring(data.content),
			['from'] 	= tostring(data.from),
			['in'] 		= tostring(data.from),
			['to'] 		= tostring(data.me)
		})
	end

}

local rxbuf = zbuff.create(2048)	-- 缓冲区
local step  = 0 					-- 状态机

-- 打包邮件报文
local mail_pack = function(mail, from)
	local b64sb = b64e(mail.subject)
	local b64bd = b64e(mail.body)
	-- 每76字符切割为一行
	local bodys = {}
	for i = 1, #b64bd, 76 do
		bodys[#bodys + 1] = string.sub(b64bd, i, i + 75)
	end
	return table.concat({
		string.format('From: "%s" <%s>', rtos.bsp(), from.user),
		string.format('To: <%s>', mail.to),
		string.format('Subject: =?UTF-8?B?%s?=', b64sb),
		'MIME-Version: 1.0',
		'Content-Type: text/plain; charset=UTF-8',
		'Content-Transfer-Encoding: base64',
		'',
		table.concat(bodys, '\r\n'),
		'.'
	}, '\r\n')
end

-- SMTP回调
local function handle(mail, from, netc, event, param)
	-- 未知错误
	if param ~= 0 then
		sys.publish('sock_dis')
		return
	end

		if event == socket.LINK then
	elseif event == socket.ON_LINE then
		step = 0
		print('SMTP连接', '已建立', '等待服务器欢迎语')
	elseif event == socket.EVENT then
		-- 定义线性流程：{预期响应, 发送指令, 指令描述}
		local flow = {
			{'220', 'EHLO localhost'},
			{'250', 'AUTH LOGIN'},
			{'334', function() return b64e(from.user) end, '邮箱账户'},
			{'334', function() return b64e(from.pass) end, '邮箱密码'},
			{'235', 'MAIL FROM:<' .. from.user .. '>'},
			{'250', 'RCPT TO:<' .. mail.to .. '>'},
			{'250', 'DATA'},
			{'354', function() return mail_pack(mail, from) end, '邮件内容'},
			{'250', 'QUIT'}
		}
		rxbuf:del()
		socket.rx(netc, rxbuf)
		local resp = rxbuf:toStr(0, rxbuf:used())
		local curr = flow[step + 1]
		-- print('SMTP收到', resp)
		print('SMTP收到', resp:gsub('[\r\n]', ' '))
		if curr and resp:find(curr[1]) then
			local cmd = type(curr[2]) == 'function' and curr[2]() or curr[2]
			print('SMTP发送', curr[3] or cmd)
			socket.tx(netc, cmd .. '\r\n')
			step = step + 1
			-- 如果已经走到最后一步，结束流程
			if step == #flow then
				print('SMTP流程', '完成')
				sys.publish('sock_dis', true)
			end
		else
			-- 拦截非法响应，快速失败
			print('SMTP流程', '中断')
			sys.publish('sock_dis')
		end
		socket.wait(netc)
	elseif event == socket.TX_OK then
		socket.wait(netc)
	elseif event == socket.CLOSE then
		sys.publish('sock_dis')
	end
end

local fwd = {

	job_cnt = function()
		return #jobs
	end,

	add = function(data)

		-- 向队列添加HTTP任务
		local act = setting.http.actives or {}
		local cfg = setting.http.configs or {}
		for _, i in ipairs(act) do
			local method, url, headers, body = build[i](cfg[i], data)
			if method and url then
				jobs[#jobs + 1] = {
					msgtyp  = 'http',
					method  = method,
					url     = url,
					headers = headers,
					body    = body
				}
			end
		end

		-- 向队列添加SMTP任务
		local rc = setting.smtp.to or {}
		local sj = (data.content or ''):match('【(.-)】') or data.typ:upper()
		local bd = table.concat({data.content or '', '', data.from or '', data.me or ''}, '\n')
		for _, rp in ipairs(rc) do
			jobs[#jobs + 1] = {
				msgtyp  = 'smtp',
				subject = sj,
				body 	= bd,
				to 		= rp
			}
		end

		sys.publish('job_enq')
	end,

	init = {
		-- 构建HTTP通知清单
		http = function(cfg)
			local actives = {}
			local configs = {}
			for i, chl in pairs(cfg.service) do
				if chl.enabled == 1 then
					actives[#actives + 1] = i
					configs[i] = chl
				end
			end

			-- 默认User-Agent
			local function ua(str)
				if not str or str == '' then
					local fws = rtos.firmware():split('_')
					local hmt = string.format('%s_%s', hmeta.model(), hmeta.hwver())
					str = table.concat({fws[1], fws[2], hmt, hmeta.chip(), rtos.buildDate()}, '; ')
				end
				return string.format('Mozilla/5.0 (compatible; %s)', str)
			end

			-- 赋值
			local useropt = cfg.options or {}
			setting.http = {
				actives = actives,
				configs = configs,
				options = {
					retries = tonumber(useropt.retries) or 10,
					timeout = tonumber(useropt.timeout) or 20,
					ua 		= ua(useropt.ua)
				}
			}
			return actives
		end,

		-- 初始化SMTP
		smtp = function(cfg)
			local to = (type(cfg.to) == 'table' and #cfg.to > 0 and cfg.enabled == 1) and cfg.to or {}
			setting.smtp = {
				retries = tonumber(cfg.retries) or 10,
				from 	= cfg.from or {},
				to 	 	= to
			}
			return to
		end
	}
}

local function tryV6()
	-- IPv6可用，随机返回true，false
	-- IPv6离线，返回false
	return select(4, socket.localIP()) ~= nil and math.random(2) == 1
end

local run = {
	-- 运行HTTP
	http = function(data, fwd_id)
		sys.taskInit(function()
			local option = setting.http.options
			local method, url, headers, body, attempt = data.method, data.url, data.headers, data.body, data.attempt or 1
			headers['User-Agent'] = option.ua
			print('HTTP', string.format('%s/%s', attempt, option.retries), '内容', method, url, json.encode(headers), body)
			local code, _, res = http.request(method, url, headers, body, {
				timeout = 1000 * option.timeout,
				ipv6    = tryV6()
			}).wait()
			print('HTTP', '结果', code, res)
			if code ~= 200 and attempt < option.retries then
				data['attempt'] = attempt + 1
				jobs[#jobs + 1] = data
				-- 响应代码不是200时，加回队列，等待重试
				-- 重试未达上限，首次不计重试次数
			end
			sys.publish(fwd_id)
		end)
	end,

	-- 发送邮件
	smtp = function(mail, fwd_id)
		sys.taskInit(function()
			local attempt = mail.attempt or 1
			local retries = setting.smtp.retries
			local 	 from = setting.smtp.from

			print('SMTP', string.format('%s/%s', attempt, retries), '内容', json.encode(mail))

			local netc = socket.create(nil, function(netc, event, param)
				handle(mail, from, netc, event, param)
			end)

			socket.debug(netc, false)
			socket.config(netc, nil, nil, from.ssl == 1)
			sys.wait(100)

			local sent = false
			local succ = socket.connect(netc, from.host, from.port, tryV6())
			if succ then
				-- print('操作次数', attempt)
				local _, ok = sys.waitUntil('sock_dis', 1000 * 20)
				sent = ok
			end

			if not sent and attempt < retries then
				mail['attempt'] = attempt + 1
				jobs[#jobs + 1] = mail
			end

			socket.close(netc)
			socket.release(netc)

			print('SMTP连接', '断开')
			print('邮件发送', not sent and '失败' or '成功')
			sys.publish(fwd_id)
		end)
	end
}

-- 队列处理
sys.taskInit(function()
	sys.waitUntil('IP_READY')
	local seq = 1
	while true do
		collectgarbage('collect')
		local job = table.remove(jobs, 1)
		if not job then
			sys.waitUntil('job_enq')
		else
			local fwd_id = 'fwd_id_' .. seq
			run[job.msgtyp](job, fwd_id)
			sys.waitUntil(fwd_id, 1000 * 60 * 10)
			print('队列', fwd_id, '结束，剩余', #jobs, '\n\n')
			sys.wait(200)
			seq = seq + 1
		end
	end
end)

return fwd

--[[接口文档

飞书 安全设置仅支持 "自定义关键词"。关键词为你的手机号及nil，此为可选设置
钉钉 安全设置仅支持 "自定义关键词"。关键词为你的手机号及nil

当操作涉及时间时，模组无法可靠提供此值，可能造成服务不可用

https://developer.work.weixin.qq.com/document/path/91770                                  微信
https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot#5a997364                飞书
https://open.dingtalk.com/document/development/custom-robots-send-group-messages          钉钉
https://bark.day.app/#/tutorial                                                           Bark
https://core.telegram.org/bots/api#sendmessage                                            Telegram
https://docs.discord.com/developers/resources/webhook#execute-webhook                     Discord

https://workers.999909.xyz/bark/
https://workers.999909.xyz/telegram/
https://workers.999909.xyz/discord/
https://workers.999909.xyz/iot/api/obj/


-- table中不符合规范的键名需要使用['键名']，反之省略
-- 可以始终以['键名']格式书写，以应对不确定的情况

--]]