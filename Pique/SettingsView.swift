//  SettingsView.swift
//  Pique
//
//  Settings sheet for configuring per-extension appearance overrides.

import SwiftUI

struct SettingsView: View {
    // Groups of (display label, file extensions) for all supported formats.
    private let formatGroups: [(name: String, icon: String, color: Color, extensions: [String])] = [
        ("JSON",         "doc.text",                              .orange, ["json"]),
        ("YAML",         "doc.text",                              .purple, ["yaml", "yml"]),
        ("TOML",         "doc.text",                              .blue,   ["toml", "lock"]),
        ("XML",          "doc.text",                              .green,  ["xml", "recipe"]),
        ("mobileconfig", "lock.doc",                              .red,    ["mobileconfig", "plist"]),
        ("Shell",        "terminal",                              .mint,   ["sh", "bash", "zsh", "ksh", "dash", "rc", "command"]),
        ("PowerShell",   "terminal",                              .blue,   ["ps1", "psm1", "psd1"]),
        ("Python",       "chevron.left.forwardslash.chevron.right", .cyan, ["py", "pyw", "pyi"]),
        ("Ruby",         "chevron.left.forwardslash.chevron.right", .red,  ["rb"]),
        ("Go",           "chevron.left.forwardslash.chevron.right", .teal, ["go"]),
        ("Rust",         "chevron.left.forwardslash.chevron.right", .orange, ["rs"]),
        ("JavaScript",   "chevron.left.forwardslash.chevron.right", .yellow, ["js", "jsx", "ts", "tsx", "mjs", "cjs"]),
        ("Markdown",     "doc.richtext",                          .gray,   ["md", "markdown", "adoc"]),
        ("HCL",          "doc.text",                              .indigo, ["tf", "tfvars", "hcl"]),
    ]

    // Track overrides in local state so the view refreshes when pickers change.
    @State private var overrides: [String: AppearanceOverride] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Appearance Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Text("Override the preview appearance for specific file types, independent of the macOS system appearance.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 12)

            // Format list
            List {
                ForEach(formatGroups, id: \.name) { group in
                    Section {
                        ForEach(group.extensions, id: \.self) { ext in
                            ExtensionRow(ext: ext, override: binding(for: ext))
                        }
                    } header: {
                        Label(group.name, systemImage: group.icon)
                            .foregroundStyle(group.color)
                            .font(.caption.bold())
                    }
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 480, height: 540)
        .onAppear { loadOverrides() }
    }

    private func binding(for ext: String) -> Binding<AppearanceOverride> {
        Binding(
            get: { overrides[ext] ?? .system },
            set: { newValue in
                overrides[ext] = newValue
                AppearanceSettings.setOverride(newValue, for: ext)
            }
        )
    }

    private func loadOverrides() {
        var loaded: [String: AppearanceOverride] = [:]
        for group in formatGroups {
            for ext in group.extensions {
                let o = AppearanceSettings.override(for: ext)
                if o != .system { loaded[ext] = o }
            }
        }
        overrides = loaded
    }
}

private struct ExtensionRow: View {
    let ext: String
    @Binding var override: AppearanceOverride

    var body: some View {
        HStack {
            Text(".\(ext)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(override == .system ? .secondary : .primary)
            Spacer()
            Picker("", selection: $override) {
                ForEach(AppearanceOverride.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }
}

#Preview {
    SettingsView()
}
