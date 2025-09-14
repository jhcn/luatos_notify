PROJECT = 'Air780EP_SMS'                          -- 项目名，不能有空格
VERSION = '0.3.75'                                -- 版本号，不能有空格

log.setLevel(2)                                   -- 输出日志级别，SILENT，DEBUG，INFO，WARN，ERROR，FATAL 0,1,2,3,4,5
log.style(1)                                      -- 日志风格

-- 全局变量
_G.sys     = require 'sys'
_G.sysplus = require 'sysplus'

_G.config  = require 'config'                     -- config
_G.led     = require 'led'                        -- led操作

-- 局部变量
local     model = require 'model'                    -- 私有adc
local       sim = require 'sim'                      -- 私有sim
local    params = require 'params'                   -- 封装http参数
local subscribe = require 'subscribe'                -- 订阅消息

-- 看门狗
if wdt then
    wdt.init(1000 * 9)
    sys.timerLoopStart(wdt.feed, 1000 * 3)
end

-- 异常日志上报，关闭
if errDump then
    errDump.config(false)
end

-- pm.ioVol(pm.IOVOL_ALL_GPIO, 1800)                 -- 所有GPIO高电平时电压
pm.force(pm.NONE)                                 -- 不休眠
pm.power(pm.GPS, false)                           -- 关闭gps电源
pm.power(pm.GPS_ANT, false)                       -- 关闭gps天线电源
pm.power(pm.CAMERA, false)                        -- 关闭camera电源

mobile.config(mobile.CONF_STATICCONFIG, 1)        -- 静态网络优化，需在飞行模式下设置
mobile.config(mobile.CONF_QUALITYFIRST, 2)        -- 网络质量优先，需在飞行模式下设置

mobile.ipv6(config.network.IPv6 == 1)             -- IPv6开关，true/false
mobile.syncTime(false)                            -- 不同步基站时间
mobile.setAuto(1000 * 10, 1000 * 30, 5)           -- SIM脱离后自动恢复/ms，搜索周围小区信息周期/ms，超时/s

-- 状态对应中文释义
local statusMap = {
    sim = {
        ['RDY']        = '已经就绪',
        ['NORDY']      = '状态异常',
        ['SIM_PIN']    = '需要验证',
        ['GET_NUMBER'] = '获取号码'
    },
    cc = {
        ['READY']            = '功能就绪',
        ['PLAY']             = '有人致电',
        ['INCOMINGCALL']     = '正在振铃',
        ['ANSWER_CALL_DONE'] = '电话接通',
        ['DISCONNECTED']     = '对方挂断',
        ['HANGUP_CALL_DONE'] = '主动挂断'
    }
}

local network = {
    onl = false,    -- 联网状态
    dis = 0         -- 断网次数
}

-- 判定手机号
function isMobile(num)
    return (#num == 11 and num:match('^1[3-9]'))
end

-- 重置LTE协议栈
-- 此操作会使底层重发SIM_IND消息
sys.subscribe('ip_reset', function(...)
    if not network.onl then return end
    network = {
        onl = false,
        dis = network.dis + 1
    }
    mobile.reset()
    log.info('IP网络', '重置原因', ..., json.encode(network))
end)

-- 等待联网
sys.subscribe('ip_wait', function()
    sys.taskInit(function()
        local result = sys.waitUntil('IP_READY', 1000 * 60)
        if not result then
            network.onl = true
            sys.publish('ip_reset', '超时未联网')
        end
        log.info('IP网络', '等待联网', (result and '成功联网' or '超时'))
    end)
end)

-- 断网
sys.subscribe('IP_LOSE', function()
    sys.publish('ip_reset', '断网')
end)

-- SIM卡就绪
sys.subscribe('SIM_IND', function(status, value)
    if status == 'RDY' then
        sys.publish('ip_wait')
    end
    log.info('SIM卡', statusMap.sim[status] or '未知', status, value)
end)

-- 执行HTTP请求
-- table中不符合规范的键名需要使用['键名']，反之省略
-- 可以始终以['键名']格式书写，以应对不确定的情况
local http_opt = config.notify.http.options
sys.subscribe('http_notify', function(method, url, headers, body, n)

    -- HTTP重试达上限则退出
    if n > http_opt.retry then return end

    sys.taskInit(function()
        log.info('HTTP', url, json.encode(headers), body, string.format('%s/%s', n, http_opt.retry))
        local _, _, _, ipv6 = socket.localIP()
        local  code, _, res = http.request(method, url, headers, body, {
            timeout = http_opt.timeout * 1000,
            debug   = false,
            ipv6    = (ipv6 ~= nil)
        }).wait()
        if code == 200 then
            log.info('HTTP', code, res)
        else
            log.info('HTTP', code, 'error!!!')
            sys.wait(3000)
            sys.publish('http_notify', method, url, headers, body, n + 1)
        end
    end)

end)

-- 构建可控制模块的号码名单
local ctrl = {}
if #config.system.ctrl > 0 then
    for _, v in pairs(config.system.ctrl) do
        ctrl[v] = true
    end
end

-- 构建通知通道清单
local http_chl = {}
for key, value in pairs(config.notify.http.channel) do
    if value.enable == 1 then
        table.insert(http_chl, key)
    end
end

-- 短信回复来电号码满足以下全部条件
-- 1，长度11位
-- 2，首位1，第二位介于3-9
-- 3，config开启
sys.subscribe('sms_build_call', function(from)
    local cfg = config.call.reply.sms
    if isMobile(from) and cfg.enable == 1 then
        sys.publish('sms_send', from, string.format(cfg.content, from))
    end
end)

-- 满足以下条件其一可短信控制本模块
-- 1，名单为空
-- 2，来信号码存在于名单内
sys.subscribe('sms_build_sms', function(from, content)
    if #config.system.ctrl < 1 or ctrl[from] then

        if not content:find('##', 1, true) then
            return
        end

        local parts = {}
        for part in content:gmatch('([^##]+)') do
            table.insert(parts, part)
        end

        -- 满足以下全部条件的短信内容将判定为短信发送指令
        -- 1，数组值不少于3个
        -- 2，第一个值是SMS
        -- 3，第二个值是数字
        if #parts > 2 and (parts[1]:lower() == 'sms') and tonumber(parts[2]) then
            rTxt = content:sub(#parts[1] + #parts[2] + 5)
            sys.publish('sms_send', parts[2], rTxt)
        end

    end
end)

-- 未设置User-Agent则使用预设值
-- 组装HTTP参数，发布执行HTTP请求的消息
local userAgent = http_opt.ua or string.format('Mozilla/5.0 (%s; %s; %s; %s) %s', model.os(), model.bsp(), model.chip(), model.hw(), model.build())
sys.subscribe('notify_build', function(type, from, content)

    -- 发布供回复短信功能订阅的消息
    sys.publish('sms_build_' .. type, from, content)

    -- 无启用的HTTP通道则退出
    if #http_chl < 1 then return end

    sys.taskInit(function()
        local num = (type == 'msg') and model.bsp() or sim.num()
        for _, value in ipairs(http_chl) do
            local method, url, headers, body = params[value](type, from, num, content)
            headers['User-Agent'] = userAgent
            sys.publish('http_notify', method, url, headers, body, 1)
        end
    end)

end)

-- 网络就绪
sys.subscribe('IP_READY', function(...)

    -- IP_READY会在双栈网络中重复出现
    -- IP_READY首次出现时标记已联网
    if not network.onl then

        log.info('IP网络', '成功联网', ...)
        log.info('IP网络', '网卡详情', socket.localIP())

        network.onl = true

        -- 设置DNS
        local dns = config.network.dns
        if #dns < 1 then return end
        for i, ns in ipairs(dns) do
            socket.setDNS(nil, i, ns)
            log.info('DNS', i, ns)
        end

    end

    -- 开机通知
    if config.system.power.notify ~= 1 then return end

    log.info('通知通道', json.encode(http_chl))
    log.info('项目详情', PROJECT, VERSION)

    config.system.power.notify = 0

    -- 构建通知内容
    -- 其实用一个string.format就能处理好content
    -- 但会造成代码又臭又长
    local content = {
        string.format('%s设备开机通知', model.bsp()),
        string.format('温度 %s', model.temp()),
        string.format('电压 %s', model.vbat()),
        string.format('IMEI %s', model.imei()),
        string.format('手机号 %s', sim.num()),
        string.format('网络 %s', sim.com()),
        string.format('PLMN %s', sim.plmn()),
        string.format('IMSI %s', mobile.imsi()),
        string.format('ICCID %s', mobile.iccid()),
        string.format('信号 %s dBm', mobile.rsrp())
    }

    sys.publish('notify_build', 'msg', '', table.concat(content, '\r\n'))

end)

-- 收到短信
sys.subscribe('SMS_INC', function(from, txt)
    sys.publish('notify_build', 'sms', from, txt)
end)

-- 语音功能
local call = {
    incoming = false,   -- 初始化被叫状态
    count    = 0        -- 振铃次数，挂断后重置为0
}
sys.subscribe('CC_IND', function(status)

    local  cfg = config.call.accept
    local from = cc.lastNum()

        if status == 'READY' then cc.init(0)
    elseif status == 'ANSWER_CALL_DONE' then cc.hangUp()
    elseif status == 'DISCONNECTED' or status == 'HANGUP_CALL_DONE' then call = {incoming = false, count = 0}
    elseif status == 'INCOMINGCALL' then

        -- 首次振铃
        if not call.incoming then
            sys.publish('notify_build', 'call', from, '')
        end

        -- 更新状态
        call = {
            incoming = true,
            count    = call.count + 1
        }

        -- 第三次振铃依条件决定是否接听电话
        if call.count == 3 then
            -- cfg.M == 1，接听手机号致电
            -- cfg.L == 1，接听非手机致电
            if (isMobile(from) and cfg.M == 1) or cfg.L == 1 then
                cc.accept()
            end
        end

    end
    log.info('通话', statusMap.cc[status] or status, from)

end)

-- 定时内存回收
sys.timerLoopStart(sys.publish, 1000 * 30, 'memory_clean')

-- 电源设置
local power = config.system.power

-- 定时重启模块
if power.reboot > 0 then
    sys.timerStart(pm.reboot, 1000 * 60 * 60 * power.reboot)
end

-- USB电源
if power.usb ~= 1 then
    sys.timerStart(pm.power, 1000 * 60 * 2, pm.USB, false)
end

sys.run()