# MacTimer · Chrome 扩展 + macOS App

按网站（域名级别）统计每天在网页上的停留时间。Chrome 扩展负责计时，
macOS App 负责查看，并可在获得系统授权后读取 Apple 屏幕使用时间，
把 App 使用时长和对应网站合并到一起，再按自定义分类（学习、工作、
娱乐等）汇总。数据只在本机流转，不联网、不上传。

GitHub：[Muyu-Ch/MacTimer](https://github.com/Muyu-Ch/MacTimer)

## 下载安装（Release）

普通用户不需要安装 Xcode，直接从 [GitHub Releases](https://github.com/Muyu-Ch/MacTimer/releases) 下载：

- `MacTimer-1.4.0.dmg`
- `MacTimer-Chrome-Extension-1.4.0.zip`

### 1. 安装 Mac App

1. 双击 DMG，把 `MacTimer.app` 拖到 **Applications**。
2. 因为当前版本没有 Apple 公证，首次打开可能提示「无法验证开发者」
   或「已损坏」。正确做法是：
   - 在 Finder 中右键 `MacTimer.app` → **打开** → 再点 **打开**；
   - 或者打开 **系统设置 → 隐私与安全性**，在底部选择 **仍要打开**；
   - 如果系统直接提示「已损坏」，可以只移除这个 App 的 quarantine：
     ```bash
     xattr -dr com.apple.quarantine /Applications/MacTimer.app
     ```
   - 不要关闭整个系统的 Gatekeeper。
3. 打开 App。第一次读取屏幕使用时间时，在权限提示中点
   **打开系统设置**，或手动进入：

   **系统设置 → 隐私与安全性 → 完全磁盘访问权限**

   添加 `/Applications/MacTimer.app`，打开开关，然后回到 App
   点「重新检查」。如果仍不可用，退出 App 再打开一次。

### 2. 安装 Chrome 扩展和本地桥

扩展压缩包可以单独统计网页；但要把数据同步到 Mac App，需要安装本地桥。

1. 解压 `MacTimer-Chrome-Extension-1.4.0.zip`，得到包含
   `manifest.json` 的文件夹。
2. 重新打开 DMG（如果已经推出），双击其中的
   **Install Native Host.command**。
   - 如果 macOS 拦截脚本，右键 → **打开**；
   - 在弹出的窗口中选择上一步解压出的扩展文件夹
     （必须直接包含 `manifest.json`）。
3. 脚本会：
   - 把扩展复制到稳定目录：
     `~/Library/Application Support/MacTimer/Extension`
   - 安装本地桥 `MacTimerHost`；
   - 写入 Chrome 的 native messaging 清单；
   - 打印扩展 ID 和后续步骤。
4. 打开 Chrome，地址栏输入 `chrome://extensions`：
   - 打开右上角 **开发者模式**；
   - 点击 **加载已解压的扩展程序**；
   - 选择上面的稳定目录
     `~/Library/Application Support/MacTimer/Extension`
     （不要选择 Downloads 里原来的解压目录）。
5. 如果之前已经加载过旧版扩展，先移除旧扩展，避免出现两个扩展
   或多个 ID。
6. 点击扩展图标，在弹窗底部点 **同步到 Mac**。平时扩展也会每 5 分钟
   自动同步一次。

> 扩展 ID 由加载目录的绝对路径决定。安装脚本已经把路径固定到
> `Application Support/MacTimer/Extension`，以后更新扩展时重新运行脚本
> 并重新加载同一目录即可保留 ID。不要移动或删除这个目录。

### 3. 首次数据检查

- Chrome 扩展弹窗应能看到当天的网站时长；
- Mac App 的「网站与 App」中应看到 Chrome 数据；
- 授权完全磁盘访问权限后，还会出现 Screen Time 的 App 数据和
  按小时图；
- Chrome 的未记录时间会在 Screen Time 数据可用后自动计算。

### 4. 更新

- 下载新版本 DMG、扩展 ZIP；
- 重新运行 DMG 中的 `Install Native Host.command` 并选择新的扩展解压目录；
- Chrome 里对同一个稳定目录重新加载扩展；
- App 覆盖安装后，如果完全磁盘访问权限失效，移除并重新添加
  `/Applications/MacTimer.app`。

> 发布构建默认匹配当前构建机器的 CPU 架构。如果你需要把 DMG 给
> Intel Mac 或同时支持 Intel/Apple Silicon，请在发布前确认构建架构，
> 或从源码自行构建。

### 从旧版 StayTimer 升级

- 新版会把
  `~/Library/Application Support/StayTimer/usage.json` 复制到
  `~/Library/Application Support/MacTimer/usage.json`；
- 自定义映射会从旧 bundle 的偏好设置迁移；
- 安装脚本会移除旧 `/Applications/StayTimer.app`、旧本地桥和旧
  Chrome native messaging 清单；
- 重新加载扩展，并给 `/Applications/MacTimer.app` 重新授予完全磁盘
  访问权限。旧 App 的授权不会自动转移。

## 从源码安装（开发者）

以下步骤需要 Xcode 或 Xcode-beta 和终端；普通用户使用上面的 Release
安装即可。

```bash
git clone https://github.com/Muyu-Ch/MacTimer.git
cd MacTimer
```

### 1. 安装 Chrome 扩展

1. 打开 Chrome，地址栏输入 `chrome://extensions`。
2. 打开右上角的「开发者模式」。
3. 点击「加载已解压的扩展程序」，选择克隆或解压后的项目目录
   （也就是包含 `manifest.json` 的目录）。
4. 在 Chrome 的扩展菜单里固定「MacTimer」。图标上的徽标会显示今天
   的累计停留时长（如 `45m`、`2.3h`）。

### 2. 构建并安装 macOS App

```bash
macos/scripts/install.sh
```

脚本会：

- 用 Xcode / Xcode-beta 的 Swift 工具链构建 `MacTimer.app` 和本地桥
  `MacTimerHost`；
- 把 App 安装到 **`/Applications/MacTimer.app`（如果那里已有 App）**，
  否则安装到 `~/Applications/MacTimer.app`；
- 清理另一处遗留的旧副本，避免启动到旧版本；
- 把本地桥安装到
  `~/Library/Application Support/MacTimer/bin/MacTimerHost`；
- 安装 Chrome 的 native messaging 清单到
  `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`；
- 打印扩展路径、扩展 ID 和后续步骤。

如果需要指定安装位置，可以运行：

```bash
APP_INSTALL_PATH="$HOME/Applications/MacTimer.app" macos/scripts/install.sh
```

然后：

1. 打开 `chrome://extensions`，对「MacTimer」点一次 **Reload**
   （新增了 `nativeMessaging` 权限）。
2. 点击扩展图标，在弹窗底部点 **同步到 Mac**。
3. 打开安装脚本最后打印的 App 路径查看网页数据（通常是
   `/Applications/MacTimer.app` 或 `~/Applications/MacTimer.app`）。
4. 如要合并 App 使用时间：打开 App，在顶部权限提示中点
   **打开系统设置**；或手动进入 **系统设置 → 隐私与安全性 →
   完全磁盘访问权限**，添加 `MacTimer.app`。授权后如果仍不可用，
   退出并重新打开 App。安装脚本也会打印这个路径。

如果扩展不是从默认目录加载的，请用实际目录重新安装一次：

```bash
EXTENSION_DIR=/实际/扩展目录 macos/scripts/install.sh
```

扩展 ID 由扩展目录的路径决定；移动扩展目录后需要重新运行安装脚本。

卸载 App 和本地桥：

```bash
macos/scripts/uninstall.sh            # 保留本地数据
macos/scripts/uninstall.sh --purge    # 同时删除本地数据
```

## 计时规则

- 只统计同时满足以下条件的时间：Chrome 窗口处于前台、当前标签页是
  活动标签页、页面协议是 `http` 或 `https`。
- 切换到其他应用、最小化窗口、切换标签页、打开 `chrome://` 等浏览器
  内部页面时，计时自动暂停。
- 按网站域名汇总，而不是按具体页面。`www.youtube.com` 和
  `music.youtube.com` 都记到 `youtube.com`；`mail.google.com` 记到
  `google.com`。对 `co.uk`、`com.cn` 等常见多级后缀做了轻量处理（不是
  完整的公共后缀列表），IP 地址和 `localhost` 按原样记录。
- 无痕窗口默认不计入。
- 每 1 分钟把当前计时落盘一次；切换标签页、切换窗口焦点、页面加载完成
  时会立即落盘，避免扩展后台被回收时丢时间。
- 每天按本地时区的 0 点切换为新的一天。跨过 0 点的会话会自动拆成两段，
  分别记到两天，所以「每日数据」在 0 点之后自然从零开始。
- 如果两次落盘间隔超过 5 分钟（例如电脑睡眠、Chrome 被完全挂起），这段
  空档不会计入，避免唤醒后凭空多出几小时。

## Chrome 弹窗

- 左右箭头按天翻看历史；「今天」「昨天」会有标记。
- 每个网站显示当天总时长和相对用时条；总计为当天所有网站之和。
- 底部是最近 7 天的每日总量小柱状图，点击柱子可以跳到那一天。
- 底部「同步到 Mac」会立即把数据写给 Mac App；平时扩展每 5 分钟自动
  尝试同步一次。

## macOS App

当前版本：**1.4.0**（build 9）。原生 SwiftUI 仪表盘。顶部有
「日 / 周 / 月 / 年」切换，覆盖日历和统计。
获得完全磁盘访问权限后，统计会把 Apple 屏幕使用时间里的 App 时长与
Chrome 扩展记录的网站时长合并；未授权时只显示网页数据，App 顶部会有
权限提示。

- **日视图**：当天总使用、最常用网站/App、前一天总计；「当日使用」图
  可以在**按小时**、**按网站/App** 和**按分类**之间切换。按小时的分时
  图来自 Screen Time，柱子按分类颜色分段堆叠；如果当天没有分时数据，
  会自动显示网站/App 图。按网站/App 的柱子同样使用所属分类的颜色。
  图下方显示当天各分类的时长和占比。
- **周视图**：周一至周日七列每日使用，柱子按分类分段堆叠；图下方显示
  本周各分类的时长和占比。点击某天可进入当天明细。
- **月视图**：月历中显示每天的总时长和深浅热力色；日历下方显示本月的
  分类组成条、各分类时长和占比。点击日期进入当天明细。
- **年视图**：12 个月柱状图，柱子按分类分段堆叠；图下方显示全年各分类
  的时长和占比。点击月份进入月视图。
- 没有归类的项目统一显示为 **「未分类」**，并使用灰色。

通用交互：

- 日期左右箭头按当前粒度前进/后退；「回到今天 / 本周 / 本月 / 今年」。
- 点击周视图的某天、月历中的日期或年视图中的月份，可以逐级下钻。
- 排行在项目较多时显示前 8 个，其余合并为「其他 N 项」。
- 周视图和月历都按周一到周日排列。
- 顶部显示 Chrome 数据最后一次同步的时间。
- 顶部同步按钮右侧有独立的设置齿轮；也可以按 `⌘,`。
- 设置里可以把外观切换为 **跟随系统 / 明亮 / 黑暗**。
- 设置里可以把 **每天的开始时间** 设为 `00:00` 到 `04:00` 之间的整点。
  例如设为 `04:00` 后，每天 `00:00–04:00` 的使用会计入前一天。
- 设置里可以新建分类、修改分类颜色，并把 App 或网站添加到分类。
- 设置里的「关于 MacTimer」或应用菜单 **关于 MacTimer** 会打开信息页，
  其中包含版本、开发者信息和支持方式。

App 每 3 秒检查一次本地快照文件，每 60 秒刷新一次屏幕使用时间。
网页同步由 Chrome 扩展主动发起；App 读取本机 Screen Time 数据库时
只读、不联网。Chrome 关闭后，仍可查看最后一次同步的网页数据。

### 每天的开始时间

可以在设置中把一天的起点设为 `00:00`、`01:00`、`02:00`、`03:00`
或 `04:00`。例如选择 `04:00` 后：

- 每天 `00:00–04:00` 的网页和 App 使用会归入前一天；
- 「今天」、日历选中状态、日/周/月/年统计都按这个起点计算；
- 日视图分时图的横轴也随之改变，例如 `04:00` 会显示为
  `04:00 → 次日 04:00` 的顺序；
- Screen Time 的已保存小时数据会跟随设置重新归档；
- Chrome 扩展会记录 `earlyHours`（`00:00–04:00` 的分时），App 用它
  精确回移；扩展更新前已经汇总的历史网页数据无法反向拆分；
- 扩展弹窗和工具栏徽标仍按自然日显示。

修改后会立即重新计算并刷新视图，不需要重新读取 Screen Time 或重启 App。

## 屏幕使用时间与网站/App 合并

Apple 没有向第三方开放读取全部屏幕使用时间统计的公开 API，因此 App
使用 macOS 本机 Screen Time 的私有数据库
`~/Library/Application Support/Knowledge/knowledgeC.db`。实现方式：

- 以只读方式打开数据库，读取 `/app/usage`（没有时回退到
  `/app/inFocus`）中的 bundle id 和起止时间，按本地 0 点拆分到每天。
- 只在本机读取和展示；不复制数据库、不写入数据库、不联网。
- 需要给 `MacTimer.app` 授予 **完全磁盘访问权限**。系统设置 →
  隐私与安全性 → 完全磁盘访问权限。授权后如果 App 仍显示未授权，
  退出并重新打开 App。App 更新后如果权限失效，需要重新添加。
- macOS 的 App 事件明细通常只保留最近约 4 周；更早的日期仍会显示
  Chrome 网页数据，但不会凭空补出 App 时长。App 最多尝试读取
  最近 730 天。
- 日视图的「按小时」图由 Screen Time 的 App 事件起止时间计算；没有
  完全磁盘访问权限、没有当天分时数据或日期超出保留范围时，会自动
  回退为「按网站/App」图。
- Screen Time 只提供 Chrome 的每小时总时长，不提供 Chrome 内部逐域名
  的分时数据。按小时图会按当天 Chrome 各分类的域名时长比例，把每小时的
  Chrome 时间分配到对应分类；当天各分类的总时长仍与分类汇总一致。
- 每次成功读取 Screen Time 后，App 会把日/小时数据合并保存到自己的
  `~/Library/Application Support/MacTimer/screen-time-archive.json`。
  因此 Apple 清掉 4 周前的明细后，MacTimer 仍能保留之前已经读过的历史。
  归档从第一次成功读取开始，不能反向补录更早的日期。
- Chrome、Chrome 网页 App 以及 MacTimer 自身不计入这里的普通 App 项，
  因为 Chrome 网站时间已经由扩展记录，否则会重复计算。
- App 会额外计算 **Chrome（未记录）**：用 Screen Time 里 Chrome（含
  Chrome 网页 App）的总时长，减去扩展当天记录的所有域名时长之和。
  - 差值 **小于 3 分钟**：视为插件一直在正常工作，当天的 Chrome 未记录
    时间为 0，只显示扩展的域名时长；
  - 差值 **大于等于 3 分钟**：把差值作为「Chrome（未记录）」一项加入
    当天统计，表示插件未覆盖的 Chrome 时间（例如插件关闭、内部页面
    或浏览器空转）。
  - 这个计算需要 Screen Time 数据；没有完全磁盘访问权限或屏幕使用
    时间数据时不会凭空生成这一项。
- App 的界面文字和图标来自本机已安装的 App；无法对应到本机 App 的
  bundle id（例如其他设备的系统组件）会被忽略。
- Safari 等其他浏览器会作为 App 显示；浏览器不能用来自定义映射到
  某个具体网站，因为它会把所有网页时间都算到那个网站上。
- 为排查私有数据库格式变化，App 会在本机写入一个只含状态、天数、
  流名称和错误信息的 `screen-time-status.json`（位于
  `~/Library/Application Support/MacTimer/`），不包含具体 App
  使用明细；可以随时删除。

### 内置映射和自定义映射

内置了一组常见网站 ↔ App 的映射，例如：

| 网站域名 | App |
| --- | --- |
| `bilibili.com` | 哔哩哔哩（`com.bilibili.bilibiliPC`） |
| `steampowered.com` | Steam |
| `spotify.com` | Spotify |
| `netflix.com` | Netflix |
| `notion.so` | Notion |
| `chatgpt.com` | ChatGPT |
| `github.com` | GitHub Desktop |

内置映射只会在对应 App 已安装或屏幕使用时间里有记录时参与合并，
避免把没有使用的网站误标成 App。映射后，网站的停留时间和 App 的
屏幕使用时间相加，多个域名可以对应同一个 App，只加一次 App 时长。

自定义映射：

1. 点顶部同步按钮右侧的设置齿轮，或按 `⌘,` 打开设置。
2. 输入域名（可以带 `https://`、`www.` 或路径，会自动归并到
   `bilibili.com` 这样的域名）。
3. 选择一个本机 App，点「添加映射」。
4. 自定义映射会立即生效并保存；删除后恢复同域名的内置映射。
   同一域名的自定义映射会覆盖内置映射。

## 分类标签

可以把 App 和网站归入自定义分类，例如「学习」「工作」「娱乐」。
MacTimer 默认提供这三个分类，也可以新建、改名、改色或删除。

使用方式：

1. 打开 **设置 → 分类标签**。
2. 点「新建分类」，输入名称并选择颜色。分类名称和颜色都可以随时修改。
3. 在「给记录设置标签」中，从已经出现过的记录列表里找到网站或 App。
   - 列表包含全部历史记录，不只限于今天或当前视图；
   - 可以用搜索框按名称、域名或 bundle identifier 过滤；
   - 已合并的网站会显示为对应的 App 目标，归类该 App 即可覆盖
     合并后的网站时长；单独出现的域名会显示为网站目标。
4. 点击该行右侧的标签，在弹出的列表中选择一个已经建好的分类，规则会
   立即生效。再次点击标签可以选择其他分类或「清除分类」。

规则说明：

- **App 规则优先于网站规则**。例如把哔哩哔哩 App 归入「娱乐」后，
  即使 `bilibili.com` 被单独的网站规则归入别的分类，合并后的
  「哔哩哔哩 + bilibili.com」也会使用 App 的分类。
- 网站与 App 合并后的项目按合并后的总时长统计，不会被拆开。
- 没有匹配到任何规则的 App 或网站归入 **「未分类」**，固定使用灰色。
- 同一个 App 或域名重复添加规则时，新规则会替换旧规则。
- 删除分类会同时删除关联规则，这些项目会回到「未分类」。
- 分类规则和颜色保存在本机 `UserDefaults` 中，不写入 Screen Time
  数据库，也不会上传。
- 日、周、月、年视图的柱状图/日历会随分类、规则和颜色变化立即更新。
- 归类列表只包含已经产生过记录的项目；如果某个网站或 App 还没有
  出现在任何记录里，需要先使用一次，等数据刷新后再来归类。

## 数据与同步

扩展的 `chrome.storage.local` 中有：

| 键 | 内容 |
| --- | --- |
| `current` | 当前正在计时的会话：`{ site, since }` |
| `day:YYYY-MM-DD` | 某个本地日期下各网站的毫秒数，如 `{ "youtube.com": 7200000 }` |
| `early:YYYY-MM-DD` | 该本地日期 `00:00–04:00` 的分时数据：`{ "0": { "youtube.com": 120000 }, ... }`，用于 App 的「每天的开始时间」 |

扩展通过本机 native messaging 桥，把数据镜像到：

```
~/Library/Application Support/MacTimer/usage.json
```

镜像格式：

```json
{
  "version": 1,
  "updatedAt": 1795364615376,
  "current": { "site": "youtube.com", "since": 1795364600000 },
  "days": {
    "2026-11-23": { "youtube.com": 7200000 }
  },
  "earlyHours": {
    "2026-11-23": {
      "0": { "youtube.com": 120000 },
      "1": { "youtube.com": 60000 }
    }
  }
}
```

- 每 5 分钟发送一次增量（今天和昨天）；首次安装、Chrome 启动和手动同步
  时发送完整快照。
- native messaging 单条消息上限约 1 MB。完整快照会控制在约 850 KB 以内，
  超出时优先保留最近日期的数据；扩展自身仍保留完整历史。
- `earlyHours` 是每个本地日期 `00:00–04:00` 的分时数据，只用于「每天的开始时间」。
  App 用它把凌晨时段移到前一天；较早的镜像没有这个字段时，对应日期无法精确回移。
- 这个 JSON 只包含 **Chrome 网页数据**。App 使用时长不会写进
  `usage.json`，而是由 App 在每次刷新时从本机屏幕使用时间数据库读取，
  并归档到 `~/Library/Application Support/MacTimer/screen-time-archive.json`；
  因此不会改变扩展和本地桥的格式。
- 所有数据只在本机文件中，不经过网络。

## 开发与测试

扩展测试（无需依赖）：

```bash
npm test
```

macOS 测试覆盖日期周期（周一起始、月网格、年键）、跨天聚合、
时长格式、本地存储、域名归一化、App/网站合并、内置/自定义映射、
分类规则的新增/修改/删除/持久化与优先级、按分类聚合未分类时长、
从历史记录生成网站/App 归类目标、日图表的三种模式、每天开始时间的
逻辑日计算与 Chrome/Screen Time 回移、
Chrome 未记录时间的三分钟阈值，以及用临时 SQLite 数据库构造的
屏幕使用时间解析（跨午夜/跨小时拆分、`/app/usage` 与
`/app/inFocus` 流选择、格式错误处理）。真实系统数据库需要完全
磁盘访问权限，测试不会读取它。构建需要 Xcode 或 Xcode-beta 提供的
Swift 工具链，因为 SwiftUI 宏插件不在纯 Command Line Tools 中：

```bash
macos/scripts/test.sh
macos/scripts/build.sh
```

App 图标由纯标准库 Python 脚本生成，再转换成 `.icns`：

```bash
macos/scripts/make-app-icon.sh
```

文件结构：

```
manifest.json      扩展清单（Manifest V3）
shared.js          纯函数：域名归并、日期、时长格式化
background.js      Service Worker：计时、落盘、徽标、本地同步
popup.html/css/js  扩展弹窗
icons/             扩展和 App 图标
tests/             扩展的 Node 测试
tools/             图标生成
macos/
  Package.swift
  Sources/MacTimerCore     数据模型、日期/周期、屏幕使用时间读取、域名与 App 合并
  Sources/MacTimerUI       SwiftUI 界面、日/周/月/年视图、设置、映射、分类和权限状态
  Sources/MacTimer         App 入口
  Sources/MacTimerHost     native messaging 本地桥
  Sources/MacTimerPreview  截图/预览工具
  Tests/                    Swift 核心与界面测试
  Resources/                Info.plist、AppIcon.icns
  Resources/Support/        关于页的收款码图片
  scripts/                  build / install / uninstall / test / package-release
                            / Install Native Host.command
.github/
  workflows/release.yml     推送 v* tag 时自动构建并上传 Release
  release-notes.md          Release 页面安装说明
dist/                       本地生成的 DMG / 扩展 ZIP（不提交）
build/                      构建产物（MacTimer.app、MacTimerHost）
```

## 发布新版本

1. 同步更新版本号：
   - `macos/Resources/Info.plist` 的 `CFBundleShortVersionString`；
   - `manifest.json` 和 `package.json` 的 `version`。
2. 运行全部测试：
   ```bash
   npm test
   macos/scripts/test.sh
   ```
3. 生成 DMG、扩展 ZIP 和校验文件：
   ```bash
   macos/scripts/package-release.sh
   ls -lh dist/
   ```
   `dist/` 已被 `.gitignore` 忽略，不会提交进仓库。DMG 内会自动包含
   `Install Native Host.command`、本地桥和安装说明。
4. 提交并打 tag：
   ```bash
   git add .
   git commit -m "Release v1.4.0"
   git tag -a v1.4.0 -m "MacTimer 1.4.0"
   git push origin main
   git push origin v1.4.0
   ```
5. GitHub Actions 会由 `.github/workflows/release.yml` 在 `v*` tag 上
   自动构建并创建 Release。也可以手动发布：
   ```bash
   gh release create v1.4.0 \
     dist/MacTimer-1.4.0.dmg \
     dist/MacTimer-Chrome-Extension-1.4.0.zip \
     dist/SHA256SUMS.txt \
     --title "MacTimer 1.4.0" \
     --notes-file .github/release-notes.md
   ```

当前发布使用的是 ad-hoc 签名，没有 Apple 公证；DMG 下载后可能出现
Gatekeeper 警告。Release 说明和上面的安装步骤已经写明了右键打开方式。
如果需要无警告的正式下载体验，后续再接入 Apple Developer ID 签名、
公证和扩展的 Chrome Web Store 发布。

## 参与贡献

欢迎提交 issue 和 pull request。提交前请先运行：

```bash
npm test
macos/scripts/test.sh
```

不要提交 `build/`、`macos/.build/`、`usage.json`、真实 Screen Time
数据或其他本机私有文件。涉及 Screen Time 的 issue 请只贴出错误信息和
`screen-time-status.json` 中的状态字段，不要贴出具体 App 使用明细。

## 开源与免责声明

- 本项目与 Apple 无关联，也不是 Apple 官方产品。
- macOS 端读取的是 Apple 未公开的 Screen Time 本地数据库，需要用户
  手动授予完全磁盘访问权限；这类实现可能随 macOS 更新失效，使用风险
  由使用者自行承担。
- 第三方 App 名称、图标和 bundle identifier 属于各自所有者；内置映射
  仅作为示例，不代表与这些产品存在合作或背书。
- `macos/Resources/Support/` 中的微信/支付宝收款码图片仅用于支持本项目
  开发者，不属于 MIT 许可的代码范围，请勿另作他用。
- 本项目使用 MIT License，详见 `LICENSE`。

## 已知边界

- Chrome 完全关闭的时段不统计；关闭前的最后一小段最多可能丢失约 1 分钟。
- 停在某个网页但人离开电脑时，只要 Chrome 仍在前台、系统没有休眠，就会
  继续计时。这里刻意没有使用系统空闲检测，否则看视频、读长文时容易被误判
  为「离开」。
- 域名归并使用轻量规则，极少数冷门多级后缀可能与公共后缀列表的划分不同。
  这也会影响映射：例如 `weixin.qq.com` 按当前规则会归到 `qq.com`，因此
  这类共享域名下的服务无法单独映射。
- 网页数据依赖 Chrome 和扩展运行；Chrome 关闭后只显示最后一次同步的镜像。
  App 数据不依赖 Chrome，但需要完全磁盘访问权限。
- 「每天的开始时间」会作用于 Mac App 的日/周/月/年统计。扩展弹窗和工具栏
  徽标仍然按自然日显示。Chrome 的分日数据只有在扩展记录 `earlyHours`
  之后才能精确回移；更新前已经汇总的网页历史无法拆分。Screen Time 历史
  因为保存了小时数据，修改开始时间后会重新归入新的日期。
- Screen Time 的本地数据库是 Apple 未公开的结构，macOS 版本更新后可能
  改变字段或流名称；App 会在读取失败时显示提示，而不是静默显示空数据。
  `knowledgeC.db` 的 App 明细和分时事件通常只覆盖约最近 4 周，年度
  App 统计和日视图的分时图会因此不完整；更早日期会回退为网站/App 图。
  这是系统数据库本身的保留限制。MacTimer 会把已读取的数据归档，因此
  从首次成功读取之后不会再丢历史；归档前已经消失的日期无法恢复。
- App 的「屏幕使用」总计是网页时间与 Screen Time App 时间的本地合并，
  不等同于 Apple 屏幕使用时间界面中的官方总计（系统可能有自己的去重、
  设备同步和四舍五入规则）。
- Chrome、Chrome 网页 App 和 MacTimer 自身不作为普通 App 项；只有
  Chrome 总时长与扩展域名总时长相差至少 3 分钟时，差额才以
  「Chrome（未记录）」显示。没有 Screen Time 权限时无法计算这个差额，
  只显示扩展的域名时长。
- 更新 `MacTimer.app` 后代码签名会变化。如果系统不再允许读取
  Screen Time，请在完全磁盘访问权限中移除并重新添加 App。
- 移动扩展目录会改变 Chrome 分配的扩展 ID，需要重新运行安装脚本来更新
  native messaging 清单。
- `tabs` 权限会触发「读取您的浏览记录」提示，这是读取当前标签页 URL 所
  必需的；`favicon` 只用于显示网站图标；`alarms` 用于每分钟落盘和定期
  同步；`nativeMessaging` 只用于和本机的 MacTimer 本地桥通信。

## License

MIT © 2026 Muyu-Ch. See [LICENSE](LICENSE).
