# 企业微信预约会议 - 参考文档

## 官方 API 文档

- [创建预约会议](https://developer.work.weixin.qq.com/document/path/99104)
- [修改预约会议](https://developer.work.weixin.qq.com/document/path/99047)
- [取消预约会议](https://developer.work.weixin.qq.com/document/path/99048)
- [获取会议详情](https://developer.work.weixin.qq.com/document/path/99049)
- [获取成员会议ID列表](https://developer.work.weixin.qq.com/document/path/99050)

## 常见错误码

| 错误码 | 含义 | 解决方案 |
|--------|------|----------|
| 60020 | IP 不允许 | 检查代理配置是否正确 |
| 48002 | API 被禁止 | 在企业微信后台开启「会议接口权限」|
| 60111 | 用户ID不存在 | 检查 invitees 的用户ID是否正确 |
| 40058 | 参数错误 | 检查请求参数格式 |
| 41001 | 缺少 access_token | 检查 corpSecret 是否正确 |
| 400039 | 管理员不在参会人列表 | 脚本已自动处理，管理员会自动加入参会人 |
