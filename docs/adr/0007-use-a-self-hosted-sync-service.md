# 使用自建服务同步家庭规则与事件

第一版使用 Vercel Functions 提供 HTTPS API，并通过 Vercel Marketplace 接入 Neon Postgres，以此取代 CloudKit：孩子端只能上报自己的当前状态、违规事件和临时申请，家长端可以读取事件、管理规则并审批申请；客户端永不持有数据库凭据。家长 Mac 的常驻进程每 30 秒安全轮询新增事件和申请、随后产生本地系统通知；不采用仍处公开测试期的 Vercel WebSocket，也不依赖 Apple 推送或 Apple Developer Program。这个选择解除 Apple 签名能力对远程 MVP 的阻塞，并保留本地执行与离线队列，但需要自行维护身份验证、数据库备份、服务可用性和安全更新。
