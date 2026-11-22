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
