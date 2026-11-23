import AppKit
import SwiftUI

public struct MacTimerAboutView: View {
    @Environment(\.colorScheme) private var scheme
    private let previewMode: Bool

    public init(previewMode: Bool = false) {
        self.previewMode = previewMode
    }

    public var body: some View {
        Group {
            if previewMode {
                aboutContent
            } else {
                ScrollView {
                    aboutContent
                }
            }
        }
        .background(Theme.page(scheme).ignoresSafeArea())
        .frame(minWidth: 620, minHeight: 660)
        .tint(Theme.accent(scheme))
    }

    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            basicInfo
            developerInfo
            supportInfo
            footer
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 16) {
            appIcon

            VStack(alignment: .leading, spacing: 4) {
                Text("MacTimer")
                    .font(.system(size: 28, weight: .semibold))
                Text("版本 \(version)（build \(build)）")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Text("本地优先的屏幕使用时间统计")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var basicInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("关于")
                .font(.system(size: 14, weight: .semibold))

            Text("MacTimer 把 Chrome 网页停留时间和 Apple 屏幕使用时间里的 App 时长合并在一起。数据只在本机读取和保存，不联网、不上传。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            infoRow("数据来源", "Chrome 扩展 + Apple Screen Time")
            infoRow("数据存储", "仅保存在本机")
            infoRow("开源协议", "MIT License")

            Link(
                destination: URL(string: "https://github.com/Muyu-Ch/MacTimer")!
            ) {
                Label(
                    "github.com/Muyu-Ch/MacTimer",
                    systemImage: "arrow.up.right.square"
                )
                .font(.system(size: 11))
                .foregroundStyle(Theme.accentInk(scheme))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .stayCard(scheme)
    }

    private var developerInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("开发者")
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 11) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Theme.accentInk(scheme))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Muyu-Ch")
                        .font(.system(size: 14, weight: .semibold))
                    Text("独立开发者")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Link(destination: URL(string: "https://github.com/Muyu-Ch")!) {
                    Label("GitHub", systemImage: "link")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accentInk(scheme))
                }
                .buttonStyle(.plain)
            }

            Text("如果 MacTimer 对你有帮助，喜欢的话可以支持我一下 ☕️")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .stayCard(scheme)
    }

    private var supportInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("支持我")
                .font(.system(size: 14, weight: .semibold))

            HStack(alignment: .top, spacing: 18) {
                paymentCard(
                    imageName: "wechat",
                    title: "微信支付",
                    accessibilityLabel: "微信支付收款码"
                )
                paymentCard(
                    imageName: "alipay",
                    title: "支付宝",
                    accessibilityLabel: "支付宝收款码"
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(18)
        .stayCard(scheme)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func paymentCard(
        imageName: String,
        title: String,
        accessibilityLabel: String
    ) -> some View {
        VStack(spacing: 8) {
            Group {
                if let image = paymentImage(named: imageName) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 24, weight: .light))
                        Text("收款码未打包")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: 200, height: 285)
            .padding(8)
            .background(
                Color.white,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.border(scheme), lineWidth: 1)
            )
            .accessibilityLabel(accessibilityLabel)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        Text("© 2026 Muyu-Ch · MIT License · 非 Apple 官方产品")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let image = bundledAppIcon
            ?? NSApplication.shared.applicationIconImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 74, height: 74)
        } else {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.accentInk(scheme))
                .frame(width: 74, height: 74)
                .background(Theme.accentWash(scheme), in: Circle())
        }
    }

    private var bundledAppIcon: NSImage? {
        guard let url = Bundle.main.url(
            forResource: "AppIcon",
            withExtension: "icns"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var version: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "1.4.0"
    }

    private var build: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "8"
    }

    private func paymentImage(named name: String) -> NSImage? {
        if let url = Bundle.main.url(
            forResource: name,
            withExtension: "png",
            subdirectory: "Support"
        ), let image = NSImage(contentsOf: url) {
            return image
        }

        if let directory = ProcessInfo.processInfo.environment[
            "MACTIMER_SUPPORT_IMAGE_DIR"
        ], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory)
                .appendingPathComponent("\(name).png")
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }

        return nil
    }
}
