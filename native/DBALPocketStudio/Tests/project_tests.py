#!/usr/bin/env python3
"""Parse OpenStep project structure, verify references/configurations and resource integrity."""
from pathlib import Path
import re,plistlib,xml.etree.ElementTree as ET,wave,hashlib,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def parse(text):
    text=re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S)
    tokens=re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+',text);position=0
    def value():
        nonlocal position
        token=tokens[position];position+=1
        if token=='{':
            result={}
            while tokens[position]!='}':
                key=value();assert tokens[position]=='=';position+=1
                assert key not in result,f'duplicate key {key}'
                result[key]=value();assert tokens[position]==';', (key,tokens[max(0,position-5):position+5]);position+=1
            position+=1;return result
        if token=='(':
            result=[]
            while tokens[position]!=')':
                result.append(value())
                if tokens[position]==',':position+=1
                else:assert tokens[position]==')'
            position+=1;return result
        if token.startswith('"'):return bytes(token[1:-1],'utf8').decode('unicode_escape')
        return token
    result=value();assert position==len(tokens);return result
p=ROOT/'DBALPocketStudio.xcodeproj/project.pbxproj'
before=p.read_bytes();subprocess.run([sys.executable,str(ROOT/'Scripts/generate_project.py')],check=True);assert p.read_bytes()==before,'project generator is not deterministic'
project=parse(p.read_text());objects=project['objects'];assert project['rootObject'] in objects
sources={str(p.relative_to(ROOT)) for p in (ROOT/'App').glob('*.swift')}|{'Engine/PocketSampler.c','Engine/PocketFX.c','Engine/AudioGraphGuard.m'}
for name in ['PocketLegacy','PocketPro']:
    target=next(v for v in objects.values() if v.get('isa')=='PBXNativeTarget' and v['name']==name)
    configs=objects[target['buildConfigurationList']]['buildConfigurations'];assert len(configs)==2
    for c in configs:
        settings=objects[c]['buildSettings'];assert settings['IPHONEOS_DEPLOYMENT_TARGET']=='15.4';assert settings['SUPPORTS_MACCATALYST']=='YES'
        assert ('POCKET_PRO' in settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS'])==(name=='PocketPro')
    phase=next(objects[x] for x in target['buildPhases'] if objects[x]['isa']=='PBXSourcesBuildPhase')
    included={objects[objects[b]['fileRef']]['path'] for b in phase['files']};assert included==sources
    scheme=ET.parse(ROOT/f'DBALPocketStudio.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme')
    for ref in scheme.findall('.//BuildableReference'):assert ref.attrib['BlueprintIdentifier'] in objects
for obj in objects.values():
    if obj.get('isa')=='PBXFileReference' and obj.get('sourceTree')=='<group>':assert (ROOT/obj['path']).exists(),obj['path']
with (ROOT/'App/Info.plist').open('rb') as f:info=plistlib.load(f)
assert 'audio' in info['UIBackgroundModes'];assert info['NSMicrophoneUsageDescription'];assert info['CFBundleDocumentTypes']
assert info['NSBluetoothAlwaysUsageDescription'] and info['NSLocalNetworkUsageDescription'] and '_apple-midi._udp' in info['NSBonjourServices']
kit=ROOT/'Resources/StarterKit';text=(kit/'StarterKit.sfz').read_text();files=re.findall(r'sample=(\S+)',text);assert len(files)==8
for name in files:
    with wave.open(str(kit/name)) as f:assert f.getnframes()>100 and f.getframerate()==44100 and f.getnchannels()==1
target=next(v for v in objects.values() if v.get('isa')=='PBXNativeTarget' and v['name']=='DBALNativeMac')
phase=next(objects[x] for x in target['buildPhases'] if objects[x]['isa']=='PBXSourcesBuildPhase')
included={objects[objects[b]['fileRef']]['path'] for b in phase['files']}
assert 'Mac/MIDIReceiver.swift' in included
assert 'Engine/AudioGraphGuard.m' in included
assert {'Mac/NativeStudio.swift','Mac/NativeAdapters.swift','App/SampleTransform.swift','App/SFZ.swift','App/Studio.swift'}<=included
assert not {'App/StudioView.swift','App/Panels.swift','App/ClipSelectionUI.swift'}&included
for c in objects[target['buildConfigurationList']]['buildConfigurations']:
    settings=objects[c]['buildSettings'];assert settings['SDKROOT']=='macosx' and settings['SUPPORTS_MACCATALYST']=='NO'
    assert 'NATIVE_MAC' in settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']
assert len([v for v in objects.values() if v.get('isa')=='PBXNativeTarget'])==3
print('PASS: separate native macOS target, shared engine/sampler, UIKit-only source exclusion, native SDK and compilation flags.')
print(f'PASS: OpenStep parsing, deterministic project, 3 shared schemes, {len(sources)} source files per target, iPadOS 15.4/Catalyst settings, microphone/background/project metadata, 8 valid kit samples.')

engine=(ROOT/"App/AudioEngine.swift").read_text()
assert "engine.connect(" not in engine
assert "DBALConnectAudioNodes" in engine and "DBALPrepareAndStartAudioEngine" in engine
assert "AudioGraphGuard.h" in (ROOT/"App/Bridging.h").read_text()
print("PASS: shared graph connections/start route through the native exception boundary.")
