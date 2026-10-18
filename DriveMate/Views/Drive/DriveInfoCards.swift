import SwiftUI

/// Kafelek oferty miejsca (restauracja / stacja) — zdjęcie Look Around na górze.
struct PlaceOfferCard: View {
    var photo: UIImage?
    var placeholderSystemName: String
    var title: String
    var subtitle: String
    var accentLabel: String
    var footnote: String? = nil
    var confirmTitle: String = "Zatwierdź"
    var cancelTitle: String = "Anuluj"
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
                    Text(cancelTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .driveTileGlassCapsule(interactive: true)
                        .overlay { Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.9) }
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text(confirmTitle)
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
        .driveTileGlassRect(cornerRadius: 24)
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

struct StoreOfferPopup: View {
    let offer: StoreOffer
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        PlaceOfferCard(
            photo: offer.snapshotImage,
            placeholderSystemName: "bag.fill",
            title: offer.name,
            subtitle: offer.address.isEmpty ? "\(offer.brandLabel) · Apple Maps" : offer.address,
            accentLabel: offer.distanceLabel,
            onConfirm: onConfirm,
            onCancel: onCancel
        )
    }
}

struct ArrivalConfirmPopup: View {
    var destinationTitle: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        PlaceOfferCard(
            photo: nil,
            placeholderSystemName: "flag.checkered",
            title: "Ukończyć trasę?",
            subtitle: "Jesteś przy: \(destinationTitle)",
            accentLabel: "≤ 20 m",
            confirmTitle: "Tak",
            cancelTitle: "Nie",
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
                    Text("Paliwo na trasie")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    infoRow(label: "Dystans", value: String(format: "%.1f km", distanceKm), accent: true)
                    infoRow(
                        label: "Zużycie (\(carModel))",
                        value: String(format: "%.1f l  ·  %.1f l/100 km", liters, consumption)
                    )
                    infoRow(label: "Koszt", value: String(format: "%.0f zł", costPLN), accent: true)

                    Text("Cena \(String(format: "%.2f", FuelProfile.shared.pricePLNPerLiter)) zł/l")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)

            case let .fuelGauge(levelPercent, liters, tankCapacity, rangeKm, carModel, costToFill):
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Paliwo")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(Int((levelPercent * 100).rounded()))%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(gaugeColor(levelPercent))
                    }

                    fuelBar(levelPercent: levelPercent)

                    infoRow(label: "W baku", value: String(format: "%.1f l / %.0f l", liters, tankCapacity))
                    infoRow(label: "Zasięg", value: String(format: "%.0f km", rangeKm), accent: true)
                    if costToFill > 0.5 {
                        infoRow(
                            label: "Do pełnego",
                            value: String(format: "%.0f zł", costToFill)
                        )
                    }

                    Text(carModel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)

            case let .capabilities(items):
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Co umiem")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Text("Zamknij · 10 s")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(DriveMatePalette.limeRoute)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 6)
                                Text(item)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)

            case let .puzzle(category, prompt):
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Łamigówka")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Text("Czytam…")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Text(category.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(DriveMatePalette.limeRoute)

                    Text(prompt)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Odpowiedź na głos · „nie wiem” = podpowiedź · „powtórz zagadkę”")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
        }
        .frame(maxWidth: 420)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .driveTileGlassRect(cornerRadius: 24)
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

    private func fuelBar(levelPercent: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(gaugeColor(levelPercent))
                    .frame(width: max(6, geo.size.width * min(max(levelPercent, 0), 1)))
                if levelPercent <= FuelProfile.reservePercent {
                    Capsule()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1)
                }
            }
        }
        .frame(height: 14)
    }

    private func gaugeColor(_ levelPercent: Double) -> Color {
        if levelPercent <= FuelProfile.reservePercent { return .orange }
        if levelPercent <= 0.25 { return .yellow }
        return DriveMatePalette.limeRoute
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
