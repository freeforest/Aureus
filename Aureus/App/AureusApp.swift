import SwiftUI

@main
struct AureusApp: App {
    @State private var model: AppModel

    init() {
        _model = State(
            initialValue: AppModel(launchConfiguration: .current())
        )
    }

    var body: some Scene {
        WindowGroup("Aureus") {
            AppRootView(model: model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1_080, height: 700)
    }
}
