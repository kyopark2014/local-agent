import SwiftUI
import AppKit

/// Half-width, transparent-knob vertical scroller for chat ScrollViews.
final class ThinTransparentScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        super.scrollerWidth(for: controlSize, scrollerStyle: scrollerStyle) * 0.5
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Keep track invisible
    }

    override func drawKnob() {
        // Transparent knob — reserve hit area without drawing
        let knob = rect(for: .knob)
        guard !knob.isEmpty else { return }
        NSColor.clear.setFill()
        knob.fill()
    }
}

/// Finds the enclosing `NSScrollView` and installs a thin transparent scroller.
struct ScrollbarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        DispatchQueue.main.async { view.configure() }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            (nsView as? ProbeView)?.configure()
        }
    }

    final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configure()
        }

        override func layout() {
            super.layout()
            configure()
        }

        func configure() {
            guard let scrollView = findScrollView() else { return }
            scrollView.scrollerStyle = .overlay
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false

            if !(scrollView.verticalScroller is ThinTransparentScroller) {
                let scroller = ThinTransparentScroller()
                scroller.controlSize = .mini
                scroller.scrollerStyle = .overlay
                scrollView.verticalScroller = scroller
            }
            scrollView.verticalScroller?.alphaValue = 0
            scrollView.verticalScroller?.controlSize = .mini
        }

        private func findScrollView() -> NSScrollView? {
            if let direct = enclosingScrollView { return direct }
            var view: NSView? = self
            while let current = view {
                if let scroll = current as? NSScrollView { return scroll }
                view = current.superview
            }
            return nil
        }
    }
}

extension View {
    /// 스크롤바 손잡이를 투명하게, 두께는 기본의 절반으로.
    func thinTransparentScrollbar() -> some View {
        background(ScrollbarConfigurator())
    }
}
