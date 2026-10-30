import Foundation
import AVFoundation
import AudioToolbox

func ref(_ name: String, _ type: OSType, _ subtype: OSType = 0x74657374,
         _ manufacturer: OSType = 0x54455354) -> PluginRef {
    PluginRef(name: name, type: type, subtype: subtype, manufacturer: manufacturer)
}
let instrument = ref("Test: Keys", kAudioUnitType_MusicDevice)
let generator = ref("Test: Generator", kAudioUnitType_Generator)
let fx = ref("Test: FX", kAudioUnitType_Effect)
let musicFX = ref("Test: MIDI-aware FX", kAudioUnitType_MusicEffect)
let midiOnly = ref("Test: MIDI only", kAudioUnitType_MIDIProcessor)
let apple = ref("Apple: Test", kAudioUnitType_Effect, 2, kAudioUnitManufacturer_Apple)
let internalFX = ref("Private FX", kAudioUnitType_Effect, 0x70786678, 0x4442414C)
let merged = PluginDiscovery.merge([instrument, fx, apple, internalFX],
    [instrument, generator, musicFX, midiOnly])
assert(merged.all.count == 6)
assert(merged.instruments == 2 && merged.effects == 2)
assert(merged.visible(effect: true, includeApple: true).count == 3)
assert(merged.visible(effect: false, includeApple: true).count == 2)
assert(merged.managerCount == 4 && merged.registryCount == 4)
assert(PluginDiscovery.merge([], [instrument]).instruments == 1)
assert(PluginDiscovery.merge([instrument], []).instruments == 1)
assert(PluginDiscovery.merge([], []).all.isEmpty)

// Register metadata locally, then exercise the real Apple discovery APIs.
// This verifies registry enumeration, not installed third-party extension discovery.
final class DiscoveryFixture: AUAudioUnit {}
let description = AudioComponentDescription(componentType: kAudioUnitType_MusicDevice,
    componentSubType: 0x64737431, componentManufacturer: 0x54455354,
    componentFlags: 0, componentFlagsMask: 0)
AUAudioUnit.registerSubclass(DiscoveryFixture.self, as: description,
    name: "DBAL Test: Discovery fixture", version: 1)
let actual = PluginDiscovery.scan()
assert(actual.all.contains { $0.type == description.componentType &&
    $0.subtype == description.componentSubType && $0.manufacturer == description.componentManufacturer })
print("PASS: discovery identity merge, registry fallback, categories, Apple visibility, private-unit exclusion and real registered fixture.")
