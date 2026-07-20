---
status: superseded by ADR-0007
---

# 使用 CloudKit 同步家庭规则与违规事件

第一版使用家长拥有的 CloudKit 私有记录区承载家庭空间，并通过 CloudKit Sharing 让使用独立 Apple Account 的孩子加入、由受管 Mac 写入最小化违规事件；家长设备订阅变化、收到推送后再获取事件。正式部署要求家长与孩子使用各自账户，现有共用账户只用于早期本机原型。这样可以依靠 Apple 账户体系完成跨设备同步与私有共享，不必先维护自建服务器，但产品将依赖 iCloud 登录、CloudKit 可用性和 Apple 平台，若未来支持 Android、多家庭运营或更强防篡改能力，则需要重新评估独立后端。
