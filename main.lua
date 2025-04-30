-- 由于蜂窝网络的不稳定性可能造成数据不准确，滞后性
-- 应该避免传送非必要参数

PROJECT = 'Air780EP_SMS'
VERSION = '0.3.11'

-- bark密钥
local bark_key = ''

-- SILENT,DEBUG,INFO,WARN,ERROR,FATAL 0,1,2,3,4,5
log.setLevel(2) -- 输出日志级别
log.style(1)    -- 日志风格

log.info(PROJECT, VERSION)

_G.sys     = require 'sys'
_G.sysplus = require 'sysplus'

if wdt then                             --添加硬狗防止程序卡死，在支持的设备上启用这个功能
    wdt.init(9000)                      --初始化watchdog设置为9s
    sys.timerLoopStart(wdt.feed, 3000)  --3s喂一次狗
end

pm.force(pm.IDLE)                           -- 强制进入指定的休眠模式
-- pm.power(pm.WORK_MODE, 0)                -- 功耗模式，1,性能 2,平衡 3,低功耗
-- socket.dft(socket.LWIP_ETH)              -- 设置默认
mobile.config(mobile.CONF_USB_ETHERNET, 0)  -- 禁用USB网卡
mobile.config(mobile.CONF_STATICCONFIG, 1)  -- 静态网络优化
mobile.config(mobile.CONF_QUALITYFIRST, 2)  -- 网络质量优先
mobile.ipv6(false)                          -- IPv6开关，true/false
mobile.syncTime(false)                      -- 不同步基站时间
mobile.setAuto(10000, 30000, 5)             -- SIM检测(ms)，定时获取小区信息(ms)，搜索小区超时时间(s,建议小于8s)

sys.timerStart(pm.reboot, 1000 * 60 * 60 * 12)  -- 定时重启,单位ms

local led_pin  = 27                       -- 设置led gpio为27
local LED      = gpio.setup(led_pin, 1)   -- 为输出,且初始化电平为高,且启用内部上拉
local net_ok   = false                    -- 联网状态
local net_boom = 0                        -- 网络是否断开，大于0则已断网。用于判定断网还是开机

-- 运营商名称
function comName()
    -- 运营商PLMN清单
    local com_code = {
        ['46000'] = '中国移动',
        ['46001'] = '中国联通',
        ['46011'] = '中国电信',
        ['46015'] = '中国广电'
    }
    local PLMN = string.sub(mobile.imsi(mobile.simid()), 1, 5)
    return com_code[PLMN] or '未知'
end

-- 获取手机号码
-- ICCID转手机号
function simNumber()
    local toNum = {
        ['89860000000000000001'] = '17000000000',
        ['89860000000000000002'] = '19100000000',
        ['89860000000000000003'] = '17300000000'
    }
    return toNum[mobile.iccid(0)] or mobile.number(0)
end

-- led闪烁，最终熄灭
function led()
    sys.taskInit(function()
        for i = 1, 10 do
            gpio.toggle(led_pin)
            sys.wait(100)
        end
        LED(0)
    end)
end

-- cpu温度
function adcCPU()
    adc.open(adc.CH_CPU)
    local temp = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    return string.format('%.2f', temp / 1000) .. '°C'
end

-- vbus电压
function adcVBUS()
    adc.open(adc.CH_VBAT)
    local temp = adc.get(adc.CH_VBAT)
    adc.close(adc.CH_VBAT)
    return string.format('%.2f', temp / 1000) .. 'V'
end

-- http通知函数
-- table中不符合规范的键名需要使用['键名']，反之省略
function notify(froms)
    sys.taskInit(function()
        froms['device_key'] = bark_key
        local timeout = 8000
        local url     = 'https://43.155.109.24/push'
        local body    = json.encode(froms)
        local header  = {
            ['Host']         = 'api.day.app',
            ['Content-Type'] = 'application/json',
            ['User-Agent']   = string.format('Mozilla/5.0 (%s; %s; build/%s)', rtos.bsp(), rtos.firmware(), rtos.buildDate())
        }
        local _, _, _, ipv6 = socket.localIP()
        local opt = {
            timeout = timeout,
            ipv6    = (ipv6 ~= nil)
        }
        for i = 1, 10 do
            led()
            log.info(body, json.encode(header), json.encode(opt), '发送次数', i)
            local res_code, res_headers, res_body = http.request('POST', url, header, body, opt).wait()
            log.info(url, res_code, res_body)
            if res_code == 200 then
                break
            else
                sys.wait(timeout) 
            end
        end
    end)
end

-- 收到短信,设置回调函数。号码，内容，时间
sms.setNewSmsCb(function(num, txt, metas)
    local froms = {
        title = num,
        body  = txt .. "\r\n\r\n" .. simNumber()
    }
    notify(froms)
end)

-- 已联网
sys.subscribe('IP_READY',
    function(ip, adapter)
        sys.taskInit(function()
            LED(0)
            sys.wait(100)
            if not net_ok then
                net_ok = true
                sys.publish('net_ok')
            end
        end)
    end
)

-- 双栈网络会发布2次IP_READY，需在首次IP_READY存储其状态，避免重复操作
sys.subscribe('net_ok', function()
    sys.taskInit(function()
        log.info('net_ok')
        socket.setDNS(nil, 1, '180.184.2.2')
        socket.setDNS(nil, 2, '223.5.5.5')
        if net_boom < 1 then
            log.info('power on')
            local froms = {
                title = rtos.bsp() .. '开机通知',
                body  = string.format("IMEI %s\r\n固件版本%s\r\n手机号%s\r\n温度%s\r\n电压 %s\r\n接入网络 %s\r\n信号强度%s\r\n信号%s\r\nIMSI %s\r\n小区id %s\r\nTAC %s", mobile.imei(), rtos.version(), simNumber(), adcCPU(), adcVBUS(), comName(), mobile.csq(), mobile.rsrp(), mobile.imsi(), mobile.eci(), mobile.tac())
            }
            notify(froms)
        end
    end)
end)

-- 断网触发
sys.subscribe('IP_LOSE',
    function(adapter)
        LED(1)
        net_boom = net_boom + 1
        net_ok   = false
        log.info('已断网')
        mobile.reset()
    end
)

sys.subscribe('SIM_IND',
    function(status, value)
        if status == 'RDY' then
            log.info('sim_ojbk')
        end
    end
)

local call_in = false
sys.subscribe("CC_IND", function(status)
    if status == 'READY' then
        log.info('电话功能', status)
    end
    if status == 'INCOMINGCALL' then
        if not call_in then
            call_in = true
            local lastNum = cc.lastNum()
            local froms = {
                title = '新的来电',
                body  = lastNum .. ' -> ' .. simNumber()
            }
            sms.send(lastNum, lastNum .. '，很抱歉无法及时处理您的来电，您可短信给我留言，我会尽快与您联系。这是一条自动回复短信')
            notify(froms)
        end
        log.info('有电话呼入，正在振铃')
    end
    if status == 'DISCONNECTED' then
        call_in = false
        log.info('电话挂断')
    end
end)

-- 定时监测联网状态
sys.timerLoopStart(function()
    if not net_ok then
        mobile.reset()
    end
end, 1000 * 60)

sys.run()