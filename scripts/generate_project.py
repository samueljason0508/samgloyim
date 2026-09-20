#!/usr/bin/env python3
"""Generate the dependency-free Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / 'samgloyim.xcodeproj'
PROJECT.mkdir(exist_ok=True)
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(value): return json.dumps(str(value))
def add(key, body):
    value = ident(key)
    objects[value] = body
    return value
def ref(key): return ident(key)
def sequence(values): return '(' + ', '.join(values) + ', )' if values else '()'
def config_list(key, settings):
    ids = []
    for name in ['Debug', 'Release']:
        values = dict(settings)
        values.update({'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if name == 'Debug' else '-O', 'DEBUG_INFORMATION_FORMAT': 'dwarf' if name == 'Debug' else 'dwarf-with-dsym'})
        if name == 'Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        ids.append(add(key + name, 'isa = XCBuildConfiguration; buildSettings = { ' + ' '.join(f'{k} = {q(v)};' for k,v in values.items()) + ' }; name = ' + q(name) + ';'))
    return add(key + 'configs', f'isa = XCConfigurationList; buildConfigurations = {sequence(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')

targets = []
groups = []
products = []
package_ref = add('package:plaid-link-ios-spm', 'isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/plaid/plaid-link-ios-spm.git"; requirement = { kind = upToNextMajorVersion; minimumVersion = 7.0.0; };')
linkkit_product = add('product:LinkKit', f'isa = XCSwiftPackageProductDependency; package = {package_ref}; productName = LinkKit;')
for folder, target, product_type in [('Samgloyim', 'samgloyim', 'application'), ('SamgloyimTests', 'SamgloyimTests', 'bundle.unit-test'), ('SamgloyimUITests', 'SamgloyimUITests', 'bundle.ui-testing')]:
    sources = sorted((ROOT / folder).rglob('*.swift'))
    children = []
    builds = []
    for source in sources:
        path = source.relative_to(ROOT).as_posix()
        file_id = add('file:' + path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = SOURCE_ROOT;')
        children.append(file_id)
        builds.append(add('build:' + path, f'isa = PBXBuildFile; fileRef = {file_id};'))
    resources = []
    if target == 'samgloyim':
        asset = add('assets', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Samgloyim/Resources/Assets.xcassets; sourceTree = SOURCE_ROOT;')
        children.append(asset)
        resources.append(add('assets-build', f'isa = PBXBuildFile; fileRef = {asset};'))
    groups.append(add('group:' + folder, f'isa = PBXGroup; children = {sequence(children)}; name = {q(folder)}; sourceTree = "<group>";'))
    framework_files = []
    if target == 'samgloyim':
        framework_files.append(add('build:LinkKit:' + target, f'isa = PBXBuildFile; productRef = {linkkit_product};'))
    phases = [add('sources:' + target, f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {sequence(builds)}; runOnlyForDeploymentPostprocessing = 0;'),
              add('frameworks:' + target, f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {sequence(framework_files)}; runOnlyForDeploymentPostprocessing = 0;'),
              add('resources:' + target, f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {sequence(resources)}; runOnlyForDeploymentPostprocessing = 0;')]
    if target == 'samgloyim':
        embed_script = (
            'mkdir -p "$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH"\n'
            'SRC="$BUILT_PRODUCTS_DIR/PackageFrameworks/LinkKit.framework"\n'
            'DST="$BUILT_PRODUCTS_DIR/$FRAMEWORKS_FOLDER_PATH/LinkKit.framework"\n'
            'if [ -d "$SRC" ]; then\n'
            '  rsync -a --delete "$SRC/" "$DST/"\n'
            '  if [ "$CODE_SIGNING_ALLOWED" != "NO" ] && [ -n "$EXPANDED_CODE_SIGN_IDENTITY" ]; then\n'
            '    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" "$DST"\n'
            '  fi\n'
            'fi\n'
        )
        phases.append(add('embed:' + target, 'isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = (); inputPaths = (); outputPaths = (); runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh; ' +
            f'shellScript = {q(embed_script)}; name = "Embed LinkKit.framework";'))
    product = add('product:' + target, f'isa = PBXFileReference; explicitFileType = {"wrapper.application" if target == "samgloyim" else "wrapper.cfbundle"}; includeInIndex = 0; path = {q(target + (".app" if target == "samgloyim" else ".xctest"))}; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    settings = {'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.samgloyim.finance' + ('' if target == 'samgloyim' else '.' + target), 'PRODUCT_MODULE_NAME': 'Samgloyim' if target == 'samgloyim' else target, 'GENERATE_INFOPLIST_FILE': 'YES', 'SWIFT_VERSION': '5.0', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'TARGETED_DEVICE_FAMILY': '1,2', 'CODE_SIGN_STYLE': 'Automatic', 'SDKROOT': 'iphoneos', 'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST': 'NO'}
    dependencies = []
    if target == 'samgloyim':
        settings.update({'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks', 'INFOPLIST_FILE': 'Samgloyim/Resources/Info.plist', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon', 'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor', 'INFOPLIST_KEY_CFBundleDisplayName': 'PocketBloom', 'INFOPLIST_KEY_LSApplicationCategoryType': 'public.app-category.finance', 'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES', 'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES', 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone': 'UIInterfaceOrientationPortrait', 'INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad': 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight', 'CURRENT_PROJECT_VERSION': '1', 'MARKETING_VERSION': '1.0', 'ENABLE_PREVIEWS': 'YES'})
    else:
        proxy = add('proxy:' + target, f'isa = PBXContainerItemProxy; containerPortal = {ref("project")}; proxyType = 1; remoteGlobalIDString = {ref("target:samgloyim")}; remoteInfo = samgloyim;')
        dependencies.append(add('dependency:' + target, f'isa = PBXTargetDependency; target = {ref("target:samgloyim")}; targetProxy = {proxy};'))
        if product_type == 'bundle.unit-test': settings.update({'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/samgloyim.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/samgloyim', 'BUNDLE_LOADER': '$(TEST_HOST)'})
        else: settings['TEST_TARGET_NAME'] = 'samgloyim'
    configs = config_list('targetconfig:' + target, settings)
    package_deps_field = f'packageProductDependencies = {sequence([linkkit_product])}; ' if target == 'samgloyim' else ''
    targets.append(add('target:' + target, f'isa = PBXNativeTarget; buildConfigurationList = {configs}; buildPhases = {sequence(phases)}; buildRules = (); dependencies = {sequence(dependencies)}; name = {q(target)}; {package_deps_field}productName = {q(target)}; productReference = {product}; productType = {q("com.apple.product-type." + product_type)};'))
products_group = add('products-group', f'isa = PBXGroup; children = {sequence(products)}; name = Products; sourceTree = "<group>";')
root_group = add('root-group', f'isa = PBXGroup; children = {sequence(groups + [products_group])}; sourceTree = "<group>";')
project_configs = config_list('projectconfig:', {'ALWAYS_SEARCH_USER_PATHS': 'NO', 'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES', 'ENABLE_TESTABILITY': 'YES', 'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'CLANG_WARN_DOCUMENTATION_COMMENTS': 'YES', 'SWIFT_STRICT_CONCURRENCY': 'targeted'})
add('project', f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastSwiftUpdateCheck = 1640; LastUpgradeCheck = 1640; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {root_group}; packageReferences = {sequence([package_ref])}; productRefGroup = {products_group}; projectDirPath = ""; projectRoot = ""; targets = {sequence(targets)};')
(PROJECT / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(f'{key} = {{ {body} }};' for key, body in objects.items()) + f'\n}}; rootObject = {ref("project")};\n}}\n')

def buildable(target):
    suffix = '.app' if target == 'samgloyim' else '.xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ref("target:"+target)}" BuildableName="{target+suffix}" BlueprintName="{target}" ReferencedContainer="container:samgloyim.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1640" version="1.7">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildable('samgloyim')}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{buildable('SamgloyimTests')}</TestableReference><TestableReference skipped="NO" parallelizable="NO">{buildable('SamgloyimUITests')}</TestableReference></Testables></TestAction>
 <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('samgloyim')}</BuildableProductRunnable></LaunchAction>
 <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildable('samgloyim')}</BuildableProductRunnable></ProfileAction>
 <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
(PROJECT / 'xcshareddata/xcschemes').mkdir(parents=True, exist_ok=True)
(PROJECT / 'xcshareddata/xcschemes/samgloyim.xcscheme').write_text(scheme)
print('Generated samgloyim.xcodeproj')
