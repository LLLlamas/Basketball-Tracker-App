import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var session = GameSession()
    @StateObject private var camera = CameraManager()
    private let haptics = HapticsEngine()

    @State private var frameProcessor: FrameProcessor?
    @State private var permissionDenied = false
    @State private var showResetConfirm = false

    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color.black.ignoresSafeArea()

                if camera.isAuthorized {
                    // Camera + overlays fill the screen; UI chrome sits on top.
                    cameraStack
                    chromeOverlay
                } else {
                    PermissionView(denied: permissionDenied) {
                        Task { await requestAccess() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await requestAccess()
        }
        .onChange(of: session.hoop) { _, newHoop in
            frameProcessor?.updateHoop(newHoop)
        }
        .confirmationDialog("Reset session?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Reset", role: .destructive) { session.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all shots this session.")
        }
    }

    // MARK: - Layers

    private var cameraStack: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(hoopPlacementTap)

            HoopOverlay(session: session)
                .ignoresSafeArea()
        }
    }

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            // Top: stats bar.
            StatsBar(session: session)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Shot event toast, centered just below stats.
            ShotEventOverlay(session: session)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

            Spacer(minLength: 0)

            // Hoop placement hint (center).
            if session.hoopPlacementActive {
                placementHint
                Spacer(minLength: 0)
            }

            // Bottom: nav bar.
            BottomBar(session: session, showResetConfirm: $showResetConfirm)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
    }

    private var placementHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 28, weight: .semibold))
            Text("Tap the hoop to start tracking")
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 10)
    }

    // MARK: - Tap handling

    /// Normalized tap within the camera preview view (0...1 of its own bounds).
    /// Used as both the detection-space hoop point and the overlay draw point.
    private var hoopPlacementTap: some Gesture {
        SpatialTapGesture()
            .onEnded { event in
                guard session.hoopPlacementActive else { return }
                let bounds = UIScreen.main.bounds
                let nx = max(0, min(1, event.location.x / bounds.width))
                let ny = max(0, min(1, event.location.y / bounds.height))
                session.placeHoop(CGPoint(x: nx, y: ny))
            }
    }

    // MARK: - Permission flow

    private func requestAccess() async {
        let granted = await camera.requestAuthorization()
        if granted {
            setupPipelineIfNeeded()
            do {
                try await camera.configure()
                camera.start()
            } catch {
                // Camera config failed — camera view stays black; user can relaunch.
            }
        } else {
            permissionDenied = true
        }
    }

    private func setupPipelineIfNeeded() {
        guard frameProcessor == nil else { return }
        let processor = FrameProcessor(session: session, haptics: haptics)
        processor.updateHoop(session.hoop)
        camera.setFrameDelegate(processor)
        frameProcessor = processor
    }
}

// MARK: - Permission screen

private struct PermissionView: View {
    let denied: Bool
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "basketball.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Shot Tracker")
                .font(.largeTitle.bold())
            Text(denied
                 ? "Camera access is off. Enable it in Settings → Shot Tracker."
                 : "Enable the camera to start tracking shots.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            if denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Enable Camera", action: onRequest)
                    .buttonStyle(.borderedProminent)
            }
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    ContentView()
}
