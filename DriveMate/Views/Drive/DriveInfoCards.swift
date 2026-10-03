import SwiftUI

/// Kafelek oferty miejsca (restauracja / stacja) — zdjęcie Look Around na górze.
struct PlaceOfferCard: View {
    var photo: UIImage?
    var placeholderSystemName: String
    var title: String
    var subtitle: String
    var accentLabel: String
    var footnote: String? = nil
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .overlay {
                                Image(systemName: placeholderSystemName)
                                    .font(.system(size: 36, weight: .semibold))
                                    .foregroundStyle(DriveMatePalette.limeRoute)
                            }
                    }
                }
                .frame(height: 168)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 24,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 24,
                        style: .continuous
                    )
                )

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
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 24,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
                Text(accentLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DriveMatePalette.limeRoute)
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(3)
                }
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
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .liquidGlassRect(cornerRadius: 24, .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(.horizontal, 24)
    }
}

struct RestaurantOfferPopup: View {
    let offer: RestaurantOffer
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        PlaceOfferCard(
            photo: offer.snapshotImage,
            placeholderSystemName: "fork.knife",
            title: offer.name,
            subtitle: offer.address.isEmpty ? "Restauracja · Apple Maps" : offer.address,
            accentLabel: offer.distanceLabel,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }
}

struct GasStationOfferPopup: View {
    let offer: GasStationOffer
    var nearbySummary: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        PlaceOfferCard(
            photo: offer.photo,
            placeholderSystemName: "fuelpump.fill",
            title: offer.name,
            subtitle: offer.address.isEmpty ? "Stacja paliw · Apple Maps" : offer.address,
            accentLabel: offer.distanceLabel,
            footnote: offer.preferCheapestContext && !nearbySummary.isEmpty
                ? "Brak live cen · \(nearbySummary)"
                : nil,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }
}

/// Okienko info (ulica / paliwo) — zamykane po TTS + 1.5 s.
struct DriveInfoCardPopup: View {
    let card: DriveInfoCard

    var body: some View {
        VStack(spacing: 0) {
            switch card {
            case let .street(title, body, image):
                photoHeader(image: image, placeholder: "road.lanes")
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(body)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)

            case let .fuelCost(distanceKm, liters, costPLN, carModel, consumption):
                VStack(alignment: .leading, spacing: 14) {
                    Text("Koszt paliwa")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    infoRow(label: "Długość trasy", value: String(format: "%.1f km", distanceKm))
                    infoRow(
                        label: "Zużycie (\(carModel))",
                        value: String(format: "%.1f l  ·  %.1f l/100 km", liters, consumption)
                    )
                    infoRow(label: "Szacowany koszt", value: String(format: "%.0f zł", costPLN), accent: true)

                    Text("Cena orientacyjna \(String(format: "%.2f", CarFuelEstimator.defaultFuelPricePLNPerLiter)) zł/l")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
        }
        .frame(maxWidth: 420)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .liquidGlassRect(cornerRadius: 24, .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
        .padding(.horizontal, 24)
    }

    private func photoHeader(image: UIImage?, placeholder: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .overlay {
                            Image(systemName: placeholder)
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundStyle(DriveMatePalette.limeRoute)
                        }
                }
            }
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 24,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 24,
                    style: .continuous
                )
            )

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
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
    }

    private func infoRow(label: String, value: String, accent: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: accent ? 20 : 15, weight: .bold, design: .rounded))
                .foregroundStyle(accent ? DriveMatePalette.limeRoute : .white)
        }
    }
}
