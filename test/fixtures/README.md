# Fixtures

One file per endpoint, each a response the service really sent, trimmed only in how many rows a
list holds and with every account's `user_token` replaced by `"scrubbed"`. Nothing else is edited:
a key inside a row is exactly as it came back, which is the whole point — a golden test here fails
when Weibo renames a field, not when this repository's idea of a field drifts.

All were taken on 2026-11-19 through the endpoints the app itself calls, anonymously where the
service allows it (weibo.com and passport) and with an anonymous visitor cookie where it does not
(m.weibo.cn). No account's own data is in any of them.

| File | Endpoint | What the test reads out of it |
|---|---|---|
| `status_show.json` | `m.weibo.cn/statuses/show` | A long post with eighteen pictures, the author, counts, `region_name` |
| `comments_hotflow.json` | `m.weibo.cn/comments/hotflow` | Hot-ordered comments, `max_id` + `max_id_type`, `total_number`, inline replies |
| `comments_by_time.json` | `m.weibo.cn/comments/hotflow` (`max_id_type=1`) | The same list newest-first, and its own cursor |
| `longtext.json` | `m.weibo.cn/statuses/extend` | `longTextContent`, the anchor the truncated text leaves behind |
| `config_list.json` | `m.weibo.cn/api/config/list` | The 推荐 channels (`channel`, `hot`), no groups for a visitor |
| `unread_empty.json` | `m.weibo.cn/api/remind/unread` | `{ok: 0, msg: 暂无数据}`, the shape a zero count comes back as |
| `hot_band.json` | `weibo.com/ajax/statuses/hot_band` | `hotgov`, rank, `num`, badge colour, category, `onboard_time`, one `is_ad` row |
| `hot_board_entertainment.json` | `weibo.com/ajax/statuses/entertainment` | The same board without `hotgov` |
| `side_search.json` | `weibo.com/ajax/side/search` | `hotquery` completions and matching accounts |
| `all_groups.json` | `weibo.com/ajax/feed/allGroups` | 推荐 channels: `group_type == 1` groups, 我的频道 then 频道推荐 |
| `profile_info.json` | `weibo.com/ajax/profile/info` | `tabList`, `status_total_counter`, `cover_image_phone`, V and 会员 fields |
| `profile_detail.json` | `weibo.com/ajax/profile/detail` | `ip_location`, `birthday`, `created_at`, `sunshine_credit`, `label_desc` |
| `profile_feature.json` | `weibo.com/ajax/profile/feature` | 精选 as m.weibo.cn container cards |
| `waterfall.json` | `weibo.com/ajax/profile/getWaterFallContent` | `list` + `next_cursor` |
| `audiowall.json` | `weibo.com/ajax/profile/getAudioList` | `list`, `next_cursor` `-1` at the end |
| `imagewall.json` | `weibo.com/ajax/profile/getImageWall` | `list` of `pid` + `mid`, `album_list` |
| `topic_detail.json` | `m.s.weibo.com/ajax_topic/detail` | `baseInfo.count`, `claim_info`, `band_info`, `media_info`, `baseData` |
| `topic_trend.json` | `m.s.weibo.com/ajax_topic/trend` | 24 hourly `read` points |
| `qrcode_image.json` | `passport.weibo.com/sso/v2/qrcode/image` | `retcode`, `qrid`, and the `data` parameter of the image address |
| `qrcode_check.json` | `passport.weibo.com/sso/v2/qrcode/check` | `retcode` 50114001, still waiting to be scanned |

Endpoints that need a signed-in account answer `{ok: -100, url: …}` to anyone else, so they have no
fixture: the feed, notifications, messages, a person's timeline, search results, the post's own
`weibo.com` copy, and every write. Their parsers are covered by the containers above (a
`profile/feature` page is the same card list a search page is) or by the hand-written cases in
`test/widget_test.dart` and `test/comment_parse_test.dart`.

To re-take one, call the endpoint with the headers `api.dart`'s interceptor sets and trim what you
get back the same way: cut list lengths, never a key.
