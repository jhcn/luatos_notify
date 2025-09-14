return {
    network = {
        dns = {
            '180.184.2.2',
            '223.5.5.5'
        },
        IPv6 = 0
    },
    notify = {
        http = {
            options = {
                timeout = 8,
                retry   = 10,
                ua      = nil
            },
            channel = {
                weCom = {
                    enable = 0,
                    url    = 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx'
                },
                feishu = {
                    enable = 0,
                    url    = 'https://open.feishu.cn/open-apis/bot/v2/hook/****',
                },
                bark = {
                    enable = 0,
                    url    = 'https://api.day.app/xxx'
                },
                TelegramBot = {
                    enable = 1,
                    url    = 'https://abcdefghijklmn.eu.org/telegram',
                    token  = '8421296570:AAH9ZfkTvN2cXelej3Ms460n1ZMQZAxmASg',
                    id     = 559928607
                },
                huaiot = {
                    enable = 1,
                    url    = 'http://192.168.1.1/obj',
                    host   = 'api.iot.test.xyz',
                    auth   = 'xxx'
                }
            }
        },
        smtp = {
            server = '',
            port   = '',
            tls    = '',
            user   = '',
            pwd    = '',
            to = {
                'test@test.cn'
            }
        }
    },
    call = {
        accept = {
            L = 0,  -- 座机
            M = 1   -- 手机
        },
        reply = {
            sms = {
                enable  = 1,
                content = '%s，很抱歉无法及时处理您的来电，您可短信给我留言，我会尽快与您联系。这是一条自动回复短信'
            }
        }
    },
    sim = {
        ['89860115840501500001'] = {
            num = '13900000001'
        },
        ['89860115840501500002'] = {
            num = '13900000002'
        },
        ['89860115840501500003'] = {
            num = '13900000003'
        }
    },
    system = {
        power = {
            notify = 1,
            usb    = 1,
            reboot = 8
        },
        led = {
            network = {
                gpio = 27
            },
            event = {
                gpio  = 27,
                total = 5,
                wait  = 60
            }
        },
        ctrl = {
            '000'
        }
    }
}

--[[使用说明
    sim     此功能可设置iccid对应手机号，对于未写入手机号的sim卡非常有效。
    ctrl    可控制模块的号码，留空代表任意号码，不可被控制可填不存在的号码如000
    reboot  定时重启模块，单位小时，0则不重启


--]]
