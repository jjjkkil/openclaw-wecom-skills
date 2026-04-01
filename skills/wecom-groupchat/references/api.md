# 企业微信群聊 API 参考

## 目录
- [创建群聊会话](#创建群聊会话)
- [修改群聊会话](#修改群聊会话)
- [获取群聊会话](#获取群聊会话)
- [应用推送消息](#应用推送消息)

详细 API 文档请参考企业微信官方文档：
- [创建群聊会话](https://developer.work.weixin.qq.com/document/path/90245)
- [修改群聊会话](https://developer.work.weixin.qq.com/document/path/98913)
- [获取群聊会话](https://developer.work.weixin.qq.com/document/path/98914)
- [应用推送消息](https://developer.work.weixin.qq.com/document/path/90248)

## 创建群聊会话

- 请求方式: POST
- 请求地址: `https://qyapi.weixin.qq.com/cgi-bin/appchat/create?access_token=ACCESS_TOKEN`

**请求参数:**

| 参数 | 必须 | 说明 |
|------|------|------|
| name | 否 | 群聊名，最多50个utf8字符 |
| owner | 否 | 群主id |
| userlist | 是 | 群成员id列表，至少2人 |
| chatid | 否 | 群聊唯一标志，由企业微信生成 |

**返回示例:**

```json
{
  "errcode": 0,
  "errmsg": "ok",
  "chatid": "CHATID"
}
```

## 修改群聊会话

- 请求方式: POST
- 请求地址: `https://qyapi.weixin.qq.com/cgi-bin/appchat/update?access_token=ACCESS_TOKEN`

**请求参数:**

| 参数 | 必须 | 说明 |
|------|------|------|
| chatid | 是 | 群聊id |
| name | 否 | 新的群聊名 |
| owner | 否 | 新群主的id |
| add_user_list | 否 | 添加成员的id列表 |
| del_user_list | 否 | 踢出成员的id列表 |

## 获取群聊会话

- 请求方式: GET
- 请求地址: `https://qyapi.weixin.qq.com/cgi-bin/appchat/get?access_token=ACCESS_TOKEN&chatid=CHATID`

**返回示例:**

```json
{
  "errcode": 0,
  "errmsg": "ok",
  "chat_info": {
    "chatid": "CHATID",
    "name": "NAME",
    "owner": "userid2",
    "userlist": ["userid1", "userid2", "userid3"],
    "chat_type": 0
  }
}
```

## 应用推送消息

- 请求方式: POST
- 请求地址: `https://qyapi.weixin.qq.com/cgi-bin/appchat/send?access_token=ACCESS_TOKEN`

**消息类型:**

- text: 文本消息
- image: 图片消息
- voice: 语音消息
- video: 视频消息
- file: 文件消息
- textcard: 文本卡片消息
- news: 图文消息
- mpnews: 图文消息(mpnews)
- markdown: Markdown消息

## 限制说明

- 只允许企业自建应用调用
- 应用的可见范围必须是根部门
- 群成员人数不可超过2000人
- 每企业创建群的次数不可超过1000次/小时
- 每企业变更群的次数不可超过1000次/小时
- 每企业消息发送量不可超过2万人次/分
- 每个成员在群中收到的同一个应用的消息不可超过200条/分，1万条/天
