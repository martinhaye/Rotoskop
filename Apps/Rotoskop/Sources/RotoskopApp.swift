import SwiftUI
import RotoskopGit
import RotoskopUI

@main
struct RotoskopApp: App {
    @StateObject private var model: AppModel

    init() {
        let built: AppModel
        do {
            built = try AppModel.makeDefault()
        } catch {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("Rotoskop-Fallback", isDirectory: true)
            let pat = KeychainPATStore()
            let store = (try? ProjectStore(rootURL: temp, patStore: pat))
                ?? (try! ProjectStore(
                    rootURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("Rotoskop-\(UUID().uuidString)", isDirectory: true),
                    patStore: pat
                ))
            built = AppModel(store: store, patStore: pat)
        }
        _model = StateObject(wrappedValue: built)
    }

    var body: some Scene {
        WindowGroup {
            RotoskopRootView(model: model)
        }
    }
}
