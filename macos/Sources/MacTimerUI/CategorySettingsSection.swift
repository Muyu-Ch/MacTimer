import AppKit
import SwiftUI
import MacTimerCore

struct CategorySettingsSection: View {
    @ObservedObject var model: DashboardModel
    @ObservedObject var store: CategoryStore
    @Environment(\.colorScheme) private var scheme

    @State private var editor: CategoryEditorState?
    @State private var pendingCategoryDeletion: UsageCategory?

    @State private var categoryPopoverTarget: CategoryRuleTarget?
    @State private var targetSearch = ""
    @State private var showAllTargets = false
    @State private var ruleError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Text("把 App 和网站归入学习、工作、娱乐等分类，统计页会按分类汇总时长。App 规则优先于网站规则；没有匹配规则的项目归入「未分类」，并始终使用灰色显示。")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            categoriesSection
            Divider()
                .overlay(Theme.hairline(scheme))
            assignSection
            Divider()
                .overlay(Theme.hairline(scheme))
            rulesSection
        }
        .padding(18)
        .stayCard(scheme)
        .sheet(item: $editor) { state in
            CategoryEditorSheet(store: store, state: state)
        }
        .alert(
            "删除分类？",
            isPresented: Binding(
                get: { pendingCategoryDeletion != nil },
                set: { if !$0 { pendingCategoryDeletion = nil } }
            ),
            presenting: pendingCategoryDeletion
        ) { category in
            Button("删除", role: .destructive) {
                store.removeCategory(id: category.id)
                pendingCategoryDeletion = nil
            }
            Button("取消", role: .cancel) {
                pendingCategoryDeletion = nil
            }
        } message: { category in
            Text("“\(category.name)”及其 \(ruleCount(for: category)) 条归类规则会被删除，相关时长将归入未分类。")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("分类标签")
                    .font(.system(size: 14, weight: .semibold))
                Text("\(store.categories.count) 个分类 · \(store.rules.count) 条规则")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            Button {
                editor = CategoryEditorState(
                    id: UUID().uuidString,
                    categoryID: nil,
                    initialName: "",
                    initialColorHex: CategoryPalette.presetColors[0]
                )
            } label: {
                Label("新建分类", systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(
                CompactActionButtonStyle(scheme: scheme, emphasized: false)
            )
            .help("新建一个自定义分类")
        }
    }

    // MARK: - Categories

    @ViewBuilder
    private var categoriesSection: some View {
        if store.categories.isEmpty {
            Text("还没有分类。新建分类后即可添加归类规则。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 0) {
                ForEach(store.categories) { category in
                    categoryRow(category)
                }
            }
        }
    }

    private func categoryRow(_ category: UsageCategory) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Circle()
                    .fill(Color(hex: category.colorHex) ?? Theme.accent(scheme))
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                Theme.border(scheme),
                                lineWidth: 0.5
                            )
                    )

                Text(category.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text("\(ruleCount(for: category)) 条规则")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Spacer(minLength: 8)

                Button {
                    editor = CategoryEditorState(
                        id: category.id,
                        categoryID: category.id,
                        initialName: category.name,
                        initialColorHex: category.colorHex
                    )
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("修改名称和颜色")

                Button {
                    pendingCategoryDeletion = category
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除分类及关联规则")
            }
            .padding(.vertical, 6)

            Rectangle()
                .fill(Theme.hairline(scheme).opacity(0.65))
                .frame(height: 1)
                .padding(.leading, 19)
        }
    }

    private func ruleCount(for category: UsageCategory) -> Int {
        store.rules.filter { $0.categoryID == category.id }.count
    }

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("归类规则")

            if store.rules.isEmpty {
                Text("还没有归类规则。点击上方记录右侧的标签即可设置。")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(sortedRules) { rule in
                        ruleRow(rule)
                    }
                }
            }
        }
    }

    private var sortedRules: [CategoryRule] {
        store.rules.sorted { left, right in
            if left.kind != right.kind {
                return left.kind == .app
            }
            return left.displayName.localizedStandardCompare(
                right.displayName
            ) == .orderedAscending
        }
    }

    private func ruleRow(_ rule: CategoryRule) -> some View {
        let category = store.category(id: rule.categoryID)
        let tint = category.flatMap { Color(hex: $0.colorHex) }
            ?? Theme.accent(scheme)

        return VStack(spacing: 0) {
            HStack(spacing: 9) {
                ruleIcon(rule)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(
                        rule.kind == .app
                            ? rule.identifier
                            : "网站 · \(rule.identifier)"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                    Text(category?.name ?? "未分类")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.12), in: Capsule())

                Button {
                    store.removeRule(id: rule.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除这条归类规则")
            }
            .padding(.vertical, 6)

            Rectangle()
                .fill(Theme.hairline(scheme).opacity(0.65))
                .frame(height: 1)
                .padding(.leading, 30)
        }
    }

    @ViewBuilder
    private func ruleIcon(_ rule: CategoryRule) -> some View {
        if rule.kind == .app,
           let image = AppCatalog.shared.icon(for: rule.identifier) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 21, height: 21)
        } else {
            Image(
                systemName: rule.kind == .app ? "app.fill" : "globe"
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 21, height: 21)
        }
    }

    // MARK: - Assign categories

    private var assignSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("给记录设置标签")

            Text("点击每行右侧的标签即可选择分类；列表包含全部历史记录，不要求今天有使用。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            targetSearchField
            targetList

            if let ruleError {
                Text(ruleError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.warningInk(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("应用规则优先于网站规则；选择「清除分类」可恢复未分类。")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(
            Theme.surface2(scheme),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 1)
        )
    }

    private var targetSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            TextField("搜索已记录的网站或 App", text: $targetSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))

            if !targetSearch.isEmpty {
                Button {
                    targetSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Theme.card(scheme),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Theme.border(scheme), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var targetList: some View {
        if filteredTargets.isEmpty {
            Text(
                model.categoryRuleTargets.isEmpty
                    ? "还没有已记录的网站或 App。使用一段时间后再来归类。"
                    : "没有匹配的记录。"
            )
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 4)
        } else {
            VStack(spacing: 0) {
                ForEach(visibleTargets) { target in
                    targetRow(target)
                }
            }
            .background(
                Theme.card(scheme),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.border(scheme), lineWidth: 1)
            )

            if filteredTargets.count > 6 {
                Button(showAllTargets ? "收起列表" : "显示全部 \(filteredTargets.count) 项") {
                    showAllTargets.toggle()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.accentInk(scheme))
            }
        }
    }

    private func targetRow(_ target: CategoryRuleTarget) -> some View {
        let currentCategory = category(for: target)

        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                targetIcon(target)

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text(targetSubtitle(target))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Text(
                    DurationText.compact(
                        milliseconds: target.milliseconds
                    )
                )
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()

                categoryTagButton(target, current: currentCategory)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)

            Rectangle()
                .fill(Theme.hairline(scheme).opacity(0.55))
                .frame(height: 1)
                .padding(.leading, 38)
        }
    }

    private func categoryTagButton(
        _ target: CategoryRuleTarget,
        current: UsageCategory?
    ) -> some View {
        let tint = current.flatMap { Color(hex: $0.colorHex) }
            ?? Color(hex: CategoryStore.uncategorizedColorHex)
            ?? Theme.accent(scheme)

        return Button {
            if categoryPopoverTarget?.id == target.id {
                categoryPopoverTarget = nil
            } else {
                categoryPopoverTarget = target
            }
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(current?.name ?? "未分类")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(
                        current == nil ? Color.secondary : Color.primary
                    )
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(0.22), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("点击选择标签")
        .popover(
            isPresented: categoryPopoverBinding(for: target),
            arrowEdge: .bottom
        ) {
            categoryPopover(for: target, current: current)
        }
    }

    private func categoryPopoverBinding(
        for target: CategoryRuleTarget
    ) -> Binding<Bool> {
        Binding(
            get: { categoryPopoverTarget?.id == target.id },
            set: { isPresented in
                if !isPresented,
                   categoryPopoverTarget?.id == target.id {
                    categoryPopoverTarget = nil
                }
            }
        )
    }

    private func categoryPopover(
        for target: CategoryRuleTarget,
        current: UsageCategory?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("选择标签")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 2)

            if store.categories.isEmpty {
                Text("还没有分类，请先在上方新建分类。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
            } else {
                ForEach(store.categories) { category in
                    categoryMenuButton(
                        target: target,
                        category: category,
                        current: current
                    )
                }

                if current != nil {
                    Divider()
                        .overlay(Theme.hairline(scheme))
                        .padding(.vertical, 3)
                    clearCategoryButton(target)
                }
            }
        }
        .padding(6)
        .frame(width: 200, alignment: .leading)
    }

    private func categoryMenuButton(
        target: CategoryRuleTarget,
        category: UsageCategory,
        current: UsageCategory?
    ) -> some View {
        let selected = current?.id == category.id
        let tint = Color(hex: category.colorHex) ?? Theme.accent(scheme)

        return Button {
            assign(target, to: category)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(category.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accentInk(scheme))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                selected ? Theme.surface2(scheme) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func clearCategoryButton(
        _ target: CategoryRuleTarget
    ) -> some View {
        Button {
            assign(target, to: nil)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(
                        Color(hex: CategoryStore.uncategorizedColorHex)
                            ?? .secondary
                    )
                    .frame(width: 8, height: 8)
                Text("清除分类")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func targetSubtitle(_ target: CategoryRuleTarget) -> String {
        switch target.kind {
        case .app:
            if let detail = target.detail,
               detail != "App",
               !detail.isEmpty {
                return "App · \(detail)"
            }
            return "App · \(target.identifier)"
        case .domain:
            return "网站 · \(target.identifier)"
        }
    }

    @ViewBuilder
    private func targetIcon(_ target: CategoryRuleTarget) -> some View {
        if target.kind == .app,
           let image = AppCatalog.shared.icon(for: target.identifier) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
        } else {
            Image(
                systemName: target.kind == .app ? "app.fill" : "globe"
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
        }
    }

    private var filteredTargets: [CategoryRuleTarget] {
        let query = targetSearch.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let all = model.categoryRuleTargets
        guard !query.isEmpty else { return all }
        return all.filter { target in
            target.name.localizedCaseInsensitiveContains(query)
                || target.identifier.localizedCaseInsensitiveContains(query)
                || (target.detail?.localizedCaseInsensitiveContains(query)
                    ?? false)
        }
    }

    private var visibleTargets: [CategoryRuleTarget] {
        guard !showAllTargets else { return filteredTargets }
        return Array(filteredTargets.prefix(6))
    }

    private func category(
        for target: CategoryRuleTarget
    ) -> UsageCategory? {
        switch target.kind {
        case .app:
            return store.category(forBundleID: target.identifier)
        case .domain:
            return store.category(forDomain: target.identifier)
        }
    }

    private func assign(
        _ target: CategoryRuleTarget,
        to category: UsageCategory?
    ) {
        defer { categoryPopoverTarget = nil }

        do {
            if let category {
                switch target.kind {
                case .app:
                    try store.addAppRule(
                        bundleID: target.identifier,
                        appName: target.name,
                        categoryID: category.id
                    )
                case .domain:
                    try store.addDomainRule(
                        domainInput: target.identifier,
                        categoryID: category.id
                    )
                }
            } else {
                store.removeRule(
                    kind: target.kind,
                    identifier: target.identifier
                )
            }
            ruleError = nil
        } catch {
            ruleError = error.localizedDescription
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.3)
    }
}

// MARK: - Editor

private struct CategoryEditorState: Identifiable {
    let id: String
    let categoryID: String?
    let initialName: String
    let initialColorHex: String
}

private struct CategoryEditorSheet: View {
    @ObservedObject var store: CategoryStore
    let state: CategoryEditorState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var name: String
    @State private var colorHex: String
    @State private var errorMessage: String?

    init(store: CategoryStore, state: CategoryEditorState) {
        self.store = store
        self.state = state
        _name = State(initialValue: state.initialName)
        _colorHex = State(initialValue: state.initialColorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(state.categoryID == nil ? "新建分类" : "编辑分类")
                    .font(.system(size: 18, weight: .semibold))
                Text("分类名称会显示在统计页，颜色用于区分不同分类。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("分类名称，如 阅读", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit(save)

            VStack(alignment: .leading, spacing: 8) {
                Text("颜色")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(28), spacing: 8),
                        count: 6
                    ),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(CategoryPalette.presetColors, id: \.self) { hex in
                        presetSwatch(hex)
                    }
                }

                HStack(spacing: 8) {
                    ColorPicker(
                        "自定义颜色",
                        selection: colorBinding,
                        supportsOpacity: false
                    )
                    .font(.system(size: 11))

                    Spacer()

                    Text(colorHex.uppercased())
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: colorHex) ?? Theme.accent(scheme))
                    .frame(width: 9, height: 9)
                Text(
                    name.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                        ? "分类预览"
                        : name.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                )
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    (Color(hex: colorHex) ?? Theme.accent(scheme))
                        .opacity(0.12),
                    in: Capsule()
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.warningInk(scheme))
            }

            HStack(spacing: 8) {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: false)
                )
                Button("保存") {
                    save()
                }
                .buttonStyle(
                    CompactActionButtonStyle(scheme: scheme, emphasized: true)
                )
                .disabled(trimmedName.isEmpty)
                .opacity(trimmedName.isEmpty ? 0.5 : 1)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.page(scheme))
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: colorHex) ?? .blue },
            set: { colorHex = $0.hexString ?? colorHex }
        )
    }

    private func presetSwatch(_ hex: String) -> some View {
        let selected = colorHex.uppercased() == hex.uppercased()
        return Button {
            colorHex = hex
        } label: {
            Circle()
                .fill(Color(hex: hex) ?? .blue)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .strokeBorder(
                            selected ? Color.primary : Theme.border(scheme),
                            lineWidth: selected ? 2 : 0.5
                        )
                        .padding(-2)
                )
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("使用颜色 \(hex)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func save() {
        guard !trimmedName.isEmpty else {
            errorMessage = CategoryStoreError.invalidName.localizedDescription
            return
        }
        if let categoryID = state.categoryID {
            store.renameCategory(id: categoryID, name: trimmedName)
            store.setColor(id: categoryID, colorHex: colorHex)
        } else {
            do {
                _ = try store.addCategory(
                    name: trimmedName,
                    colorHex: colorHex
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        dismiss()
    }
}
