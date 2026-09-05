//
//  PermissionsScreen.swift
//  RingExperience
//
//  Consent is a design surface, not a system dialog. Three cards with the exact wording of what
//  we will and will not do: Bluetooth (required), Notifications (recommended), Health (optional).
//  The Bluetooth system prompt itself is raised by the first scan on the pairing screen, at a
//  moment the app chose.
//

import SwiftUI
import UserNotifications

public struct PermissionsScreen: View {
    private let onContinue: () -> Void
    @AppStorage("ring.health.writeThrough") private var healthWriteThrough = false
    @State private var notificationsGranted: Bool?

    public init(onContinue: @escaping () -> Void) { self.onContinue = onContinue }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing16) {
                    Text("Before we pair").font(RingTypography.largeTitle).foregroundStyle(RingTheme.Content.primary)
                    card("antenna.radiowaves.left.and.right", "Bluetooth", "Required",
                         "Used only to find and talk to your ring. We never scan for other devices, and we do not use your location.") {
                        Text("iOS will ask on the next screen.").font(RingTypography.footnote).foregroundStyle(RingTheme.Content.tertiary)
                    }
                    card("bell.badge", "Notifications", "Recommended",
                         "One message at bedtime if your ring needs charging, one when your night is ready. Nothing else, and each can be switched off.") {
                        Button(notificationsGranted == true ? "Allowed" : "Allow notifications") { requestNotifications() }
                            .buttonStyle(RingSecondaryButtonStyle())
                            .disabled(notificationsGranted == true)
                    }
                    card("heart.text.square", "Health", "Optional",
                         "Writes sleep, heart rate, oxygen, breathing rate, skin temperature and steps to the Health app so your ring appears alongside other devices. We read nothing back.") {
                        Toggle("Write to Health", isOn: $healthWriteThrough).tint(RingTheme.Status.optimal)
                    }
                }
                .padding(RingTheme.Metrics.spacing24)
            }
            Button("Continue", action: onContinue).buttonStyle(RingPrimaryButtonStyle()).padding(RingTheme.Metrics.spacing24).background(RingTheme.Background.elevated)
        }
        .background(RingTheme.Background.base)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func card<Action: View>(_ symbol: String, _ title: String, _ badge: String, _ body: String, @ViewBuilder action: () -> Action) -> some View {
        VStack(alignment: .leading, spacing: RingTheme.Metrics.spacing12) {
            HStack {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(RingTheme.Brand.ink)
                Text(title).font(RingTypography.headline).foregroundStyle(RingTheme.Content.primary)
                Spacer()
                Text(badge).font(RingTypography.caption).fontWeight(.semibold).foregroundStyle(RingTheme.Content.tertiary)
            }
            Text(body).font(RingTypography.subheadline).foregroundStyle(RingTheme.Content.secondary).fixedSize(horizontal: false, vertical: true)
            action()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringCard()
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { notificationsGranted = granted }
        }
    }
}

#Preview { NavigationStack { PermissionsScreen(onContinue: {}) } }
