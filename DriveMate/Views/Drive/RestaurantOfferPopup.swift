import SwiftUI
import MapKit

/// Centralne okienko oferty restauracji (zdjęcie Apple Maps + Zatwierdź / Anuluj).
struct RestaurantOfferPopup: View {
    let offer: RestaurantOffer
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let image = offer.snapshotImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .overlay {
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundStyle(DriveMatePalette.limeRoute)
                            }
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()

                HStack(spacing: 4) {
                    Image(systemName: "apple.logo").font(.system(size: 9, weight: .semibold))
                    Text("Maps")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.45)))
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(offer.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(offer.address.isEmpty ? "Restauracja · Apple Maps" : offer.address)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                Text(offer.distanceLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DriveMatePalette.limeRoute)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Anuluj")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .liquidGlassCapsule(.clear.interactive())
                        .overlay { Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.9) }
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text("Zatwierdź")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.88))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            Capsule().fill(DriveMatePalette.limeRoute)
                        }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: 420)
        .liquidGlassRect(cornerRadius: 24, .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(.horizontal, 24)
    }
}
