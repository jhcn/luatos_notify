-- 内存回收
sys.subscribe('memory_clean', function()
    collectgarbage('collect')
end)

-- 由HTTP触发内存回收
sys.subscribe('http_build', function()
    sys.publish('memory_clean')
end)

-- LED闪烁，最终熄灭
sys.subscribe('http_notify', function()
    led.event()
end)

-- 联网，LED灭
sys.subscribe('IP_READY', function()
    led.network(0)
end)

-- 断网，LED亮
sys.subscribe('IP_LOSE', function()
    led.network(1)
end)

-- 发送短信
sys.subscribe('sms_send', function(num, txt)
    log.info('发出短信', num, txt)
    sms.send(num, txt)
end)