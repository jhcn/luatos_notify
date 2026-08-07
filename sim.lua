local    sim = {}
local     id = mobile.simid()
local simMap = {
    com = {
        ['46000'] = '中国移动',
        ['46001'] = '中国联通',
        ['46004'] = '中国移动',
        ['46007'] = '中国移动',
        ['46008'] = '中国移动',
        ['46011'] = '中国电信',
        ['46015'] = '中国广电'
    }
}

-- PLMN
-- 虚拟运营商无独立PLMN
function sim.plmn()
    local IMSI = mobile.imsi()
    return IMSI and IMSI:sub(1, 5)
end

-- 运营商名称
function sim.com()
    local ICCID = mobile.iccid(id)
    local   cfg = config.sim[ICCID]
    if (cfg and cfg.com) then
        return cfg.com
    end
    local IMSI = mobile.imsi()
    local PLMN = IMSI and IMSI:sub(1, 5)
    return PLMN and simMap.com[PLMN]
end

-- 手机号
function sim.num()
    local ICCID = mobile.iccid(id)
    local   cfg = config.sim[ICCID]
    return (cfg and cfg.num) or mobile.number(id) or mobile.number()
end

return sim
