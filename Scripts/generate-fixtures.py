#!/usr/bin/env python3
"""Generates the Xcode fixture projects under Tests/Fixtures.

Usage: rm -rf Tests/Fixtures && python3 Scripts/generate-fixtures.py Tests/Fixtures
"""
import hashlib, json, os, shutil, struct, sys, zlib

ROOT = sys.argv[1]

def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()

def q(v):
    v = str(v)
    import re
    if re.fullmatch(r"[A-Za-z0-9_$./\-]+", v) and v not in ("",):
        return v
    return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'

def fmt_settings(d, indent):
    pad = "\t" * indent
    out = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            items = "".join(f"{pad}\t{q(x)},\n" for x in v)
            out.append(f"{pad}{q(k)} = (\n{items}{pad});\n")
        else:
            out.append(f"{pad}{q(k)} = {q(v)};\n")
    return "".join(out)

FILETYPES = {
    "swift": "sourcecode.swift", "plist": "text.plist.xml", "xcassets": "folder.assetcatalog",
    "xcprivacy": "text.xml", "xcconfig": "text.xcconfig", "m": "sourcecode.c.objc", "h": "sourcecode.c.h",
}

def write(path, content, binary=False):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "wb" if binary else "w") as f:
        f.write(content)

def png(size=1, alpha=False):
    px = b"\xff\x80\x00\xff" if alpha else b"\xff\x80\x00"
    raw = b"".join(b"\x00" + px * size for _ in range(size))
    def chunk(t, d):
        c = t + d
        return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6 if alpha else 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

def plist(d):
    def val(v, ind):
        p = "\t" * ind
        if isinstance(v, bool):
            return f"{p}<{'true' if v else 'false'}/>\n"
        if isinstance(v, int):
            return f"{p}<integer>{v}</integer>\n"
        if isinstance(v, str):
            return f"{p}<string>{v}</string>\n"
        if isinstance(v, list):
            return f"{p}<array>\n" + "".join(val(x, ind + 1) for x in v) + f"{p}</array>\n"
        if isinstance(v, dict):
            return f"{p}<dict>\n" + "".join(f"{p}\t<key>{k}</key>\n" + val(v[k], ind + 1) for k in v) + f"{p}</dict>\n"
        raise TypeError(v)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
            '<plist version="1.0">\n' + val(d, 0) + '</plist>\n')

def app_icon(path, name="AppIcon", with_image=True, pixels=1024, alpha=False, idiom="universal", size="1024x1024", scale=None):
    write(f"{path}/Contents.json", json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    images = [{"idiom": idiom, "size": size}]
    if idiom == "universal":
        images[0]["platform"] = "ios"
    if scale:
        images[0]["scale"] = scale
    if with_image:
        images[0]["filename"] = "Icon-1024.png"
        write(f"{path}/{name}.appiconset/Icon-1024.png", png(pixels, alpha), binary=True)
    write(f"{path}/{name}.appiconset/Contents.json",
          json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")

def scheme(path, name, blueprint_id, target, container, archive="Release", launch="Debug"):
    write(path, f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{blueprint_id}"
               BuildableName = "{target}.app"
               BlueprintName = "{target}"
               ReferencedContainer = "container:{container}">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <LaunchAction
      buildConfiguration = "{launch}"
      launchStyle = "0">
   </LaunchAction>
   <ArchiveAction
      buildConfiguration = "{archive}"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''')

def project(name, base, configs, project_settings, targets, project_xcconfigs=None, extra_groups=()):
    """targets: list of dicts with name, type, sources, resources, settings{config:dict},
    xcconfigs{config:path}, sync{folder: [excluded files]}"""
    pid = oid(name, "project")
    objs = {}  # section -> list of (id, text)
    def add(section, ident, text):
        objs.setdefault(section, []).append((ident, text))

    # Groups and files
    files = {}
    for t in targets:
        for p in t.get("sources", []) + t.get("resources", []):
            files.setdefault(p, None)
    for xc in list((project_xcconfigs or {}).values()) + [p for t in targets for p in t.get("xcconfigs", {}).values()]:
        files.setdefault(xc, None)
    for g in extra_groups:
        files.setdefault(g, None)
    groups = {}
    for p in files:
        folder, fname = os.path.split(p)
        groups.setdefault(folder, []).append(fname)
        files[p] = oid(name, "file", p)
        ext = fname.rsplit(".", 1)[-1]
        add("PBXFileReference", files[p],
            f"{{isa = PBXFileReference; lastKnownFileType = {FILETYPES.get(ext, 'text')}; path = {q(fname)}; sourceTree = \"<group>\"; }};")
    main_children = []
    for folder in sorted(groups):
        gid = oid(name, "group", folder)
        main_children.append(gid)
        kids = "".join(f"\t\t\t\t{files[os.path.join(folder, f)]} /* {f} */,\n" for f in sorted(groups[folder]))
        add("PBXGroup", gid, f"{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{kids}\t\t\t);\n\t\t\tpath = {q(folder)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
    products_id = oid(name, "products")
    sync_ids = {}
    for t in targets:
        for folder, excluded in t.get("sync", {}).items():
            sid = oid(name, "sync", folder)
            sync_ids[(t["name"], folder)] = sid
            main_children.append(sid)
            exc = ""
            if excluded:
                eid = oid(name, "syncexc", folder)
                items = "".join(f"\t\t\t\t{q(e)},\n" for e in excluded)
                add("PBXFileSystemSynchronizedBuildFileExceptionSet", eid,
                    f"{{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n{items}\t\t\t);\n\t\t\ttarget = {oid(name, 'target', t['name'])} /* {t['name']} */;\n\t\t}};")
                exc = f"\t\t\texceptions = (\n\t\t\t\t{eid} /* PBXFileSystemSynchronizedBuildFileExceptionSet */,\n\t\t\t);\n"
            add("PBXFileSystemSynchronizedRootGroup", sid,
                f"{{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n{exc}\t\t\tpath = {q(folder)};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
    main_children.append(products_id)
    main_id = oid(name, "maingroup")
    kids = "".join(f"\t\t\t\t{c},\n" for c in main_children)
    add("PBXGroup", main_id, f"{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{kids}\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
    product_kids = ""
    target_ids = []
    for t in targets:
        tid = oid(name, "target", t["name"])
        target_ids.append(tid)
        prod = oid(name, "product", t["name"])
        ext = {"com.apple.product-type.application": "app", "com.apple.product-type.app-extension": "appex",
               "com.apple.product-type.framework": "framework"}.get(t["type"], "xctest")
        add("PBXFileReference", prod, f"{{isa = PBXFileReference; explicitFileType = wrapper.{ext}; includeInIndex = 0; path = {q(t['name'] + '.' + ext)}; sourceTree = BUILT_PRODUCTS_DIR; }};")
        product_kids += f"\t\t\t\t{prod},\n"
        phases = []
        for kind, key in (("PBXSourcesBuildPhase", "sources"), ("PBXResourcesBuildPhase", "resources")):
            phid = oid(name, kind, t["name"])
            phases.append(phid)
            bfs = ""
            for p in t.get(key, []):
                bid = oid(name, "buildfile", t["name"], p)
                add("PBXBuildFile", bid, f"{{isa = PBXBuildFile; fileRef = {files[p]} /* {os.path.basename(p)} */; }};")
                bfs += f"\t\t\t\t{bid},\n"
            add(kind, phid, f"{{\n\t\t\tisa = {kind};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n{bfs}\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
        clid = oid(name, "configlist", t["name"])
        cfg_ids = []
        for c in configs:
            cid = oid(name, "config", t["name"], c)
            cfg_ids.append(cid)
            basecfg = ""
            if c in t.get("xcconfigs", {}):
                basecfg = f"\t\t\tbaseConfigurationReference = {files[t['xcconfigs'][c]]};\n"
            add("XCBuildConfiguration", cid, f"{{\n\t\t\tisa = XCBuildConfiguration;\n{basecfg}\t\t\tbuildSettings = {{\n{fmt_settings(t.get('settings', {}).get(c, {}), 4)}\t\t\t}};\n\t\t\tname = {q(c)};\n\t\t}};")
        for script in t.get("scripts", []):
            sid = oid(name, "script", t["name"], script)
            phases.append(sid)
            add("PBXShellScriptBuildPhase", sid, f"{{\n\t\t\tisa = PBXShellScriptBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\tname = {q(script)};\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t\tshellPath = /bin/sh;\n\t\t\tshellScript = \"echo running\\n\";\n\t\t}};")
        add("XCConfigurationList", clid, f"{{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n" + "".join(f"\t\t\t\t{x},\n" for x in cfg_ids) + f"\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = {q(configs[-1])};\n\t\t}};")
        sync = ""
        if t.get("sync"):
            sync = "\t\t\tfileSystemSynchronizedGroups = (\n" + "".join(f"\t\t\t\t{sync_ids[(t['name'], f)]},\n" for f in t["sync"]) + "\t\t\t);\n"
        add("PBXNativeTarget", tid, f"{{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {clid};\n\t\t\tbuildPhases = (\n" + "".join(f"\t\t\t\t{x},\n" for x in phases) + f"\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n{sync}\t\t\tname = {q(t['name'])};\n\t\t\tproductName = {q(t['name'])};\n\t\t\tproductReference = {prod};\n\t\t\tproductType = {q(t['type'])};\n\t\t}};")
    add("PBXGroup", products_id, f"{{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{product_kids}\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
    pcl = oid(name, "projconfiglist")
    pcfg = []
    for c in configs:
        cid = oid(name, "projconfig", c)
        pcfg.append(cid)
        basecfg = ""
        if project_xcconfigs and c in project_xcconfigs:
            basecfg = f"\t\t\tbaseConfigurationReference = {files[project_xcconfigs[c]]};\n"
        add("XCBuildConfiguration", cid, f"{{\n\t\t\tisa = XCBuildConfiguration;\n{basecfg}\t\t\tbuildSettings = {{\n{fmt_settings(project_settings.get(c, {}), 4)}\t\t\t}};\n\t\t\tname = {q(c)};\n\t\t}};")
    add("XCConfigurationList", pcl, f"{{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n" + "".join(f"\t\t\t\t{x},\n" for x in pcfg) + f"\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = {q(configs[-1])};\n\t\t}};")
    add("PBXProject", pid, f"{{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t}};\n\t\t\tbuildConfigurationList = {pcl};\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {main_id};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {products_id} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n" + "".join(f"\t\t\t\t{x},\n" for x in target_ids) + "\t\t\t);\n\t\t};")
    out = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n"
    for section in sorted(objs):
        out += f"\n/* Begin {section} section */\n"
        for ident, text in sorted(objs[section]):
            out += f"\t\t{ident} = {text}\n"
        out += f"/* End {section} section */\n"
    out += f"\t}};\n\trootObject = {pid} /* Project object */;\n}}\n"
    write(f"{base}/{name}.xcodeproj/project.pbxproj", out)
    return {t["name"]: oid(name, "target", t["name"]) for t in targets}

PROJECT_DEBUG = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
    "GCC_OPTIMIZATION_LEVEL": "0", "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
    "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
}
PROJECT_RELEASE = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_COMPILATION_MODE": "wholemodule",
    "VALIDATE_PRODUCT": "YES",
}

def app_settings(**extra):
    d = {"CODE_SIGN_STYLE": "Automatic", "PRODUCT_NAME": "$(TARGET_NAME)", "SWIFT_VERSION": "5.0",
         "TARGETED_DEVICE_FAMILY": "1,2", "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"]}
    d.update(extra)
    return d

PRIVACY_USERDEFAULTS = {
    "NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
    "NSPrivacyAccessedAPITypes": [{"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
                                   "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}],
}

# ---------------------------------------------------------------- ValidApp
B = "ValidApp"
valid_settings = app_settings(
    ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", CURRENT_PROJECT_VERSION="42", GENERATE_INFOPLIST_FILE="YES",
    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription="Your location is used to show nearby stores.",
    INFOPLIST_KEY_UILaunchScreen_Generation="YES", MARKETING_VERSION="1.2.0",
    INFOPLIST_KEY_ITSAppUsesNonExemptEncryption="NO", DEVELOPMENT_TEAM="ABCDE12345",
    CODE_SIGN_ENTITLEMENTS="ValidApp/ValidApp.entitlements",
    PRODUCT_BUNDLE_IDENTIFIER="com.acme.validapp")
ids = project("ValidApp", B, ["Debug", "Release"], {"Debug": PROJECT_DEBUG, "Release": PROJECT_RELEASE}, [
    {"name": "ValidApp", "type": "com.apple.product-type.application",
     "sources": ["ValidApp/ValidAppApp.swift", "ValidApp/StoreLocator.swift"],
     "resources": ["ValidApp/Assets.xcassets", "ValidApp/PrivacyInfo.xcprivacy"],
     "settings": {"Debug": valid_settings, "Release": valid_settings}},
    {"name": "ValidAppUITests", "type": "com.apple.product-type.bundle.ui-testing",
     "sources": ["ValidAppUITests/ValidAppUITests.swift"],
     "settings": {"Debug": {"PRODUCT_BUNDLE_IDENTIFIER": "com.acme.validapp.uitests"}, "Release": {}}},
])
write(f"{B}/ValidApp/ValidAppApp.swift", '''import SwiftUI

@main
struct ValidAppApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Text(hasCompletedOnboarding ? "Welcome back" : "Welcome")
                .accessibilityLabel("Greeting")
        }
    }
}
''')
write(f"{B}/ValidApp/StoreLocator.swift", '''import CoreLocation

final class StoreLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
    }
}
''')
write(f"{B}/ValidAppUITests/ValidAppUITests.swift", '''import XCTest

final class ValidAppUITests: XCTestCase {
    func testLaunch() {
        XCUIApplication().launch()
    }
}
''')
app_icon(f"{B}/ValidApp/Assets.xcassets")
write(f"{B}/ValidApp/PrivacyInfo.xcprivacy", plist(PRIVACY_USERDEFAULTS))
write(f"{B}/ValidApp/ValidApp.entitlements", plist({
    "com.apple.developer.associated-domains": ["applinks:acme.com", "webcredentials:acme.com?mode=developer"],
    "com.apple.security.application-groups": ["group.com.acme.validapp"],
    "aps-environment": "development",
}))
scheme(f"{B}/ValidApp.xcodeproj/xcshareddata/xcschemes/ValidApp.xcscheme", "ValidApp", ids["ValidApp"], "ValidApp", "ValidApp.xcodeproj")

# ---------------------------------------------------------------- MissingConfig
B = "MissingConfig"
missing_settings = app_settings(INFOPLIST_FILE="MissingConfig/Info.plist")
ids = project("MissingConfig", B, ["Debug", "Release"], {"Debug": PROJECT_DEBUG, "Release": PROJECT_RELEASE}, [
    {"name": "MissingConfig", "type": "com.apple.product-type.application",
     "sources": ["MissingConfig/CameraViewController.swift", "MissingConfig/APIClient.swift", "MissingConfig/Settings.swift"],
     "resources": ["MissingConfig/Info.plist"],
     "settings": {"Debug": missing_settings, "Release": missing_settings}},
])
write(f"{B}/MissingConfig/Info.plist", plist({
    "CFBundleDevelopmentRegion": "$(DEVELOPMENT_LANGUAGE)",
    "CFBundleExecutable": "$(EXECUTABLE_NAME)",
    "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleName": "$(PRODUCT_NAME)",
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)",
    "NSMicrophoneUsageDescription": "",
    "UILaunchStoryboardName": "LaunchScreen",
}))
write(f"{B}/MissingConfig/CameraViewController.swift", '''import AVFoundation
import UIKit

final class CameraViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            print("Camera access: \\(granted)")
        }
    }
}
''')
write(f"{B}/MissingConfig/APIClient.swift", '''import Foundation

enum APIClient {
    // Fake credentials used to exercise the secret scanner.
    static let awsAccessKeyID = "AKIAIOSFODNN7EXAMPLE"
    static let apiSecret = "q8Zt3vN1pLx7Rk2Wm9Yc"
    static let analyticsKey = "a1b2c3d4e5f6g7h8i9j0" // appstoreready:ignore
}
''')
write(f"{B}/MissingConfig/Settings.swift", '''import Foundation

struct Settings {
    var lastSync: Date? {
        UserDefaults.standard.object(forKey: "lastSync") as? Date
    }
}
''')
scheme(f"{B}/MissingConfig.xcodeproj/xcshareddata/xcschemes/MissingConfig.xcscheme", "MissingConfig", ids["MissingConfig"], "MissingConfig", "MissingConfig.xcodeproj", archive="Debug")

# ---------------------------------------------------------------- Malformed
B = "Malformed"
mal_settings = app_settings(INFOPLIST_FILE="Malformed/Info.plist", ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon",
                            PRODUCT_BUNDLE_IDENTIFIER="com.acme.malformed", MARKETING_VERSION="1.0", CURRENT_PROJECT_VERSION="1")
ids = project("Malformed", B, ["Debug", "Release"], {"Debug": PROJECT_DEBUG, "Release": PROJECT_RELEASE}, [
    {"name": "Malformed", "type": "com.apple.product-type.application",
     "sources": ["Malformed/App.swift"],
     "resources": ["Malformed/Info.plist", "Malformed/Assets.xcassets", "Malformed/PrivacyInfo.xcprivacy"],
     "settings": {"Debug": mal_settings, "Release": mal_settings}},
])
write(f"{B}/Malformed/App.swift", 'import SwiftUI\n\n@main\nstruct MalformedApp: App {\n    var body: some Scene { WindowGroup { Text("Hi") } }\n}\n')
write(f"{B}/Malformed/Info.plist", '''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleIdentifier</key>
\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)
\t<key>CFBundleVersion</key>
</dict>
''')
write(f"{B}/Malformed/PrivacyInfo.xcprivacy", '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>NSPrivacyTracking</key>\n')
write(f"{B}/Malformed/Assets.xcassets/Contents.json", '{"info": {"author": "xcode", "version": 1}}\n')
write(f"{B}/Malformed/Assets.xcassets/AppIcon.appiconset/Contents.json", '{"images": [ {"idiom": "universal", \n')

# ---------------------------------------------------------------- BrokenProject
write("BrokenProject/BrokenProject.xcodeproj/project.pbxproj", '''// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tclasses = {
\t};
\tobjectVersion = 77;
\tobjects = {
\t\tAAAAAAAAAAAAAAAAAAAAAAAA = {isa = PBXProject; buildConfigurationList = BBBBBBBBBBBBBBBBBBBBBBBB;
''')

# ---------------------------------------------------------------- MultiTarget
B = "MultiTarget"
shop = app_settings(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", GENERATE_INFOPLIST_FILE="YES",
                    PRODUCT_BUNDLE_IDENTIFIER="com.acme.shop")
widget = {"GENERATE_INFOPLIST_FILE": "YES", "INFOPLIST_KEY_CFBundleDisplayName": "Shop Widget",
          "MARKETING_VERSION": "1.9.0", "PRODUCT_BUNDLE_IDENTIFIER": "com.acme.shop.widget",
          "PRODUCT_NAME": "$(TARGET_NAME)", "SKIP_INSTALL": "YES", "SWIFT_VERSION": "5.0"}
kit = {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "com.acme.shopkit", "PRODUCT_NAME": "$(TARGET_NAME:c99extidentifier)"}
tests = {"GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": "com.acme.shop.tests"}
multi_project = {"Debug": dict(PROJECT_DEBUG, MARKETING_VERSION="2.0.0", CURRENT_PROJECT_VERSION="7"),
                 "Release": dict(PROJECT_RELEASE, MARKETING_VERSION="2.0.0", CURRENT_PROJECT_VERSION="7")}
ids = project("MultiTarget", B, ["Debug", "Release"], multi_project, [
    {"name": "Shop", "type": "com.apple.product-type.application",
     "sources": ["Shop/ShopApp.swift"], "resources": ["Shop/Assets.xcassets", "Shop/PrivacyInfo.xcprivacy"],
     "settings": {"Debug": shop, "Release": shop}},
    {"name": "ShopWidget", "type": "com.apple.product-type.app-extension",
     "sync": {"ShopWidget": ["Preview/PreviewLocation.swift"]},
     "settings": {"Debug": widget, "Release": widget}},
    {"name": "ShopKit", "type": "com.apple.product-type.framework",
     "sources": ["ShopKit/Cart.swift"], "settings": {"Debug": kit, "Release": kit}},
    {"name": "ShopTests", "type": "com.apple.product-type.bundle.unit-test",
     "sources": ["ShopTests/CartTests.swift"], "settings": {"Debug": tests, "Release": tests}},
])
write(f"{B}/Shop/ShopApp.swift", 'import SwiftUI\n\n@main\nstruct ShopApp: App {\n    var body: some Scene { WindowGroup { Text("Shop") } }\n}\n')
app_icon(f"{B}/Shop/Assets.xcassets")
write(f"{B}/Shop/PrivacyInfo.xcprivacy", plist({"NSPrivacyTracking": False, "NSPrivacyAccessedAPITypes": [], "NSPrivacyCollectedDataTypes": []}))
write(f"{B}/ShopWidget/ShopWidget.swift", '''import WidgetKit
import SwiftUI

struct CartProvider: TimelineProvider {
    private let shared = UserDefaults(suiteName: "group.com.acme.shop")

    func placeholder(in context: Context) -> SimpleEntry { SimpleEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) { completion(SimpleEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        completion(Timeline(entries: [SimpleEntry(date: .now)], policy: .atEnd))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
}
''')
write(f"{B}/ShopWidget/Preview/PreviewLocation.swift", '''import CoreLocation

// Excluded from the widget target; only used by Xcode previews.
let previewManager: CLLocationManager = {
    let manager = CLLocationManager()
    manager.requestWhenInUseAuthorization()
    return manager
}()
''')
write(f"{B}/ShopKit/Cart.swift", 'public struct Cart {\n    public var items: [String] = []\n    public init() {}\n}\n')
write(f"{B}/ShopTests/CartTests.swift", '''import XCTest

final class CartTests: XCTestCase {
    // A fake key used to check that the scanner downgrades findings in tests.
    let stubKey = "AKIAIOSFODNN7EXAMPLE"

    func testEmptyCart() {
        XCTAssertTrue(true)
    }
}
''')
scheme(f"{B}/MultiTarget.xcodeproj/xcshareddata/xcschemes/Shop.xcscheme", "Shop", ids["Shop"], "Shop", "MultiTarget.xcodeproj")

# ---------------------------------------------------------------- MultiConfig
B = "MultiConfig"
mc_target = {c: app_settings(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", INFOPLIST_FILE="MultiConfig/Info.plist")
             for c in ["Debug", "Staging", "Release"]}
staging = dict(PROJECT_RELEASE, SWIFT_OPTIMIZATION_LEVEL="-Onone")
ids = project("MultiConfig", B, ["Debug", "Staging", "Release"],
              {"Debug": PROJECT_DEBUG, "Staging": staging, "Release": PROJECT_RELEASE},
              [{"name": "MultiConfig", "type": "com.apple.product-type.application",
                "sources": ["MultiConfig/MultiConfigApp.swift"],
                "resources": ["MultiConfig/Info.plist", "MultiConfig/Assets.xcassets"],
                "settings": mc_target}],
              project_xcconfigs={"Debug": "Config/Debug.xcconfig", "Staging": "Config/Staging.xcconfig",
                                 "Release": "Config/Release.xcconfig"},
              extra_groups=["Config/Shared.xcconfig"])
write(f"{B}/Config/Shared.xcconfig", '// Settings shared by every configuration.\nPRODUCT_BUNDLE_IDENTIFIER = com.acme.multiconfig\nMARKETING_VERSION = 3.1.0\n')
write(f"{B}/Config/Debug.xcconfig", '#include "Shared.xcconfig"\nCURRENT_PROJECT_VERSION = 100\n')
write(f"{B}/Config/Staging.xcconfig", '#include "Shared.xcconfig"\n\nPRODUCT_BUNDLE_IDENTIFIER = com.acme.multiconfig.staging\nCURRENT_PROJECT_VERSION = 101\nSWIFT_ACTIVE_COMPILATION_CONDITIONS = STAGING DEBUG\n')
write(f"{B}/Config/Release.xcconfig", '#include "Shared.xcconfig"\nCURRENT_PROJECT_VERSION = 102\n')
write(f"{B}/MultiConfig/Info.plist", plist({
    "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "$(PRODUCT_BUNDLE_PACKAGE_TYPE)",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "UILaunchScreen": {},
}))
write(f"{B}/MultiConfig/MultiConfigApp.swift", 'import SwiftUI\n\n@main\nstruct MultiConfigApp: App {\n    var body: some Scene { WindowGroup { Text("Config") } }\n}\n')
app_icon(f"{B}/MultiConfig/Assets.xcassets")
scheme(f"{B}/MultiConfig.xcodeproj/xcshareddata/xcschemes/MultiConfig.xcscheme", "MultiConfig", ids["MultiConfig"], "MultiConfig", "MultiConfig.xcodeproj", archive="Staging")

# ---------------------------------------------------------------- WorkspaceApp
B = "WorkspaceApp"
ws = app_settings(ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon", GENERATE_INFOPLIST_FILE="YES", CURRENT_PROJECT_VERSION="3",
                  MARKETING_VERSION="1.0.0", PRODUCT_BUNDLE_IDENTIFIER="com.acme.workspaceapp")
ids = project("App", f"{B}/App", ["Debug", "Release"], {"Debug": PROJECT_DEBUG, "Release": PROJECT_RELEASE}, [
    {"name": "App", "type": "com.apple.product-type.application", "sources": ["App/AppMain.swift"],
     "resources": ["App/Assets.xcassets"], "settings": {"Debug": ws, "Release": ws}}])
write(f"{B}/App/App/AppMain.swift", 'import SwiftUI\n\n@main\nstruct AppMain: App {\n    var body: some Scene { WindowGroup { Text("Workspace") } }\n}\n')
app_icon(f"{B}/App/App/Assets.xcassets")
write(f"{B}/WorkspaceApp.xcworkspace/contents.xcworkspacedata", '''<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <Group
      location = "group:App"
      name = "App">
      <FileRef
         location = "group:App.xcodeproj">
      </FileRef>
   </Group>
</Workspace>
''')
scheme(f"{B}/WorkspaceApp.xcworkspace/xcshareddata/xcschemes/App.xcscheme", "App", ids["App"], "App", "App/App.xcodeproj")

# ---------------------------------------------------------------- Hardening
# Security, signing, configuration, and guideline issues in one iOS app.
B = "Hardening"
hard = app_settings(INFOPLIST_FILE="Hardening/Info.plist", ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon",
                    PRODUCT_BUNDLE_IDENTIFIER="com.acme.hardening", MARKETING_VERSION="1.0.0", CURRENT_PROJECT_VERSION="5",
                    CODE_SIGN_STYLE="Manual", DEVELOPMENT_TEAM="ABCDE12345", IPHONEOS_DEPLOYMENT_TARGET="12.0",
                    CODE_SIGN_ENTITLEMENTS="Hardening/Hardening.entitlements")
hard_release = dict(PROJECT_RELEASE, DEBUG_INFORMATION_FORMAT="dwarf")
ids = project("Hardening", B, ["Debug", "Release"], {"Debug": PROJECT_DEBUG, "Release": hard_release}, [
    {"name": "Hardening", "type": "com.apple.product-type.application",
     "sources": ["Hardening/HardeningApp.swift", "Hardening/Network.swift", "Hardening/Background.swift",
                 "Hardening/Store.swift", "Hardening/Account.swift", "Hardening/Health.swift"],
     "resources": ["Hardening/Info.plist", "Hardening/Assets.xcassets"],
     "scripts": ["Upload dSYMs"],
     "settings": {"Debug": hard, "Release": hard}},
])
write(f"{B}/Hardening/Info.plist", plist({
    "CFBundleExecutable": "$(EXECUTABLE_NAME)", "CFBundleIdentifier": "$(PRODUCT_BUNDLE_IDENTIFIER)",
    "CFBundleName": "$(PRODUCT_NAME)", "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": "$(MARKETING_VERSION)", "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
    "ITSAppUsesNonExemptEncryption": True,
    "NSLocationAlwaysAndWhenInUseUsageDescription": "Your location is used to log trips in the background.",
    "NSAppTransportSecurity": {
        "NSAllowsArbitraryLoadsInWebContent": True,
        "NSExceptionDomains": {
            "legacy.acme.com": {"NSExceptionAllowsInsecureHTTPLoads": True, "NSExceptionMinimumTLSVersion": "TLSv1.0"},
            "localhost": {"NSExceptionAllowsInsecureHTTPLoads": True},
        },
    },
    "UIBackgroundModes": ["processing", "remote-notifications"],
    "BGTaskSchedulerPermittedIdentifiers": ["com.acme.hardening.cleanup"],
}))
write(f"{B}/Hardening/Hardening.entitlements", plist({
    "com.apple.developer.associated-domains": ["applinks:acme.com", "links.acme.com"],
    "com.apple.security.application-groups": ["com.acme.shared"],
    "aps-environment": "staging",
    "com.apple.developer.healthkit": True,
    "get-task-allow": True,
}))
write(f"{B}/Hardening/HardeningApp.swift", 'import SwiftUI\n\n@main\nstruct HardeningApp: App {\n    var body: some Scene { WindowGroup { Text("Hardening").accessibilityLabel("Title") } }\n}\n')
write(f"{B}/Hardening/Network.swift", '''import Foundation

enum Endpoints {
    static let legacy = URL(string: "http://legacy.acme.com/feed")!
    static let reports = URL(string: "http://reports.acme-analytics.net/v1/upload")!
    static let local = URL(string: "http://localhost:8080")!
}
''')
write(f"{B}/Hardening/Background.swift", '''import BackgroundTasks

enum BackgroundWork {
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.acme.hardening.refresh", using: nil) { task in
            task.setTaskCompleted(success: true)
        }
    }
}
''')
write(f"{B}/Hardening/Store.swift", 'import StoreKit\n\nfunc loadProducts() async throws -> [Product] {\n    try await Product.products(for: ["pro"])\n}\n')
write(f"{B}/Hardening/Account.swift", '''import GoogleSignIn

final class AccountService {
    func signIn() { GIDSignIn.sharedInstance.signIn(withPresenting: UIViewController()) { _, _ in } }
    func signUp(email: String) {}
}
''')
write(f"{B}/Hardening/Health.swift", '''import HealthKit

func requestHealth(store: HKHealthStore) {
    store.requestAuthorization(toShare: [], read: []) { _, _ in }
}
''')
write(f"{B}/Hardening/Certificates/distribution.p12", b"\x30\x82\x00\x10not-a-real-certificate", binary=True)
app_icon(f"{B}/Hardening/Assets.xcassets", pixels=512)
scheme(f"{B}/Hardening.xcodeproj/xcshareddata/xcschemes/Hardening.xcscheme", "Hardening", ids["Hardening"], "Hardening", "Hardening.xcodeproj")

# ---------------------------------------------------------------- PrivacyIssues
# Privacy manifest values, tracking, and third-party SDKs.
B = "PrivacyIssues"
priv = app_settings(GENERATE_INFOPLIST_FILE="YES", ASSETCATALOG_COMPILER_APPICON_NAME="AppIcon",
                    PRODUCT_BUNDLE_IDENTIFIER="com.acme.privacy", MARKETING_VERSION="1.0.0", CURRENT_PROJECT_VERSION="1",
                    DEVELOPMENT_TEAM="ABCDE12345", INFOPLIST_KEY_UILaunchScreen_Generation="YES",
                    INFOPLIST_KEY_ITSAppUsesNonExemptEncryption="NO",
                    INFOPLIST_KEY_NSUserTrackingUsageDescription="Used to measure ad campaigns.")
ids = project("PrivacyIssues", B, ["Debug", "Release"], {"Debug": PROJECT_DEBUG, "Release": PROJECT_RELEASE}, [
    {"name": "PrivacyIssues", "type": "com.apple.product-type.application",
     "sources": ["PrivacyIssues/PrivacyApp.swift", "PrivacyIssues/Tracking.swift"],
     "resources": ["PrivacyIssues/Assets.xcassets", "PrivacyIssues/PrivacyInfo.xcprivacy"],
     "settings": {"Debug": priv, "Release": priv}},
])
write(f"{B}/PrivacyIssues/PrivacyApp.swift", '''import SwiftUI

@main
struct PrivacyApp: App {
    @AppStorage("launches") private var launches = 0
    private let started = ProcessInfo.processInfo.systemUptime

    var body: some Scene { WindowGroup { Text("Privacy").accessibilityLabel("Title") } }
}
''')
write(f"{B}/PrivacyIssues/Tracking.swift", '''import AppTrackingTransparency

func askToTrack() {
    ATTrackingManager.requestTrackingAuthorization { _ in }
}
''')
write(f"{B}/PrivacyIssues/PrivacyInfo.xcprivacy", plist({
    "NSPrivacyTracking": False,
    "NSPrivacyTrackingDomains": ["metrics.example-tracker.com"],
    "NSPrivacyCollectedDataTypes": [
        {"NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypePhotosOrVideos", "NSPrivacyCollectedDataTypeLinked": False,
         "NSPrivacyCollectedDataTypeTracking": False, "NSPrivacyCollectedDataTypePurposes": ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]},
        {"NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeEmailAddress", "NSPrivacyCollectedDataTypePurposes": ["Marketing"]},
    ],
    "NSPrivacyAccessedAPITypes": [
        {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults", "NSPrivacyAccessedAPITypeReasons": ["CA92.1", "C56D.1"]},
        {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryFileTimestamp", "NSPrivacyAccessedAPITypeReasons": ["DDA9.2"]},
        {"NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryNetwork", "NSPrivacyAccessedAPITypeReasons": ["1234.1"]},
    ],
}))
app_icon(f"{B}/PrivacyIssues/Assets.xcassets", alpha=True)
write(f"{B}/PrivacyIssues.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", json.dumps({
    "originHash": "0", "version": 3, "pins": [
        {"identity": "alamofire", "kind": "remoteSourceControl", "location": "https://github.com/Alamofire/Alamofire.git",
         "state": {"revision": "0", "version": "5.9.1"}},
        {"identity": "swift-collections", "kind": "remoteSourceControl", "location": "https://github.com/apple/swift-collections.git",
         "state": {"revision": "0", "version": "1.1.0"}},
    ]}, indent=2) + "\n")
write(f"{B}/Podfile.lock", "PODS:\n  - FirebaseCore (10.0.0):\n    - GoogleUtilities/Environment (~> 7.8)\n  - SDWebImage (5.19.0):\n    - SDWebImage/Core (= 5.19.0)\n  - SDWebImage/Core (5.19.0)\n\nDEPENDENCIES:\n  - FirebaseCore\n  - SDWebImage\n\nCOCOAPODS: 1.15.2\n")
write(f"{B}/Pods/FirebaseCore/FirebaseCore/Sources/FIRApp.m", "// stub\n")
write(f"{B}/Pods/SDWebImage/WebImage/PrivacyInfo.xcprivacy", plist({"NSPrivacyTracking": False}))
write(f"{B}/Frameworks/Lottie.xcframework/Info.plist", plist({"XCFrameworkFormatVersion": "1.0"}))
scheme(f"{B}/PrivacyIssues.xcodeproj/xcshareddata/xcschemes/PrivacyIssues.xcscheme", "PrivacyIssues", ids["PrivacyIssues"], "PrivacyIssues", "PrivacyIssues.xcodeproj")

# ---------------------------------------------------------------- MacApp
B = "MacApp"
mac_project = {c: dict(base, SDKROOT="macosx", MACOSX_DEPLOYMENT_TARGET="10.15") for c, base in (("Debug", PROJECT_DEBUG), ("Release", PROJECT_RELEASE))}
for d in mac_project.values():
    d.pop("IPHONEOS_DEPLOYMENT_TARGET")
mac = {"CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "ABCDE12345", "PRODUCT_NAME": "$(TARGET_NAME)", "SWIFT_VERSION": "5.0",
       "GENERATE_INFOPLIST_FILE": "YES", "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
       "PRODUCT_BUNDLE_IDENTIFIER": "com.acme.macapp", "MARKETING_VERSION": "1.0.0", "CURRENT_PROJECT_VERSION": "1",
       "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity-tools",
       "INFOPLIST_KEY_ITSAppUsesNonExemptEncryption": "NO"}
ids = project("MacApp", B, ["Debug", "Release"], mac_project, [
    {"name": "MacApp", "type": "com.apple.product-type.application",
     "sources": ["MacApp/MacApp.swift"], "resources": ["MacApp/Assets.xcassets"],
     "settings": {"Debug": mac, "Release": mac}},
])
write(f"{B}/MacApp/MacApp.swift", '''import SwiftUI

@main
struct MacApp: App {
    @AppStorage("windowCount") private var windowCount = 1
    var body: some Scene { WindowGroup { Text("Mac").accessibilityLabel("Title") } }
}
''')
app_icon(f"{B}/MacApp/Assets.xcassets", idiom="mac", size="512x512", scale="2x")
scheme(f"{B}/MacApp.xcodeproj/xcshareddata/xcschemes/MacApp.xcscheme", "MacApp", ids["MacApp"], "MacApp", "MacApp.xcodeproj")

# ---------------------------------------------------------------- Multiplatform
# One target for iOS and macOS (SDKROOT = auto); a store-review prompt that is not a purchase.
B = "Multiplatform"
mp_project = {c: dict(base, SDKROOT="auto", SUPPORTED_PLATFORMS="iphoneos iphonesimulator macosx", MACOSX_DEPLOYMENT_TARGET="10.14")
              for c, base in (("Debug", PROJECT_DEBUG), ("Release", PROJECT_RELEASE))}
mp = app_settings(GENERATE_INFOPLIST_FILE="YES", PRODUCT_BUNDLE_IDENTIFIER="com.acme.multiplatform", DEVELOPMENT_TEAM="ABCDE12345",
                  MARKETING_VERSION="1.0.0", CURRENT_PROJECT_VERSION="1")
ids = project("Multiplatform", B, ["Debug", "Release"], mp_project, [
    {"name": "Multiplatform", "type": "com.apple.product-type.application",
     "sources": ["Multiplatform/MultiplatformApp.swift"], "settings": {"Debug": mp, "Release": mp}},
])
write(f"{B}/Multiplatform/MultiplatformApp.swift", '''import StoreKit
import SwiftUI

@main
struct MultiplatformApp: App {
    @Environment(\\.requestReview) private var requestReview
    var body: some Scene { WindowGroup { Button("Rate") { requestReview() }.accessibilityLabel("Rate the app") } }
}
''')

# ---------------------------------------------------------------- Suppressed
B = "Suppressed"
sup = app_settings(GENERATE_INFOPLIST_FILE="YES", PRODUCT_BUNDLE_IDENTIFIER="com.acme.suppressed",
                   MARKETING_VERSION="1.0.0", CURRENT_PROJECT_VERSION="1")
ids = project("Suppressed", B, ["Debug", "Release"], {"Debug": PROJECT_DEBUG, "Release": PROJECT_RELEASE}, [
    {"name": "Suppressed", "type": "com.apple.product-type.application",
     "sources": ["Suppressed/Keys.swift"], "settings": {"Debug": sup, "Release": sup}},
])
write(f"{B}/Suppressed/Keys.swift", 'enum Keys {\n    // AWS documentation example key.\n    static let aws = "AKIAIOSFODNN7EXAMPLE"\n}\n')
write(f"{B}/.appstoreready.yml", '''# Suppressions for the Suppressed fixture.
version: 1
suppressions:
  - rule: ASR008
    reason: AWS documentation example key, not a real credential
    path: Suppressed/Keys.swift
    expires: 2030-12-31
  - rule: ASR009
    reason: Temporary until the scheme is fixed
    expires: 2026-01-31
''')

B = "SuppressedInvalid"
write(f"{B}/.appstoreready.yml", "version: 1\nsuppressions:\n  - rule: ASR999\n    reason: unknown rule\n")
project("SuppressedInvalid", B, ["Debug", "Release"], {"Debug": PROJECT_DEBUG, "Release": PROJECT_RELEASE}, [
    {"name": "SuppressedInvalid", "type": "com.apple.product-type.application",
     "sources": ["SuppressedInvalid/App.swift"], "settings": {"Debug": sup, "Release": sup}},
])
write(f"{B}/SuppressedInvalid/App.swift", "print(1)\n")

# ---------------------------------------------------------------- NoProject
write("NoProject/README.md", "This directory intentionally contains no Xcode project.\n")
print("fixtures written to", ROOT)
