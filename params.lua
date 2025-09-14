local params = {}
local    chl = config.notify.http.channel

-- 微信
function params.weCom(type, from, num, content)
    local text = {
        call = string.format('%s致电%s', from, num),
        sms  = string.format('%s发来短信： %s 收信方：%s', from, content, num),
        msg  = content
    }
    if not text[type] then return end
    return 'POST', chl.weCom.url, {
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode({msgtype = 'text', text = {content = text[type]}})
end

-- 飞书
function params.feishu(type, from, num, content)
    local text = {
        call = string.format('%s致电%s', from, num),
        sms  = string.format('%s发来短信： %s 收信方：%s', from, content, num),
        msg  = content
    }
    if not text[type] then return end
    return 'POST', chl.feishu.url, {
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode({msg_type = 'text', content = {text = text[type]}})
end

-- bark
function params.bark(type, from, num, content)
    local params = {
        call = {body = string.format('%s 致电 %s', from, num)},
        sms  = {body = content, title = from},
        msg  = {body = content, title = num}
    }
    if not params[type] then return end
    return 'POST', chl.bark.url, {
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode(params[type])
end

-- TelegramBot
function params.TelegramBot(type, from, num, content)
    local  cfg = chl.TelegramBot
    local text = {
        call = string.format('`%s` `致电` ||%s||', from, num),
        sms  = string.format('`%s`\r\n ||%s||\r\n`%s`', from, num, content),
        msg  = string.format('`%s`', content)
    }
    if not text[type] then return end
    return 'POST', string.format('%s/bot%s/sendMessage', cfg.url, cfg.token), {
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode({chat_id = cfg.id, text = text[type], parse_mode = 'MarkdownV2'})
end

-- 私人接口
function params.huaiot(type, from, num, content)
    local    cfg = chl.huaiot
    local params = {
        call = {['in'] = from, ['to'] = num},
        sms  = {['content'] = content, ['from'] = from, ['to'] = num},
        msg  = {['content'] = content, ['from'] = num}
    }
    return 'POST', string.format('%s/%s/', cfg.url, type), {
        ['Host']         = cfg.host,
        ['X-Auth']       = cfg.auth,
        ['Content-Type'] = 'application/json; charset=utf-8'
    }, json.encode(params[type])
end

return params

--[[接口文档

    飞书，    https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot
    微信，    https://developer.work.weixin.qq.com/document/path/91770
    bark，    https://bark.day.app/#/tutorial
    Telegram，https://core.telegram.org/bots/api#sendmessage

--]]