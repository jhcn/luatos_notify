local    sim = {}
local     id = mobile.simid()
local simMap = {
    com = {
        ['46000'] = '中国移动',
        ['46001'] = '中国联通',
        ['46004'] = '中国移动',
        ['46011'] = '中国电信',
        ['46015'] = '中国广电'
    }
}

-- PLMN
-- 虚拟运营商无独立PLMN
function sim.plmn()
    local IMSI = mobile.imsi()
    local PLMN = IMSI and IMSI:sub(1, 5)
    return PLMN
end

-- 运营商名称
function sim.com()
    local IMSI = mobile.imsi()
    local PLMN = IMSI and IMSI:sub(1, 5)
    local  COM = PLMN and simMap.com[PLMN]
    return PLMN and simMap.com[PLMN]
end

-- 手机号
function sim.num()
    local ICCID = mobile.iccid(id)
    local   NUM = (config.sim[ICCID] and config.sim[ICCID].num) or mobile.number() or mobile.number(id)
    return NUM
end

return sim