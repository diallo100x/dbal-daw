#!/usr/bin/env python3
"""Dependency-free deterministic Xcode project generator. Run from any directory."""
from pathlib import Path
import hashlib, plistlib, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
objects={}
def ident(key):return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def add(key,text):
    i=ident(key);objects[i]=text;return i
def quoted(s):return '"'+str(s).replace('\\','\\\\').replace('"','\\"')+'"'
def refs(items):return '('+','.join(items)+',)'
def settings(values):return '{'+' '.join(f'{quoted(k)} = {quoted(v)};' for k,v in values.items())+'}'
files=[]
for p in sorted((ROOT/'App').glob('*.swift')):files.append((str(p.relative_to(ROOT)),'sourcecode.swift'))
for p in sorted((ROOT/'Mac').glob('*.swift')):files.append((str(p.relative_to(ROOT)),'sourcecode.swift'))
files += [('Mac/Info.plist','text.plist.xml'),('Mac/Native.entitlements','text.plist.entitlements'),('Engine/AudioGraphGuard.m','sourcecode.c.objc'),('Engine/AudioGraphGuard.h','sourcecode.c.h'),('Engine/PocketSampler.c','sourcecode.c.c'),('Engine/PocketFX.c','sourcecode.c.c'),('Engine/PocketFX.h','sourcecode.c.h'),('Engine/PocketSampler.h','sourcecode.c.h'),('App/Bridging.h','sourcecode.c.h'),('App/Info.plist','text.plist.xml'),('App/Mac.entitlements','text.plist.entitlements')]
fileids={}
for name,kind in files:
    fileids[name]=add('file:'+name,f'{{isa=PBXFileReference;lastKnownFileType={quoted(kind)};path={quoted(name)};sourceTree="<group>";}}')
kit=add('kit','{isa=PBXFileReference;lastKnownFileType=folder;path="Resources/StarterKit";sourceTree="<group>";}')
products=[];targets=[]; target_ids={}
shared_mac={'AudioEngine.swift','Session.swift','PerformanceModel.swift','SFZ.swift','XYAudioUnit.swift','SampleTransform.swift','Studio.swift','StudioPerformance.swift','ClipEdits.swift','ClipTile.swift','MusicalControls.swift','SamplerControls.swift','PerformancePanel.swift','WaveformHandles.swift','Waveforms.swift','MIDIMessage.swift','MIDINoteEdits.swift','PluginDiscovery.swift','TimelineEditors.swift','MIDIQuantizeTools.swift'}
for flavor in ['Legacy','Pro','Mac']:
    native=flavor=='Mac'
    name='DBALNativeMac' if native else 'Pocket'+flavor
    product=add('product:'+name,f'{{isa=PBXFileReference;explicitFileType=wrapper.application;includeInIndex=0;path={name}.app;sourceTree=BUILT_PRODUCTS_DIR;}}');products.append(product)
    sources=[]
    for file,_ in files:
        if file.endswith(('.swift','.c','.m')) and ((native and (file.startswith(('Mac/','Engine/')) or Path(file).name in shared_mac)) or (not native and not file.startswith('Mac/'))):
            sources.append(add('build:'+name+file,f'{{isa=PBXBuildFile;fileRef={fileids[file]};}}'))
    buildkit=add('buildkit:'+name,f'{{isa=PBXBuildFile;fileRef={kit};}}')
    sb=add('sources:'+name,f'{{isa=PBXSourcesBuildPhase;buildActionMask=2147483647;files={refs(sources)};runOnlyForDeploymentPostprocessing=0;}}')
    rb=add('resources:'+name,f'{{isa=PBXResourcesBuildPhase;buildActionMask=2147483647;files={refs([buildkit])};runOnlyForDeploymentPostprocessing=0;}}')
    fb=add('frameworks:'+name,'{isa=PBXFrameworksBuildPhase;buildActionMask=2147483647;files=();runOnlyForDeploymentPostprocessing=0;}')
    configs=[]
    for config in ['Debug','Release']:
        values={
            'PRODUCT_NAME':name,'PRODUCT_BUNDLE_IDENTIFIER':'io.diallobeats.pocketstudio.'+flavor.lower(),
            'POCKET_DISPLAY_NAME':'Pocket Studio '+flavor,'SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'15.4',
            'MACOSX_DEPLOYMENT_TARGET':'12.3','TARGETED_DEVICE_FAMILY':'2','SDKROOT':'iphoneos',
            'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'YES',
            'DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER':'YES','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD':'NO',
            'INFOPLIST_FILE':'App/Info.plist','GENERATE_INFOPLIST_FILE':'NO',
            'SWIFT_OBJC_BRIDGING_HEADER':'App/Bridging.h','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','GCC_ENABLE_OBJC_EXCEPTIONS':'YES',
            'CODE_SIGN_STYLE':'Automatic','CODE_SIGN_ENTITLEMENTS[sdk=macosx*]':'App/Mac.entitlements',
            'ENABLE_HARDENED_RUNTIME':'YES','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O',
            'GCC_OPTIMIZATION_LEVEL':'0' if config=='Debug' else 's','GCC_C_LANGUAGE_STANDARD':'c11',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'$(inherited) '+('DEBUG ' if config=='Debug' else '')+('POCKET_PRO' if flavor=='Pro' else 'POCKET_LEGACY'),
            'MARKETING_VERSION':'0.1.6','CURRENT_PROJECT_VERSION':'7','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks',
            'ENABLE_USER_SCRIPT_SANDBOXING':'YES','SWIFT_EMIT_LOC_STRINGS':'NO',
        }
        if native:
            values.update({'PRODUCT_BUNDLE_IDENTIFIER':'io.diallobeats.dbal.native','POCKET_DISPLAY_NAME':'DBAL DAW',
                'SDKROOT':'macosx','SUPPORTED_PLATFORMS':'macosx','SUPPORTS_MACCATALYST':'NO',
                'INFOPLIST_FILE':'Mac/Info.plist','CODE_SIGN_ENTITLEMENTS':'Mac/Native.entitlements',
                'CODE_SIGN_ENTITLEMENTS[sdk=macosx*]':'Mac/Native.entitlements',
                'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'$(inherited) POCKET_PRO NATIVE_MAC'+(' DEBUG' if config=='Debug' else ''),
                'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks','COMBINE_HIDPI_IMAGES':'YES'})
            for key in ['IPHONEOS_DEPLOYMENT_TARGET','TARGETED_DEVICE_FAMILY','DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER','SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD']:values.pop(key,None)
        configs.append(add('config:'+name+config,f'{{isa=XCBuildConfiguration;buildSettings={settings(values)};name={config};}}'))
    cl=add('configs:'+name,f'{{isa=XCConfigurationList;buildConfigurations={refs(configs)};defaultConfigurationIsVisible=0;defaultConfigurationName=Release;}}')
    target=add('target:'+name,f'{{isa=PBXNativeTarget;buildConfigurationList={cl};buildPhases={refs([sb,fb,rb])};buildRules=();dependencies=();name={name};productName={name};productReference={product};productType="com.apple.product-type.application";}}')
    targets.append(target);target_ids[name]=target
pg=add('products',f'{{isa=PBXGroup;children={refs(products)};name=Products;sourceTree="<group>";}}')
main=add('main',f'{{isa=PBXGroup;children={refs(list(fileids.values())+[kit,pg])};sourceTree="<group>";}}')
pc=[]
for config in ['Debug','Release']:
    pc.append(add('projectconfig:'+config,f'{{isa=XCBuildConfiguration;buildSettings={settings({"CLANG_WARN_DOCUMENTATION_COMMENTS":"YES","GCC_WARN_64_TO_32_BIT_CONVERSION":"YES","CLANG_WARN_INFINITE_RECURSION":"YES"})};name={config};}}'))
pcl=add('projectconfigs',f'{{isa=XCConfigurationList;buildConfigurations={refs(pc)};defaultConfigurationIsVisible=0;defaultConfigurationName=Release;}}')
project=add('project',f'{{isa=PBXProject;attributes={{BuildIndependentTargetsInParallel=YES;LastUpgradeCheck=1500;}};buildConfigurationList={pcl};compatibilityVersion="Xcode 14.0";developmentRegion=en;hasScannedForEncodings=0;knownRegions=(en,Base,);mainGroup={main};productRefGroup={pg};projectDirPath="";projectRoot="";targets={refs(targets)};}}')
output='// !$*UTF8*$!\n{archiveVersion=1;classes={};objectVersion=56;objects={\n'+''.join(f'{i} = {v};\n' for i,v in objects.items())+f'}};rootObject={project};}}\n'
(ROOT/'DBALPocketStudio.xcodeproj/project.pbxproj').write_text(output)
for name,target in target_ids.items():
    scheme=ET.Element('Scheme',LastUpgradeVersion='1500',version='1.3')
    build=ET.SubElement(scheme,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES')
    entries=ET.SubElement(build,'BuildActionEntries')
    entry=ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES',buildForProfiling='YES',buildForArchiving='YES',buildForAnalyzing='YES')
    attrs=dict(BuildableIdentifier='primary',BlueprintIdentifier=target,BuildableName=name+'.app',BlueprintName=name,ReferencedContainer='container:DBALPocketStudio.xcodeproj')
    ET.SubElement(entry,'BuildableReference',**attrs)
    ET.SubElement(scheme,'TestAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='YES')
    launch=ET.SubElement(scheme,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',debugServiceExtension='internal',allowLocationSimulation='YES')
    run=ET.SubElement(launch,'BuildableProductRunnable',runnableDebuggingMode='0');ET.SubElement(run,'BuildableReference',**attrs)
    ET.SubElement(scheme,'AnalyzeAction',buildConfiguration='Debug')
    ET.SubElement(scheme,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
    ET.indent(scheme)
    ET.ElementTree(scheme).write(ROOT/f'DBALPocketStudio.xcodeproj/xcshareddata/xcschemes/{name}.xcscheme',encoding='UTF-8',xml_declaration=True)
info={
    'CFBundleDevelopmentRegion':'en','CFBundleDisplayName':'$(POCKET_DISPLAY_NAME)','CFBundleExecutable':'$(EXECUTABLE_NAME)',
    'CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)',
    'CFBundlePackageType':'APPL','CFBundleShortVersionString':'$(MARKETING_VERSION)','CFBundleVersion':'$(CURRENT_PROJECT_VERSION)',
    'LSRequiresIPhoneOS':True,'LSApplicationCategoryType':'public.app-category.music',
    'NSBluetoothAlwaysUsageDescription':'Connect Pocket MIDI Remote to your Mac or MIDI host over Bluetooth.',
    'NSLocalNetworkUsageDescription':'Connect Pocket MIDI Remote over your local MIDI network.',
    'NSBonjourServices':['_apple-midi._udp'],
    'NSMicrophoneUsageDescription':'Record vocals and instruments into your Pocket Studio sessions.',
    'UIBackgroundModes':['audio'],'UILaunchScreen':{},'UIApplicationSupportsIndirectInputEvents':True,
    'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'],
    'UIFileSharingEnabled':True,'LSSupportsOpeningDocumentsInPlace':True,
    'CFBundleDocumentTypes':[{'CFBundleTypeName':'Pocket Studio Session','CFBundleTypeRole':'Editor','LSHandlerRank':'Owner','LSItemContentTypes':['io.diallobeats.pocketstudio.session']}],
    'UTExportedTypeDeclarations':[{'UTTypeIdentifier':'io.diallobeats.pocketstudio.session','UTTypeDescription':'Pocket Studio Session','UTTypeConformsTo':['com.apple.package'],'UTTypeTagSpecification':{'public.filename-extension':['pocketstudio']}}],
}
with (ROOT/'App/Info.plist').open('wb') as f:plistlib.dump(info,f)
with (ROOT/'App/Mac.entitlements').open('wb') as f:plistlib.dump({'com.apple.security.app-sandbox':True,'com.apple.security.device.audio-input':True,'com.apple.security.files.user-selected.read-write':True},f)
macinfo={k:v for k,v in info.items() if not k.startswith(('UI','LSRequiresIPhone','LSSupportsOpening'))}
macinfo['NSPrincipalClass']='NSApplication'
macinfo['NSHighResolutionCapable']=True
with (ROOT/'Mac/Info.plist').open('wb') as f:plistlib.dump(macinfo,f)
with (ROOT/'Mac/Native.entitlements').open('wb') as f:plistlib.dump({'com.apple.security.device.audio-input':True,'com.apple.security.cs.disable-library-validation':True},f)
print('Generated Legacy/Pro with Catalyst and separate native macOS target.')
