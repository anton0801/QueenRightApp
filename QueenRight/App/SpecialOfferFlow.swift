import SwiftUI

struct SpecialOfferFlow: View {


    private enum Stage { case offer, accepted }

    @State private var stage: Stage

    init(url: URL) {
        _stage = State(initialValue: NotificationOffer.shouldShow ? .offer : .accepted)
    }

    var body: some View {
        switch stage {
        case .offer:
            NotificationOfferView {
                withAnimation(.easeInOut(duration: 0.3)) { stage = .accepted }
            }
            .transition(.opacity)

        case .accepted:
            SquareView()
                .transition(.opacity)
        }
    }
    
}
