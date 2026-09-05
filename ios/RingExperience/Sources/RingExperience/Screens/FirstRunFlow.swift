//
//  FirstRunFlow.swift
//  RingExperience
//
//  J1, the only onboarding that matters: Welcome → About you → Permissions → Pairing → Fit &
//  wear → Today. Skippable at every step; a user who skips lands on Today with the learning
//  hero and the unpaired card, not on an empty dashboard.
//

import SwiftUI
import RingDiscovery

struct FirstRunFlow<DS: RingDataSource>: View {
    @ObservedObject var dataSource: DS
    let onFinish: () -> Void

    private enum Step { case profile, permissions, pairing, fit }
    @State private var step: Step = .profile
    @State private var profile: UserProfile = .draft()
    @StateObject private var pairingModel: RingPairingModel

    @MainActor init(dataSource: DS, onFinish: @escaping () -> Void) {
        self.dataSource = dataSource
        self.onFinish = onFinish
        _pairingModel = StateObject(wrappedValue: RingPairingModel(link: dataSource.pairingLink))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .profile:
                    ProfileOnboardingFlow(initial: profile) { completed in
                        profile = completed
                        Task { await dataSource.saveProfile(completed) }
                        advance(.permissions)
                    } onSkip: {
                        Task { await dataSource.saveProfile(profile) }
                        advance(.permissions)
                    }
                case .permissions:
                    PermissionsScreen { advance(.pairing) }
                case .pairing:
                    PairingScreen(model: pairingModel, demoPairing: dataSource.isDemo ? { Task { await dataSource.adoptPairedRing(id: "demo", name: "LOOP-E5FF") }; advance(.fit) } : nil, onSkip: { advance(.fit) }) { ring in
                        Task { await dataSource.adoptPairedRing(id: ring.id, name: ring.displayName) }
                        advance(.fit)
                    }
                case .fit:
                    FitAndWearScreen(profile: profile, battery: dataSource.battery, onDone: onFinish)
                }
            }
            .ringMotion(RingMotion.cardAppear, value: stepIndex)
        }
    }

    private var stepIndex: Int {
        switch step {
        case .profile: return 0
        case .permissions: return 1
        case .pairing: return 2
        case .fit: return 3
        }
    }

    private func advance(_ next: Step) { step = next }
}

#Preview {
    FirstRunFlow(dataSource: MockRingDataSource(scenario: .unpaired, profile: nil), onFinish: {})
}
