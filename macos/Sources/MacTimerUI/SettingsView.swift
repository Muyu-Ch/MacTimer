import AppKit
import SwiftUI
import MacTimerCore
import UniformTypeIdentifiers

public struct MacTimerSettingsView: View {
    @ObservedObject private var model: DashboardModel
    @ObservedObject private var store: MappingStore
    @Environment(\.colorScheme) private var scheme

    @State private var domainInput = ""
    @State private var selectedApp: SelectedApp?
    @State private var validationMessage: String?
    private let previewMode: Bool

    private struct SelectedApp: Equatable {
        var bundleID: String
        var name: String
    }

    public init(
        model: DashboardModel,
        store: MappingStore,
        previewMode: Bool = false
    ) {
        self.model = model
        self.store = store
        self.previewMode = previewMode
    }

    public var body: some View {
        Group {
            if previewMode {
                settingsContent
            } else {
                ScrollView {
                    settingsContent
                }
            }
        }
        .background(Theme.page(scheme).ignoresSafeArea())
        .frame(minWidth: 620, minHeight: 660)
        .tint(Theme.accent(scheme))
    }

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            screenTimeSection
            mappingSection
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置")
                .font(.system(size: 24, weight: .semibold))
            Text("管理 Apple 屏幕使用时间的读取权限，以及网站与 App 的合并关系。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Screen Time access

    private var screenTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Apple 屏幕使用时间")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                screenTimeStatusBadge
            }

            Text("App 使用时长从本机 Screen Time 数据库只读读取，并合并进日、周、月、年统计。Chrome 及其网页 App 不使用这里的时长，避免与扩展记录的网站时间重复计算。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            screenTimeErrorDetail

            HStack(spacing: 8) {
                Button("打开完全磁盘访问设置") {
                    model.openFullDiskAccessSettings()
                }
                .buttonStyle(
                    CompactActionButtonStyle(
                        scheme: scheme,
                        emphasized: !model.screenTimeAccess.isReady
                    )
                )

                Button("在 Finder 中显示 App") {
                    model.revealAppInFinder()
                }
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: false)
                )

                Button("重新检查") {
                    model.retryScreenTime()
                }
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: false)
                )
            }

            Text("最多尝试读取最近 730 天；macOS 通常只保留最近约 4 周的 App 事件明细，更早的日期以网页数据为主。首次使用或更新 App 后，请在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中添加 MacTimer.app；如果授权后仍不可用，请退出并重新打开 App。")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .stayCard(scheme)
    }

    @ViewBuilder
    private var screenTimeErrorDetail: some View {
        switch model.screenTimeAccess {
        case .needsPermission:
            Text("尚未获得完全磁盘访问权限，目前只显示网页数据。")
                .font(.system(size: 11))
                .foregroundStyle(Theme.warningInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
        case .unavailable(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.warningInk(scheme))
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var screenTimeStatusBadge: some View {
        switch model.screenTimeAccess {
        case .idle, .loading:
            statusText("正在连接…", color: .secondary)
        case .ready(let dayCount, let updatedAt):
            statusText(
                dayCount > 0
                    ? "已读取 \(dayCount) 天 · \(timeText(updatedAt))"
                    : "已连接 · 暂无 App 记录",
                color: Theme.accentInk(scheme)
            )
        case .needsPermission:
            statusText("需要完全磁盘访问权限", color: Theme.warningInk(scheme))
        case .unavailable:
            statusText("暂不可用", color: Theme.warningInk(scheme))
        }
    }

    private func statusText(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func timeText(_ date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.hour, .minute],
            from: date
        )
        return String(
            format: "%02d:%02d",
            components.hour ?? 0,
            components.minute ?? 0
        )
    }

    // MARK: - Mapping

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("网站与 App 映射")
                    .font(.system(size: 14, weight: .semibold))
                Text("映射后，网站的停留时间会和对应 App 的屏幕使用时间合并为一项。同一 App 可以关联多个域名；自定义映射覆盖同域名的内置映射。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            customMappingsSection
            addMappingSection
            builtInMappingsSection
        }
        .padding(18)
        .stayCard(scheme)
    }

    private var customMappingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("自定义映射")

            if store.customMappings.isEmpty {
                Text("还没有自定义映射。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.customMappings) { mapping in
                        mappingRow(
                            mapping: mapping,
                            trailing: AnyView(
                                Button {
                                    store.removeMapping(domain: mapping.domain)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help("删除这条自定义映射")
                            )
                        )
                    }
                }
            }
        }
    }

    private var addMappingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("添加映射")

            HStack(alignment: .center, spacing: 10) {
                TextField(
                    "网站域名，如 bilibili.com",
                    text: $domainInput
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)

                Button(selectedApp == nil ? "选择应用…" : "更换应用") {
                    chooseApplication()
                }
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: false)
                )
            }

            if let selectedApp {
                HStack(spacing: 7) {
                    mappingIcon(bundleID: selectedApp.bundleID)
                    Text(selectedApp.name)
                        .font(.system(size: 11.5, weight: .medium))
                    Text(selectedApp.bundleID)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    Button("清除") {
                        self.selectedApp = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Theme.surface2(scheme),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }

            if !domainInput.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty {
                if let normalizedDomain {
                    HStack(spacing: 6) {
                        Text("将使用：\(normalizedDomain)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        if let builtIn = store.builtInMapping(
                            for: normalizedDomain
                        ) {
                            Text("覆盖内置的 \(builtIn.appName)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.accentInk(scheme))
                        }
                    }
                } else {
                    Text("域名无效，请输入例如 bilibili.com。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.warningInk(scheme))
                }
            }

            HStack(spacing: 9) {
                Button("添加映射") {
                    addMapping()
                }
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: true)
                )
                .disabled(
                    normalizedDomain == nil || selectedApp == nil
                )
                .opacity(
                    normalizedDomain == nil || selectedApp == nil ? 0.5 : 1
                )

                if let validationMessage {
                    Text(validationMessage)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.warningInk(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var builtInMappingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("内置映射")

            VStack(spacing: 0) {
                ForEach(
                    store.builtIns.sorted { $0.domain < $1.domain }
                ) { mapping in
                    mappingRow(
                        mapping: mapping,
                        trailing: AnyView(
                            Text(
                                store.isCustomized(domain: mapping.domain)
                                    ? "已覆盖"
                                    : "内置"
                            )
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(
                                Theme.surface2(scheme),
                                in: Capsule()
                            )
                        )
                    )
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.3)
    }

    private func mappingRow(
        mapping: DomainAppMapping,
        trailing: AnyView
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                mappingIcon(bundleID: mapping.bundleID)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mapping.appName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(mapping.domain)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                trailing
            }
            .padding(.vertical, 6)

            Rectangle()
                .fill(Theme.hairline(scheme).opacity(0.65))
                .frame(height: 1)
                .padding(.leading, 30)
        }
    }

    @ViewBuilder
    private func mappingIcon(bundleID: String) -> some View {
        if let image = AppCatalog.shared.icon(for: bundleID) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 21, height: 21)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 21, height: 21)
        }
    }

    private var normalizedDomain: String? {
        DomainName.normalize(domainInput)
    }

    private func addMapping() {
        guard let selectedApp else {
            validationMessage = MappingValidationError.emptyApp
                .localizedDescription
            return
        }
        do {
            try store.addMapping(
                domainInput: domainInput,
                bundleID: selectedApp.bundleID,
                appName: selectedApp.name
            )
            domainInput = ""
            self.selectedApp = nil
            validationMessage = nil
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "选择要与网站合并使用时间的 App"
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let info = AppCatalog.shared.appInfo(at: url) else {
            validationMessage = "无法读取所选 App 的 bundle identifier。"
            return
        }
        if ScreenTimeFilter.isBrowser(info.bundleID) {
            validationMessage = MappingValidationError.browserUnsupported
                .localizedDescription
            selectedApp = nil
            return
        }
        if ScreenTimeFilter.isExcluded(info.bundleID) {
            validationMessage = MappingValidationError.excludedApp
                .localizedDescription
            selectedApp = nil
            return
        }
        selectedApp = SelectedApp(
            bundleID: info.bundleID,
            name: info.name
        )
        validationMessage = nil
    }
}
