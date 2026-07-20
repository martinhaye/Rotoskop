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
                        filePath: workspace.openFilePath,
                        restoredScrollOffset: workspace.savedScrollOffset,
                        onScrollOffsetChange: { workspace.updateScrollOffset($0) },
                        revealLine: workspace.revealLine,
                        revealColumn: workspace.revealColumn,
                        onRevealConsumed: {
                            workspace.revealLine = nil
                            workspace.revealColumn = nil
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}

#if os(iOS)
import UIKit

extension Notification.Name {
    static let rotoskopEditorSelect = Notification.Name("rotoskopEditorSelect")
    static let rotoskopEditorSelectAll = Notification.Name("rotoskopEditorSelectAll")
}
#endif
