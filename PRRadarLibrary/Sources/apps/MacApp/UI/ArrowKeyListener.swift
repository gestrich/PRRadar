import SwiftUI

struct ArrowKeyListener: NSViewRepresentable {

    let onLeft: () -> (() -> Void)?
    let onRight: () -> (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = ArrowKeyView()
        view.onLeft = onLeft
        view.onRight = onRight
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ArrowKeyView else { return }
        view.onLeft = onLeft
        view.onRight = onRight
    }
}

private class ArrowKeyView: NSView {

    var onLeft: (() -> (() -> Void)?)?
    var onRight: (() -> (() -> Void)?)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                if event.keyCode == 123, let action = self.onLeft?() {
                    action()
                    return nil
                }
                if event.keyCode == 124, let action = self.onRight?() {
                    action()
                    return nil
                }
                return event
            }
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
