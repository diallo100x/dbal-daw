import SwiftUI
import AVFoundation
import AudioToolbox

/// Metadata discovery only. Being listed does not mean a plug-in passed a render test.
enum PluginDiscovery {
    struct Snapshot {
        var all: [PluginRef] = []
        var managerCount = 0
        var registryCount = 0
        var instruments: Int { visible(effect: false, includeApple: false).count }
        var effects: Int { visible(effect: true, includeApple: false).count }
        func visible(effect: Bool, includeApple: Bool) -> [PluginRef] {
            all.filter { PluginDiscovery.supports($0.type, effect: effect) &&
                (includeApple || $0.manufacturer != kAudioUnitManufacturer_Apple) }
        }
    }
    static func supports(_ type: OSType, effect: Bool) -> Bool {
        effect ? [kAudioUnitType_Effect, kAudioUnitType_MusicEffect].contains(type) :
            [kAudioUnitType_MusicDevice, kAudioUnitType_Generator].contains(type)
    }
    static func merge(_ manager: [PluginRef], _ registry: [PluginRef]) -> Snapshot {
        var seen = Set<String>()
        let all = (manager + registry).filter { ref in
            // Pocket FX is a private, in-process implementation, not a hosted preset.
            guard !(ref.manufacturer == 0x4442414C && ref.subtype == 0x70786678) else { return false }
            return seen.insert("\(ref.type):\(ref.subtype):\(ref.manufacturer)").inserted
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return Snapshot(all: all, managerCount: manager.count, registryCount: registry.count)
    }
    static func scan() -> Snapshot {
        var wildcard = AudioComponentDescription(componentType: 0, componentSubType: 0,
            componentManufacturer: 0, componentFlags: 0, componentFlagsMask: 0)
        let manager = AVAudioUnitComponentManager.shared().components(matching: wildcard).map { component in
            let d = component.audioComponentDescription
            return PluginRef(name: component.name, type: d.componentType,
                subtype: d.componentSubType, manufacturer: d.componentManufacturer)
        }
        var registry: [PluginRef] = []
        var previous: AudioComponent?
        while let component = AudioComponentFindNext(previous, &wildcard) {
            previous = component
            var d = wildcard
            guard AudioComponentGetDescription(component, &d) == noErr else { continue }
            var copiedName: Unmanaged<CFString>?
            let status = AudioComponentCopyName(component, &copiedName)
            let name = copiedName?.takeRetainedValue() as String?
            registry.append(PluginRef(name: status == noErr ? (name ?? "Unnamed Audio Unit") : "Unnamed Audio Unit",
                type: d.componentType, subtype: d.componentSubType, manufacturer: d.componentManufacturer))
        }
        return merge(manager, registry)
    }
}

@MainActor struct PluginDiscoveryList: View {
    @Environment(\.scenePhase) private var scenePhase
    let effect: Bool
    let picked: (PluginRef) -> Void
    @State private var snapshot = PluginDiscovery.Snapshot()
    @State private var includeApple = false
    @State private var scanned = false
    var body: some View {
        List {
            Section {
                Button("Refresh Audio Units", action: refresh)
                Toggle("Show Apple audio units", isOn: $includeApple)
                if scanned {
                    Text("Third-party: \(snapshot.instruments) instruments / generators, \(snapshot.effects) effects").font(.caption)
                    Text("Discovery: \(snapshot.managerCount) manager entries; \(snapshot.registryCount) registry entries.").font(.caption).foregroundColor(.secondary)
                }
            }
            Section(header: Text(effect ? "Effects" : "Instruments / Generators")) {
                if snapshot.visible(effect: effect, includeApple: includeApple).isEmpty {
                    Text(scanned ? "No registered audio units in this category are visible to DBAL. This is a discovery result, not a compatibility test. Use Refresh after returning from another app." : "Checking registered Audio Units…").font(.callout)
                }
                ForEach(snapshot.visible(effect: effect, includeApple: includeApple)) { ref in
                    Button(ref.name) { picked(ref) }
                }
            }
            Section {
                Text("Audio effects appear in Effects; instruments and audio generators appear in Instruments. MIDI-only processors and Inter-App Audio apps are not hosted here. Apple units can be shown to check discovery without third-party extensions.").font(.caption).foregroundColor(.secondary)
            }
        }
        .task {
            refresh()
            // Registration may complete after the first query. Cancellation stops retries on dismissal.
            for _ in 0..<3 {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioUnitComponentManager.registrationsChangedNotification)) { _ in refresh() }
        .onChange(of: scenePhase) { phase in if phase == .active { refresh() } }
    }
    private func refresh() { snapshot = PluginDiscovery.scan(); scanned = true }
}
