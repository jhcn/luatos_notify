local model = {}

-- cpu温度
function model.temp()
    adc.open(adc.CH_CPU)
    local x = adc.get(adc.CH_CPU)
    adc.close(adc.CH_CPU)
    return string.format('%.2f', x / 1000)
end

-- vbus电压
function model.vbat()
    adc.open(adc.CH_VBAT)
    local x = adc.get(adc.CH_VBAT)
    adc.close(adc.CH_VBAT)
    return string.format('%.2f', x / 1000)
end

-- 固件
function model.os()
    return rtos.firmware()
end

-- 模组名称
function model.bsp()
    return hmeta.model()
end

-- 硬件版本号
function model.hw()
    return hmeta.hwver()
end

-- 原始芯片型号
function model.chip()
    return hmeta.chip()
end

-- 固件编译日期
function model.build()
    local x = rtos.buildDate()
    return x
end

-- SN
function model.sn()
    return mobile.sn()
end

-- IMEI
function model.imei()
    return mobile.imei()
end

return model