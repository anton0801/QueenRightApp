import SwiftUI

struct UnreachableView: View {
    let message: String

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                CombGround()
                
                Image("queenr")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .ignoresSafeArea()
                    .blur(radius: 2)
                    .opacity(0.8)
                
                VStack(spacing: Space.gap) {
                    
                    Image("error_title")
                        .resizable()
                        .frame(width: 200, height: 60)
                    
                    Image("dialog_error")
                        .resizable()
                        .frame(width: 260, height: 205)
//                    Spacer()
//                    
//                    Hexagon()
//                        .stroke(Palette.hairlineStrong, lineWidth: 1.5)
//                        .frame(width: 68, height: 76)
//                        .overlay {
//                            Image(systemName: "wifi.slash")
//                                .font(.system(size: 24, weight: .light))
//                                .foregroundStyle(Palette.textSecondary)
//                        }
//                    
//                    VStack(spacing: Space.tight) {
//                        Text("Can’t reach the server")
//                            .font(Typo.display)
//                            .foregroundStyle(Palette.textPrimary)
//                            .multilineTextAlignment(.center)
//                        
//                        Text(message)
//                            .font(Typo.body)
//                            .foregroundStyle(Palette.textSecondary)
//                            .multilineTextAlignment(.center)
//                            .fixedSize(horizontal: false, vertical: true)
//                    }
//                    
//                    Spacer()
//                    Spacer()
                }
                .padding(Space.screen)
            }
            .accessibilityElement(children: .contain)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    UnreachableView(message: "Check your connection and try again.")
}
