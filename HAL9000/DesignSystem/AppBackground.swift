import SwiftUI

struct AppBackground: View {
    var body: some View {
        ZStack {
            AppColor.heroBackground

            Circle()
                .fill(AppColor.pageGlow.opacity(0.28))
                .frame(width: 280, height: 280)
                .blur(radius: 70)
                .offset(x: -150, y: -250)

            Circle()
                .fill(AppColor.success.opacity(0.12))
                .frame(width: 220, height: 220)
                .blur(radius: 80)
                .offset(x: 160, y: 120)
        }
        .ignoresSafeArea()
    }
}
