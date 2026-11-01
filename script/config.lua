return {
	usb = {
		dpdm = 1,
		net  = 0
	},
	time = {
		sync = 1,
		sntp = {
			enabled = 1,
			server  = {'time.apple.com', 'time.windows.com', 'ntp.aliyun.com'}
		}
	},
	network = {
		IPv6 = 1,
		dns  = {'180.184.2.2', '223.6.6.6'}
	},
	io = {
		default = {
			pull = 0,
			vol  = 3300
		},
		led = {
			{
				role = 'network',
				gpio = 30,
				pull = 0
			},
			{
				role = 'event',
				gpio = 27,
				pull = 0
			}
		}
	},
	system = {
		auto = {
			reboot = 24
		},
		log = {
			level = 2,
			style = 1
		},
		admin = {'13900000001', '13900000002'}
	},
	forward = {
		startup = 1,
		http = {
			service = {
				wecom = {
					enabled = 0,
					url     = 'https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx'
				},
				feishu = {
					enabled = 0,
					url     = 'https://open.feishu.cn/open-apis/bot/v2/hook/xxx',
				},
				dingtalk = {
					enabled = 0,
					url     = 'https://oapi.dingtalk.com/robot/send?access_token=xxx'
				},
				bark = {
					enabled = 0,
					url     = 'https://api.day.app/JZNMufhGeCRgHhPHYkE2ie'
				},
				telegram = {
					enabled = 0,
					url     = 'https://workers.999909.xyz/telegram/bot{token}/sendMessage',
					token   = '123:abc',
					id      = 12345
				},
				discord = {
					enabled = 0,
					url     = 'https://workers.999909.xyz/discord/api/webhooks/123/abc'
				},
				huaiot = {
					enabled = 0,
					url     = 'https://api.iot.999909.xyz/obj',
					auth    = '123abc'
				}
			},
			options = {
				timeout = 20,
				retries = 10,
				ua      = ''
			}
		},
		smtp = {
			enabled = 0,
			from = {
				host = 'smtp.qq.com',
				port = 465,
				ssl  = 1,
				user = '12345@qq.com',
				pass = '123abc'
			},
			to = {
				'eg02ewaxa5d@icloud.com',
				'1944060020@qq.com'
			},
			retries = 10
		}
	},
	sim = {
		['89860000000000000001'] = {
			number = '13900000001'
		},
		['89860000000000000002'] = {
			number = '13900000002',
			brand  = '中国移动'
		}
	}
}

--[[使用说明

	SMTP功能
	当前支持明文和SSL/TLS方式的连接，尚不支持STARTTLS
	典型端口，明文：25，SSL/TLS：465

	retries		如转发不成功，最大重试次数
	ethernet    USB网卡设置，0关，3开(windows)，7开(Linux)
	ctrl        可控短信制模块的号码，留空代表任意号码，不可被控制可填不存在的号码如000
	reboot      定时重启模块，单位小时，0则不重启

	飞书 安全设置仅支持"自定义关键词"。关键词为你的手机号及nil，此为可选设置
	钉钉 安全设置仅支持"自定义关键词"。关键词为你的手机号及nil

--]]