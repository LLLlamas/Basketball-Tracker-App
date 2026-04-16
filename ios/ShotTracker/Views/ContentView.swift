import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.isAuthorized {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()

                VStack {
                    HStack {
                        statusPill
                        Spacer()
                    }
                    .padding()
                    Spacer()
                }
            } else {
                PermissionView(denied: permissionDenied) {
                    Task { await requestAccess() }
                }
            }
        }
        .task {
            await requestAccess()
        }
    }

    private var statusPill: some View {
        Text("Camera ready")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15)))
    }

    private func requestAccess() async {
        let granted = await camera.requestAuthorization()
        if granted {
            try? await camera.configure()
            camera.start()
        } else {
            permissionDenied = true
        }
    }
}

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
