#### 核心功能： 短信转发

#### 成品购买： ` https://www.goofish.com/personal?userId=2792694676 `
#### 硬件复刻： ` https://oshwhub.com/eda_zoznodhaz `
#### 交流反馈： [`1030563382`](https://qm.qq.com/q/U4f9Q6sVqg?from=github)

#### 模组功能支持情况
| 模组 | 移动短信 | 联通短信 | 电信短信 | VOLTE |
| :--- | :--- | :--- | :--- | :--- |
| AIR780E | ✅ | ❌ | ❌ | ❌ |
| AIR780EP | ✅ | ❌ | ❌ | ❌ |
| AIR780EPM | ✅ | ✅ | ✅ | ❌ |
| AIR780EPV | ✅ | ✅ | ✅ | ✅ |
| AIR780EHM | ✅ | ✅ | ✅ | ✅ |

#### 使用
- 修改config各项参数
- 启用某通道，除设置通道参数外，还需要将其对应的 **` enabled `** 值设置为 **` 1 `**

#### 注意
- 如本库提供型号对应soc，务必优先使用本库所提供的。追求厂家最新soc需自测各项功能正常

#### 支持的通道
| 通道 |  | 文档 |
| :--- | :--- | :--- |
| Bark | ✅ | https://bark.day.app/#/tutorial |
| WeCom | ✅ | https://developer.work.weixin.qq.com/document/path/91770 |
| feishu | ✅ | https://open.feishu.cn/document/client-docs/bot-v3/add-custom-bot |
| DingTalk | ✅ | https://open.dingtalk.com/document/development/custom-robots-send-group-messages |
| TelegramBot | ✅ | https://core.telegram.org/bots/api#sendmessage |
| Discord | ✅ | https://docs.discord.com/developers/resources/webhook#execute-webhook |
| Email | ✅ |

#### 功能
- ✅ 转发收到短信内容
- ✅ 来电(被呼叫)通知
- ✅ 开机发送通知
- ✅ 受控发出短信
- ✅ 定时重启

#### SMS指令
给10001发送短信，内容108

    cmd##sms##10001##108

重启系统

    cmd##reboot

#### 声明
  - 受益开源，回馈开源
  - 谢绝任何形式的商用
  - 谢绝用于中华人民共和国法律所禁止的一切活动
