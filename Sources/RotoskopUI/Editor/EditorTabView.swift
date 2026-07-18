import SwiftUI

/// Editor tab: one open file, autosave, ⋯ menu (DESIGN §3 / §7.2).
struct EditorTabView: View {
    @ObservedObject var workspace: ProjectWorkspace

    var body: some View {
        Group {
            if workspace.openFilePath == nil {
                ContentUnavailableView(
                    "No File Open",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    description: Text("Open a file from the Files tab.")
                )
            } else {
                VStack(spacing: 0) {
                    if let banner = workspace.diagnosticBanner {
                        Text(banner)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.08))
                    }
                    CodeEditorView(
                        text: Binding(
                            get: { workspace.documentText },
                            set: { workspace.applyEditorText($0) }
                        ),
                        fileKind: workspace.openFileKind,
                        revealLine: workspace.revealLine,
                        revealColumn: workspace.revealColumn,
                        onRevealConsumed: {
                            workspace.revealLine = nil
                            workspace.revealColumn = nil
                        }
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    #if os(iOS)
                    Button("Select") { notifySelect() }
                    Button("Select All") { notifySelectAll() }
                    Divider()
                    Button("Cut") { notifyCut() }
                    Button("Copy") { notifyCopy() }
                    Button("Paste") { notifyPaste() }
                    Button("Undo") { notifyUndo() }
                    Divider()
                    #endif
                    Button("Save Now") { _ = workspace.saveDocumentNow() }
                        .disabled(!workspace.isDocumentDirty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if workspace.openFilePath != nil {
                HStack {
                    Text(workspace.openFilePath ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if workspace.isDocumentDirty {
                        Text("Editing…")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let status = workspace.statusMessage {
                        Text(status)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }
        }
    }

    #if os(iOS)
    private func notifySelect() {
        NotificationCenter.default.post(name: .rotoskopEditorSelect, object: nil)
    }

    private func notifySelectAll() {
        NotificationCenter.default.post(name: .rotoskopEditorSelectAll, object: nil)
    }

    private func notifyCut() {
        UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.cut(_:)), to: nil, from: nil, for: nil)
    }

    private func notifyCopy() {
        UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: nil, for: nil)
    }

    private func notifyPaste() {
        UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.paste(_:)), to: nil, from: nil, for: nil)
    }

    private func notifyUndo() {
        UIApplication.shared.sendAction(Selector(("undo:")), to: nil, from: nil, for: nil)
    }
    #endif
}

#if os(iOS)
import UIKit

extension Notification.Name {
    static let rotoskopEditorSelect = Notification.Name("rotoskopEditorSelect")
    static let rotoskopEditorSelectAll = Notification.Name("rotoskopEditorSelectAll")
}
#endif
