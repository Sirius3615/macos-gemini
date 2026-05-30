import SwiftUI

/// The view displayed in the MenuBarExtra popover.
/// Shows permission status, API key config, model selection, and a quit button.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var permissions: PermissionsManager
    @EnvironmentObject var shakeDetector: ShakeDetector
    @ObservedObject private var settings = SettingsManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("AI Context")
                    .font(.system(size: 14, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Permissions section
            VStack(alignment: .leading, spacing: 8) {
                if permissions.isAccessibilityGranted && permissions.isScreenRecordingGranted && permissions.isCalendarGranted {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("Permissions Active")
                            .font(.system(size: 13, weight: .medium))
                    }
                } else {
                    Text("Permissions Required")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.red)
                        .textCase(.uppercase)

                    permissionRow(
                        title: "Accessibility",
                        icon: "hand.point.up.braille",
                        isGranted: permissions.isAccessibilityGranted,
                        action: permissions.openAccessibilitySettings
                    )

                    permissionRow(
                        title: "Screen Recording",
                        icon: "rectangle.dashed.badge.record",
                        isGranted: permissions.isScreenRecordingGranted,
                        action: permissions.openScreenRecordingSettings
                    )

                    permissionRow(
                        title: "Calendar",
                        icon: "calendar",
                        isGranted: permissions.isCalendarGranted,
                        action: permissions.openCalendarSettings
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()
            
            // Persona Quick Toggle
            VStack(alignment: .leading, spacing: 6) {
                Text("PERSONA")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .padding(.bottom, 2)
                
                ForEach(Array(settings.personas.enumerated()), id: \.element.id) { index, persona in
                    Button {
                        settings.activePersonaIndex = index
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: persona.icon)
                                .font(.system(size: 11))
                                .frame(width: 16)
                                .foregroundStyle(settings.activePersonaIndex == index ? .white : .secondary)
                            Text(persona.name)
                                .font(.system(size: 12, weight: settings.activePersonaIndex == index ? .semibold : .regular))
                            Spacer()
                            if settings.activePersonaIndex == index {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.purple)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            Divider()

            // Status
            HStack(spacing: 6) {
                Circle()
                    .fill(shakeDetector.isMonitoring ? .green : .orange)
                    .frame(width: 7, height: 7)
                Text(shakeDetector.isMonitoring ? "Monitoring active" : "Not monitoring")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            // Open Chat button
            Button(action: {
                ChatWindowManager.shared.openRegularChatWindow()
            }) {
                HStack {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Open Chat Window")
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            // Settings button
            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" || $0.title == "Settings" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            // Quit button
            Button(action: { NSApplication.shared.terminate(nil) }) {
                HStack {
                    Image(systemName: "power")
                    Text("Quit")
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .padding(.bottom, 4)
        }
        .frame(width: 300)
    }

    private func permissionRow(
        title: String,
        icon: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 12))
                .frame(width: 20)
                .foregroundStyle(isGranted ? .green : .orange)

            Text(title)
                .font(.system(size: 13))

            Spacer()

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
