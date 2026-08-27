import os
import sys

def create_pbxproj():
    project_dir = os.path.dirname(os.path.abspath(__file__))
    radarmap_dir = os.path.join(project_dir, "RadarMap")
    companion_dir = os.path.join(project_dir, "RadarMapCompanion")
    xcodeproj_dir = os.path.join(project_dir, "RadarMap.xcodeproj")
    os.makedirs(xcodeproj_dir, exist_ok=True)
    
    # Watch Swift files
    watch_swift_files = []
    for root, _, files in os.walk(radarmap_dir):
        for f in files:
            if f.endswith(".swift"):
                rel_path = os.path.relpath(os.path.join(root, f), radarmap_dir)
                watch_swift_files.append((f, rel_path))
                
    # iOS Companion Swift files
    ios_swift_files = [("RadarMapCompanionApp.swift", "RadarMapCompanionApp.swift")]
    
    file_refs = []
    build_files = []
    
    # IDs
    watch_app_ref_id = "1A0000010000000000000001"
    ios_app_ref_id = "2A0000010000000000000001"
    
    file_refs.append(f'\t\t{watch_app_ref_id} /* RadarMap Watch App.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "RadarMap Watch App.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
    file_refs.append(f'\t\t{ios_app_ref_id} /* RadarMap.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "RadarMap.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')
    
    # Watch files
    watch_file_ids = {}
    watch_build_ids = {}
    idx = 100
    for fname, rel_path in watch_swift_files:
        f_id = f"FF{idx:06d}0000000000000001"
        b_id = f"FF{idx:06d}0000000000000002"
        watch_file_ids[fname] = f_id
        watch_build_ids[fname] = b_id
        file_refs.append(f'\t\t{f_id} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel_path}"; sourceTree = "<group>"; }};')
        build_files.append(f'\t\t{b_id} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {fname} */; }};')
        idx += 1
        
    watch_info_plist_id = "FF0000010000000000000001"
    file_refs.append(f'\t\t{watch_info_plist_id} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Resources/Info.plist"; sourceTree = "<group>"; }};')
    
    google_plist_id = "FF0000020000000000000001"
    file_refs.append(f'\t\t{google_plist_id} /* GoogleService-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Resources/GoogleService-Info.plist"; sourceTree = "<group>"; }};')

    assets_id = "FF0000030000000000000001"
    assets_build_id = "FF0000030000000000000002"
    file_refs.append(f'\t\t{assets_id} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "Resources/Assets.xcassets"; sourceTree = "<group>"; }};')
    build_files.append(f'\t\t{assets_build_id} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {assets_id} /* Assets.xcassets */; }};')

    # iOS Companion files
    ios_swift_id = "2F0001000000000000000001"
    ios_swift_build_id = "2F0001000000000000000002"
    file_refs.append(f'\t\t{ios_swift_id} /* RadarMapCompanionApp.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "RadarMapCompanionApp.swift"; sourceTree = "<group>"; }};')
    build_files.append(f'\t\t{ios_swift_build_id} /* RadarMapCompanionApp.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {ios_swift_id} /* RadarMapCompanionApp.swift */; }};')
    
    ios_info_plist_id = "2F0000010000000000000001"
    file_refs.append(f'\t\t{ios_info_plist_id} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "Resources/Info.plist"; sourceTree = "<group>"; }};')
    
    # Embed watch app build file
    embed_watch_build_id = "2A0000020000000000000001"
    build_files.append(f'\t\t{embed_watch_build_id} /* RadarMap Watch App.app in Embed Watch Content */ = {{isa = PBXBuildFile; fileRef = {watch_app_ref_id} /* RadarMap Watch App.app */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};')

    watch_group_children = [f'\t\t\t\t{watch_file_ids[fname]} /* {fname} */,' for fname, _ in watch_swift_files]
    watch_group_children.append(f'\t\t\t\t{watch_info_plist_id} /* Info.plist */,')
    watch_group_children.append(f'\t\t\t\t{google_plist_id} /* GoogleService-Info.plist */,')
    watch_group_children.append(f'\t\t\t\t{assets_id} /* Assets.xcassets */,')
    
    ios_group_children = [
        f'\t\t\t\t{ios_swift_id} /* RadarMapCompanionApp.swift */,',
        f'\t\t\t\t{ios_info_plist_id} /* Info.plist */,',
    ]

    watch_sources_build_phase = [f'\t\t\t\t{watch_build_ids[fname]} /* {fname} in Sources */,' for fname, _ in watch_swift_files]
    watch_resources_build_phase = [f'\t\t\t\t{assets_build_id} /* Assets.xcassets in Resources */,']
    
    ios_sources_build_phase = [f'\t\t\t\t{ios_swift_build_id} /* RadarMapCompanionApp.swift in Sources */,']

    team_id = "2VUBR7QPFD"

    pbxproj_content = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t2A0000030000000000000001 /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 1A0000090000000000000001 /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = 1A0000060000000000000001;
\t\t\tremoteInfo = "RadarMap Watch App";
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXCopyFilesBuildPhase section */
\t\t2A0000040000000000000001 /* Embed Watch Content */ = {{
\t\t\tisa = PBXCopyFilesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tdstPath = "$(CONTENTS_FOLDER_PATH)/Watch";
\t\t\tdstSubfolderSpec = 16;
\t\t\tfiles = (
\t\t\t\t{embed_watch_build_id} /* RadarMap Watch App.app in Embed Watch Content */,
\t\t\t);
\t\t\tname = "Embed Watch Content";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXCopyFilesBuildPhase section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t1A0000020000000000000001 /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t2A0000050000000000000001 /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t1A0000030000000000000001 = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t2A0000060000000000000001 /* RadarMapCompanion */,
\t\t\t\t1A0000040000000000000001 /* RadarMap */,
\t\t\t\t1A0000050000000000000001 /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t2A0000060000000000000001 /* RadarMapCompanion */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(ios_group_children)}
\t\t\t);
\t\t\tpath = RadarMapCompanion;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t1A0000040000000000000001 /* RadarMap */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{chr(10).join(watch_group_children)}
\t\t\t);
\t\t\tpath = RadarMap;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t1A0000050000000000000001 /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t2A0000010000000000000001 /* RadarMap.app */,
\t\t\t\t1A0000010000000000000001 /* RadarMap Watch App.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t2A0000070000000000000001 /* RadarMap */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 2A0000080000000000000001 /* Build configuration list for PBXNativeTarget "RadarMap" */;
\t\t\tbuildPhases = (
\t\t\t\t2A0000090000000000000001 /* Sources */,
\t\t\t\t2A0000050000000000000001 /* Frameworks */,
\t\t\t\t2A0000040000000000000001 /* Embed Watch Content */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t2A00000A0000000000000001 /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = "RadarMap";
\t\t\tproductName = "RadarMap";
\t\t\tproductReference = 2A0000010000000000000001 /* RadarMap.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t1A0000060000000000000001 /* RadarMap Watch App */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 1A0000070000000000000001 /* Build configuration list for PBXNativeTarget "RadarMap Watch App" */;
\t\t\tbuildPhases = (
\t\t\t\t1A0000080000000000000001 /* Sources */,
\t\t\t\t1A0000020000000000000001 /* Frameworks */,
\t\t\t\t1A0000100000000000000001 /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = "RadarMap Watch App";
\t\t\tproductName = "RadarMap Watch App";
\t\t\tproductReference = 1A0000010000000000000001 /* RadarMap Watch App.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t1A0000090000000000000001 /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t2A0000070000000000000001 = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tDevelopmentTeam = {team_id};
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t}};
\t\t\t\t\t1A0000060000000000000001 = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;
\t\t\t\t\t\tDevelopmentTeam = {team_id};
\t\t\t\t\t\tProvisioningStyle = Automatic;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = 1A00000A0000000000000001 /* Build configuration list for PBXProject "RadarMap" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = 1A0000030000000000000001;
\t\t\tproductRefGroup = 1A0000050000000000000001 /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t2A0000070000000000000001 /* RadarMap */,
\t\t\t\t1A0000060000000000000001 /* RadarMap Watch App */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t1A0000100000000000000001 /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(watch_resources_build_phase)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t2A0000090000000000000001 /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(ios_sources_build_phase)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t1A0000080000000000000001 /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{chr(10).join(watch_sources_build_phase)}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t2A00000A0000000000000001 /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = 1A0000060000000000000001 /* RadarMap Watch App */;
\t\t\ttargetProxy = 2A0000030000000000000001 /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t1A00000B0000000000000001 /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tDEVELOPMENT_TEAM = {team_id};
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tENABLE_TESTABILITY = YES;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t1A00000C0000000000000001 /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tDEVELOPMENT_TEAM = {team_id};
\t\t\t\tENABLE_NS_ASSERTIONS = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t2A00000B0000000000000001 /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = {team_id};
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = RadarMapCompanion/Resources/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Radar Map";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.radarmap.watch;
\t\t\t\tPRODUCT_NAME = "RadarMap";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphonesimulator iphoneos";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t2A00000C0000000000000001 /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = {team_id};
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = RadarMapCompanion/Resources/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Radar Map";
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.radarmap.watch;
\t\t\t\tPRODUCT_NAME = "RadarMap";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphonesimulator iphoneos";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t1A00000D0000000000000001 /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = {team_id};
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = RadarMap/Resources/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Radar Map";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.radarmap.watch.watchkitapp;
\t\t\t\tPRODUCT_NAME = "RadarMap Watch App";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchsimulator watchos";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "4";
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t1A00000E0000000000000001 /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = {team_id};
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = RadarMap/Resources/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "Radar Map";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.radarmap.watch.watchkitapp;
\t\t\t\tPRODUCT_NAME = "RadarMap Watch App";
\t\t\t\tSDKROOT = watchos;
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSUPPORTED_PLATFORMS = "watchsimulator watchos";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tTARGETED_DEVICE_FAMILY = "4";
\t\t\t\tWATCHOS_DEPLOYMENT_TARGET = 10.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t1A00000A0000000000000001 /* Build configuration list for PBXProject "RadarMap" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t1A00000B0000000000000001 /* Debug */,
\t\t\t\t1A00000C0000000000000001 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t2A0000080000000000000001 /* Build configuration list for PBXNativeTarget "RadarMap" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t2A00000B0000000000000001 /* Debug */,
\t\t\t\t2A00000C0000000000000001 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t1A0000070000000000000001 /* Build configuration list for PBXNativeTarget "RadarMap Watch App" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t1A00000D0000000000000001 /* Debug */,
\t\t\t\t1A00000E0000000000000001 /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = 1A0000090000000000000001 /* Project object */;
}}
"""

    pbxproj_path = os.path.join(xcodeproj_dir, "project.pbxproj")
    with open(pbxproj_path, "w") as f:
        f.write(pbxproj_content)
    print(f"Generated unified iOS + watchOS Xcode project: {pbxproj_path}")

if __name__ == "__main__":
    create_pbxproj()
