import SwiftUI

/// Root navigation for the iPhone portrait app shell (DESIGN §7).
public struct RotoskopRootView: View {
    @ObservedObject public var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            RepoListView(model: model)
        }
        .environmentObject(model)
    }
}
