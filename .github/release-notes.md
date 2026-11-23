## MacTimer 1.4.0

本次更新：

- 新增自定义分类标签：可给网站和 App 设置学习、工作、娱乐等标签，
  并自定义颜色；日/周/月/年视图会按分类展示时长。
- 分类用时整合进柱状图：日视图可按小时、网站/App 或分类查看，
  周/年柱状图按分类堆叠，月视图显示分类组成。
- 新增设置页：可切换跟随系统 / 明亮 / 黑暗，管理标签，查看软件信息。
- 新增「每天的开始时间」：可选 00:00–04:00；例如 04:00 会把每天
  00:00–04:00 的使用计入前一天，分时图坐标轴也会随之改变。
- Screen Time 数据会归档保存在本机，减少系统约 4 周保留期的限制。
- Chrome 扩展新增凌晨分时数据，用于「每天的开始时间」的精确回移。

> 升级后请在 `chrome://extensions` 中重新加载扩展，才能开始记录凌晨分时。
> 扩展更新前已经汇总的旧网页历史无法反向拆分。App 更新后可能需要重新授予
> 完全磁盘访问权限。

## 下载

- `MacTimer-*.dmg`：macOS App
- `MacTimer-Chrome-Extension-*.zip`：Chrome 扩展
- `SHA256SUMS.txt`：下载文件校验值

## 安装

1. 打开 DMG，把 `MacTimer.app` 拖到 Applications。
2. 解压 Chrome 扩展 ZIP。
3. 在 DMG 中双击 `Install Native Host.command`（如果被拦截，右键 → 打开），
   选择解压后的扩展目录。它会安装本地桥，并把扩展复制到稳定目录。
4. Chrome 打开 `chrome://extensions`，启用开发者模式，
   加载 `~/Library/Application Support/MacTimer/Extension`。
5. 打开 App，在系统设置 → 隐私与安全性 → 完全磁盘访问权限中添加
   `/Applications/MacTimer.app`。
6. 在扩展弹窗中点击「同步到 Mac」。

详细说明见仓库 README。

## 注意

- App 未经过 Apple 公证，首次打开可能被 Gatekeeper 拦截；请右键打开，
  或在「隐私与安全性」中选择「仍要打开」。不要关闭整个系统的 Gatekeeper。
- App 更新后可能需要重新添加完全磁盘访问权限。
- 扩展的稳定目录不要随意移动，否则 Chrome 扩展 ID 会变化，本地桥清单
  需要重新运行安装脚本。
- Screen Time 使用 Apple 未公开的本地数据库，系统更新后可能失效；
  详见 README 的已知边界。
