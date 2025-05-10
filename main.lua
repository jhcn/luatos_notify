PROJECT = 'Air780EP_SMS'                    -- 项目名，不能有空格
VERSION = '0.3.12'                          -- 版本号，不能有空格

BARK_URL = 'https://api.day.app/push'       -- bark api
BARK_KEY = ''                               -- bark口令

log.setLevel(1)                             -- 输出日志级别，SILENT,DEBUG,INFO,WARN,ERROR,FATAL 0,1,2,3,4,5
log.style(1)                                -- 日志风格

_G.sys     = require 'sys'
_G.sysplus = require 'sysplus'

if wdt then                                 --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)                          --初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)      --3s喂一次狗
end

pm.force(pm.IDLE)                           -- 强制进入指定的休眠模式

mobile.config(mobile.CONF_STATICCONFIG, 1)  -- 静态网络优化，wiki显示需要在飞行模式下设置。所以不一定有效喔
mobile.config(mobile.CONF_QUALITYFIRST, 2)  -- 网络质量优先，wiki显示需要在飞行模式下设置。所以不一定有效喔

mobile.ipv6(false)                          -- IPv6开关，true/false
mobile.syncTime(false)                      -- 不同步基站时间
mobile.setAuto(10000, 30000, 5)             -- SIM脱离后自动恢复/ms，搜索周围小区信息周期/ms，超时/s

local rb_sw     = 24                         -- 设置定时重启时间(单位:小时)，0不重启
local led_pin   = 27                         -- 设置led gpio 780填27 724填1
local led_sw    = gpio.setup(led_pin, 1)     -- led 电平 1/0 高/低
local net_ok    = false                      -- 联网状态
local sms_reply = false                      -- 设置有电话呼入时回复短信，true/false
local net_boom  = 0                          -- 记录断网次数，为0时则开机后未断网

-- 定时重启
if rb_sw > 0 then
    sys.timerStart(pm.reboot, 1000 * 60 * 60 * rb_sw)
end

-- 定义运营商PLMN清单
-- 返回运营商名称
function comName()
    local PLMN = string.sub(mobile.imsi(mobile.simid()), 1, 5)
    local list = {
        ['46000'] = '中国移动',
        ['46001'] = '中国联通',
        ['46011'] = '中国电信',
        ['46015'] = '中国广电'
    }
    return list[PLMN] or '未知'
end

-- ICCID转手机号
-- 返回手机号码
function simNumber()
    local simId = mobile.simid()
    local toNum = {
        ['89860000000000000000'] = '18500000000',
        ['89860000000000000001'] = '18600000000'
    }
    return toNum[mobile.iccid(simId)] or mobile.number(simId) or '未知'
end

-- cpu温度
function adcCPU()
    adc.open(adc.CH_CPU)
    local temp = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    return string.format('%.2f°C', temp / 1000)
end

-- vbus电压
function adcVBUS()
    adc.open(adc.CH_VBAT)
    local temp = adc.get(adc.CH_VBAT)
    adc.close(adc.CH_VBAT)
    return string.format('%.2fV', temp / 1000)
end

-- SIM卡就绪
sys.subscribe('SIM_IND',
    function(status, value)
        if status == 'RDY' then
            log.info('SIM卡就绪', status)
        end
    end
)

-- led灯操作，最终熄灭
sys.subscribe('led_tog',
    function(n)
        sys.taskInit(function()
            led_sw(0)
            for _ = 1, n do
                gpio.toggle(led_pin)
                sys.wait(100)
            end
            led_sw(0)
        end)
    end
)

-- HTTP通知函数
-- table中不符合规范的键名需要使用['键名']，反之省略
-- 可以始终以['键名']格式书写，以应对不确定的情况
sys.subscribe('notify',
    function(type, froms, n)
        sys.publish('led_tog', 10)
        sys.taskInit(function()
            froms['device_key'] = BARK_KEY
            local url    = BARK_URL
            local body   = json.encode(froms)
            local header = {
                ['Content-Type'] = 'application/json; charset=utf-8',
                ['User-Agent']   = string.format('Mozilla/5.0 (%s; %s; %s)', rtos.bsp(), rtos.firmware(), rtos.buildDate())
            }
            local _, _, _, ipv6 = socket.localIP()
            local opt = {
                ['timeout'] = 8000,
                ['debug']   = false,
                ['ipv6']    = (ipv6 ~= nil)
            }
            local res_code, _, res_body = http.request('POST', url, header, body, opt).wait()
            if res_code ~= 200 and n < 10 then
                sys.wait(500)
                sys.publish('notify', type, froms, n + 1)
            end
            log.info(body, json.encode(header), json.encode(opt), '重试次数', n - 1)
            log.info(url, res_code, res_body)
        end)
    end
)

-- 双栈网络会发布2次IP_READY，需在首次IP_READY存储其状态，避免重复操作
-- 其实用一个string.format就能处理好content，但这样做会造成代码又臭又长
sys.subscribe('net_ok',
    function()
        if net_boom < 1 then
            socket.setDNS(nil, 1, '180.184.2.2')
            socket.setDNS(nil, 2, '223.5.5.5')
            local bsp   = hmeta.model()
            local froms = {
                ['title'] = string.format('%s设备开机通知', bsp),
                ['body']  = table.concat(
                    {
                        string.format('手机号 %s', simNumber()),
                        string.format('IMEI %s', mobile.imei()),
                        string.format('IMSI %s', mobile.imsi()),
                        string.format('小区 %s', mobile.eci()),
                        string.format('信号 %sdBm', mobile.rsrp()),
                        string.format('温度 %s', adcCPU()),
                        string.format('电压 %s', adcVBUS()),
                        string.format('固件版本 %s', rtos.version()),
                        string.format('接入网络 %s', comName()),
                        string.format('信号强度 %s', mobile.csq()),
                        string.format('TAC %s', mobile.tac())
                    }, '\r\n'
                )
            }
            sys.publish('notify', 'msg', froms, 1)
        end
        log.info('net_ok')
    end
)

-- 已联网
sys.subscribe('IP_READY',
    function(ip, adapter)
        if not net_ok then
            net_ok = true
            sys.publish('net_ok')
        end
    end
)

-- 处理被叫时自动回复短信和收到发送短信指令事件
-- 由电话事件触发时，回复短信前检测呼入电话号码是否为私人号码(长度11位 首位 1，二位 3-9)
sys.subscribe('send_sms',
    function(ref, num, txt)
        if ref == 'call' then
            if string.len(num) == 11 and string.match(num, "^1[3-9][%d]") then
                sms.send(num, txt)
            end
        elseif ref == 'ctrl' then
            sms.send(num, txt)
        end
    end
)

-- 收到短信
-- 判定时短信指令的条件要满足以下全部条件
-- 1，数组一定是3个值
-- 2，第一个值必须是SMS
-- 3，第二个值必须是数字
sys.subscribe('SMS_INC', function(num, txt)
    local froms = {
        ['title'] = num,
        ['body']  = string.format('%s\r\n\r\n%s', txt, simNumber())
    }
    local parts = {}
    for part in string.gmatch(txt, "([^##]+)") do
        table.insert(parts, part)
    end
    if #parts == 3 and parts[1] == 'SMS' and (tonumber(parts[2]) ~= nil) then
        sys.publish('send_sms', 'ctrl', parts[2], parts[3])
        log.info('短信指令', json.encode(parts))
    end
    sys.publish('notify', 'sms', froms, 1)
end)

-- 语音功能
local cc_in = false
local cc_zh = {
    ['READY']            = '功能就绪',
    ['PLAY']             = '有人致电',
    ['INCOMINGCALL']     = '正在振铃',
    ['DISCONNECTED']     = '电话挂断',
    ['ANSWER_CALL_DONE'] = '电话接通'
}
sys.subscribe('CC_IND', function(status)
    local lastNum = cc.lastNum()
    if status == 'DISCONNECTED' then
        cc_in = false
    elseif status == 'READY' then
        cc.init(0)
    elseif status == 'INCOMINGCALL' then
        if not cc_in then
            cc_in = true
            local froms = {
                ['body'] = string.format('%s 致电 %s', lastNum, simNumber)
            }
            sys.publish('notify', 'call', froms, 1)
            if sms_reply then
                local sms_txt = string.format('%s，很抱歉无法及时处理您的来电，您可短信给我留言，我会尽快与您联系。这是一条自动回复短信', lastNum)
                sys.publish('send_sms', 'call', lastNum, sms_txt)
            end
        end
    end
    log.info('电话功能', cc_zh[status] or status, lastNum)
end)

-- 处理联网异常
sys.subscribe('net_boom',
    function(msg)
        mobile.reset()
        log.info(msg)
    end
)

-- 检测联网状态
sys.timerLoopStart(function()
    if not net_ok then
        sys.publish('net_boom', '联网异常')
    end
end, 1000 * 60)

-- 断网
sys.subscribe('IP_LOSE',
    function(adapter)
        net_boom = net_boom + 1
        net_ok   = false
        sys.publish('net_boom', '已断网', adapter)
    end
)

-- 定时发布led_tog实现闪烁
-- sys.timerLoopStart(function()
--     sys.publish('led_tog', 1)
-- end, 2000)

sys.run()