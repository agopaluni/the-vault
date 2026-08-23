#!/usr/bin/env python3
"""Generate a valid project.pbxproj for The Vault from the source tree.

Run once from the project root: python3 gen_pbxproj.py
"""
import os, uuid

ROOT = os.path.dirname(os.path.abspath(__file__))
APP = "TheVault"          # source folder (unchanged)
TARGET = "The Vault"      # target / product name → builds "The Vault.app"
BUNDLE_ID = "com.thevault.TheVault"

def oid():
    return uuid.uuid4().hex[:24].upper()

# ---- collect source + resource files -------------------------------------
swift_files = []   # (abs_path, rel_path_from_app)
for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, APP)):
    dirnames[:] = [d for d in dirnames if not d.endswith(".xcassets")]
    for f in sorted(filenames):
        if f.endswith(".swift"):
            full = os.path.join(dirpath, f)
            rel = os.path.relpath(full, os.path.join(ROOT, APP))
            swift_files.append((full, rel))
swift_files.sort(key=lambda x: x[1])

assets_rel = "Resources/Assets.xcassets"
entitlements_rel = "TheVault.entitlements"

# ---- build the group tree mirroring folders ------------------------------
# node: {"groups": {name: node}, "files": [(name, rel, oid_fileref, oid_buildfile, kind)]}
def new_node():
    return {"groups": {}, "files": []}

tree = new_node()

def add_file(rel, kind):
    parts = rel.split(os.sep)
    node = tree
    for p in parts[:-1]:
        node = node["groups"].setdefault(p, new_node())
    name = parts[-1]
    fref = oid()
    bfile = oid() if kind in ("source", "resource") else None
    node["files"].append((name, rel, fref, bfile, kind))
    return fref, bfile

source_build_refs = []
resource_build_refs = []

for _, rel in swift_files:
    fref, bfile = add_file(rel, "source")
    source_build_refs.append(bfile)

assets_fref, assets_bfile = add_file(assets_rel, "resource")
resource_build_refs.append(assets_bfile)

ent_fref, _ = add_file(entitlements_rel, "entitlements")

# ---- emit PBXFileReference + PBXBuildFile sections ------------------------
filerefs = []
buildfiles = []

def file_type(name):
    if name.endswith(".swift"): return "sourcecode.swift"
    if name.endswith(".xcassets"): return "folder.assetcatalog"
    if name.endswith(".entitlements"): return "text.plist.entitlements"
    if name.endswith(".plist"): return "text.plist.xml"
    return "text"

# product reference
product_ref = oid()

def walk_emit(node):
    for (name, rel, fref, bfile, kind) in node["files"]:
        ft = file_type(name)
        filerefs.append(
            f'\t\t{fref} /* {name} */ = {{isa = PBXFileReference; '
            f'lastKnownFileType = {ft}; path = "{name}"; sourceTree = "<group>"; }};')
        if kind == "source":
            buildfiles.append(
                f'\t\t{bfile} /* {name} in Sources */ = {{isa = PBXBuildFile; '
                f'fileRef = {fref} /* {name} */; }};')
        elif kind == "resource":
            buildfiles.append(
                f'\t\t{bfile} /* {name} in Resources */ = {{isa = PBXBuildFile; '
                f'fileRef = {fref} /* {name} */; }};')
    for gname, gnode in node["groups"].items():
        walk_emit(gnode)

walk_emit(tree)

# ---- emit PBXGroup section ------------------------------------------------
groups_out = []

def emit_group(node, name, is_root_app=False):
    gid = oid()
    child_lines = []
    # sub-groups first (sorted), then files (sorted)
    sub_ids = []
    for gname in sorted(node["groups"].keys()):
        sub = emit_group(node["groups"][gname], gname)
        sub_ids.append((gname, sub))
    for (gname, sub) in sub_ids:
        child_lines.append(f'\t\t\t\t{sub} /* {gname} */,')
    for (fname, rel, fref, bfile, kind) in sorted(node["files"], key=lambda x: x[0]):
        child_lines.append(f'\t\t\t\t{fref} /* {fname} */,')
    children = "\n".join(child_lines)
    groups_out.append(
        f'\t\t{gid} /* {name} */ = {{\n'
        f'\t\t\tisa = PBXGroup;\n'
        f'\t\t\tchildren = (\n{children}\n\t\t\t);\n'
        f'\t\t\tpath = "{name}";\n'
        f'\t\t\tsourceTree = "<group>";\n'
        f'\t\t}};')
    return gid

app_group_id = emit_group(tree, APP)

# Products group
products_group_id = oid()
groups_out.append(
    f'\t\t{products_group_id} /* Products */ = {{\n'
    f'\t\t\tisa = PBXGroup;\n'
    f'\t\t\tchildren = (\n\t\t\t\t{product_ref} /* {TARGET}.app */,\n\t\t\t);\n'
    f'\t\t\tname = Products;\n'
    f'\t\t\tsourceTree = "<group>";\n'
    f'\t\t}};')

# Main group
main_group_id = oid()
groups_out.append(
    f'\t\t{main_group_id} = {{\n'
    f'\t\t\tisa = PBXGroup;\n'
    f'\t\t\tchildren = (\n'
    f'\t\t\t\t{app_group_id} /* {APP} */,\n'
    f'\t\t\t\t{products_group_id} /* Products */,\n'
    f'\t\t\t);\n'
    f'\t\t\tsourceTree = "<group>";\n'
    f'\t\t}};')

# product file reference
filerefs.append(
    f'\t\t{product_ref} /* {TARGET}.app */ = {{isa = PBXFileReference; '
    f'explicitFileType = wrapper.application; includeInIndex = 0; '
    f'path = "{TARGET}.app"; sourceTree = BUILT_PRODUCTS_DIR; }};')

# ---- build phases ---------------------------------------------------------
sources_phase_id = oid()
resources_phase_id = oid()
frameworks_phase_id = oid()

sources_lines = "\n".join(
    f'\t\t\t\t{b} /* in Sources */,' for b in source_build_refs)
resources_lines = "\n".join(
    f'\t\t\t\t{b} /* in Resources */,' for b in resource_build_refs)

sources_phase = (
    f'\t\t{sources_phase_id} /* Sources */ = {{\n'
    f'\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
    f'\t\t\tfiles = (\n{sources_lines}\n\t\t\t);\n'
    f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};')
resources_phase = (
    f'\t\t{resources_phase_id} /* Resources */ = {{\n'
    f'\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
    f'\t\t\tfiles = (\n{resources_lines}\n\t\t\t);\n'
    f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};')
frameworks_phase = (
    f'\t\t{frameworks_phase_id} /* Frameworks */ = {{\n'
    f'\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n'
    f'\t\t\tfiles = (\n\t\t\t);\n'
    f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};')

# ---- target ---------------------------------------------------------------
target_id = oid()
target_cfg_list = oid()
project_cfg_list = oid()
proj_debug = oid(); proj_release = oid()
tgt_debug = oid(); tgt_release = oid()

common_build = f'''\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = "{APP}/{entitlements_rel}";
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = "The Vault";
\t\t\t\tINFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.photography";
\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "";
\t\t\t\tINFOPLIST_KEY_NSPrincipalClass = NSApplication;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "{TARGET}";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);'''

tgt_debug_cfg = (
    f'\t\t{tgt_debug} /* Debug */ = {{\n\t\t\tisa = XCBuildConfiguration;\n'
    f'\t\t\tbuildSettings = {{\n{common_build}\n\t\t\t}};\n\t\t\tname = Debug;\n\t\t}};')
tgt_release_cfg = (
    f'\t\t{tgt_release} /* Release */ = {{\n\t\t\tisa = XCBuildConfiguration;\n'
    f'\t\t\tbuildSettings = {{\n{common_build}\n\t\t\t}};\n\t\t\tname = Release;\n\t\t}};')

proj_common = '''\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 13.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 5.0;'''

proj_debug_cfg = (
    f'\t\t{proj_debug} /* Debug */ = {{\n\t\t\tisa = XCBuildConfiguration;\n'
    f'\t\t\tbuildSettings = {{\n{proj_common}\n'
    f'\t\t\t\tONLY_ACTIVE_ARCH = YES;\n'
    f'\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n'
    f'\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";\n'
    f'\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n'
    f'\t\t\t}};\n\t\t\tname = Debug;\n\t\t}};')
proj_release_cfg = (
    f'\t\t{proj_release} /* Release */ = {{\n\t\t\tisa = XCBuildConfiguration;\n'
    f'\t\t\tbuildSettings = {{\n{proj_common}\n'
    f'\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-O";\n'
    f'\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n'
    f'\t\t\t}};\n\t\t\tname = Release;\n\t\t}};')

target_cfg_list_obj = (
    f'\t\t{target_cfg_list} /* Build configuration list for PBXNativeTarget */ = {{\n'
    f'\t\t\tisa = XCConfigurationList;\n'
    f'\t\t\tbuildConfigurations = (\n'
    f'\t\t\t\t{tgt_debug} /* Debug */,\n\t\t\t\t{tgt_release} /* Release */,\n\t\t\t);\n'
    f'\t\t\tdefaultConfigurationIsVisible = 0;\n'
    f'\t\t\tdefaultConfigurationName = Release;\n\t\t}};')
project_cfg_list_obj = (
    f'\t\t{project_cfg_list} /* Build configuration list for PBXProject */ = {{\n'
    f'\t\t\tisa = XCConfigurationList;\n'
    f'\t\t\tbuildConfigurations = (\n'
    f'\t\t\t\t{proj_debug} /* Debug */,\n\t\t\t\t{proj_release} /* Release */,\n\t\t\t);\n'
    f'\t\t\tdefaultConfigurationIsVisible = 0;\n'
    f'\t\t\tdefaultConfigurationName = Release;\n\t\t}};')

target_obj = (
    f'\t\t{target_id} /* {TARGET} */ = {{\n'
    f'\t\t\tisa = PBXNativeTarget;\n'
    f'\t\t\tbuildConfigurationList = {target_cfg_list} /* Build configuration list for PBXNativeTarget */;\n'
    f'\t\t\tbuildPhases = (\n'
    f'\t\t\t\t{sources_phase_id} /* Sources */,\n'
    f'\t\t\t\t{frameworks_phase_id} /* Frameworks */,\n'
    f'\t\t\t\t{resources_phase_id} /* Resources */,\n'
    f'\t\t\t);\n'
    f'\t\t\tbuildRules = (\n\t\t\t);\n'
    f'\t\t\tdependencies = (\n\t\t\t);\n'
    f'\t\t\tname = "{TARGET}";\n'
    f'\t\t\tproductName = "{TARGET}";\n'
    f'\t\t\tproductReference = {product_ref} /* {TARGET}.app */;\n'
    f'\t\t\tproductType = "com.apple.product-type.application";\n\t\t}};')

project_id = oid()
project_obj = (
    f'\t\t{project_id} /* Project object */ = {{\n'
    f'\t\t\tisa = PBXProject;\n'
    f'\t\t\tattributes = {{\n'
    f'\t\t\t\tBuildIndependentTargetsInParallel = 1;\n'
    f'\t\t\t\tLastSwiftUpdateCheck = 1500;\n'
    f'\t\t\t\tLastUpgradeCheck = 1500;\n'
    f'\t\t\t\tTargetAttributes = {{\n'
    f'\t\t\t\t\t{target_id} = {{ CreatedOnToolsVersion = 15.0; }};\n'
    f'\t\t\t\t}};\n'
    f'\t\t\t}};\n'
    f'\t\t\tbuildConfigurationList = {project_cfg_list} /* Build configuration list for PBXProject */;\n'
    f'\t\t\tcompatibilityVersion = "Xcode 14.0";\n'
    f'\t\t\tdevelopmentRegion = en;\n'
    f'\t\t\thasScannedForEncodings = 0;\n'
    f'\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n'
    f'\t\t\tmainGroup = {main_group_id};\n'
    f'\t\t\tproductRefGroup = {products_group_id} /* Products */;\n'
    f'\t\t\tprojectDirPath = "";\n'
    f'\t\t\tprojectRoot = "";\n'
    f'\t\t\ttargets = (\n\t\t\t\t{target_id} /* {TARGET} */,\n\t\t\t);\n\t\t}};')

# ---- assemble -------------------------------------------------------------
out = []
out.append("// !$*UTF8*$!")
out.append("{")
out.append("\tarchiveVersion = 1;")
out.append("\tclasses = {")
out.append("\t};")
out.append("\tobjectVersion = 56;")
out.append("\tobjects = {")

out.append("\n/* Begin PBXBuildFile section */")
out.extend(buildfiles)
out.append("/* End PBXBuildFile section */")

out.append("\n/* Begin PBXFileReference section */")
out.extend(filerefs)
out.append("/* End PBXFileReference section */")

out.append("\n/* Begin PBXFrameworksBuildPhase section */")
out.append(frameworks_phase)
out.append("/* End PBXFrameworksBuildPhase section */")

out.append("\n/* Begin PBXGroup section */")
out.extend(groups_out)
out.append("/* End PBXGroup section */")

out.append("\n/* Begin PBXNativeTarget section */")
out.append(target_obj)
out.append("/* End PBXNativeTarget section */")

out.append("\n/* Begin PBXProject section */")
out.append(project_obj)
out.append("/* End PBXProject section */")

out.append("\n/* Begin PBXResourcesBuildPhase section */")
out.append(resources_phase)
out.append("/* End PBXResourcesBuildPhase section */")

out.append("\n/* Begin PBXSourcesBuildPhase section */")
out.append(sources_phase)
out.append("/* End PBXSourcesBuildPhase section */")

out.append("\n/* Begin XCBuildConfiguration section */")
out.extend([proj_debug_cfg, proj_release_cfg, tgt_debug_cfg, tgt_release_cfg])
out.append("/* End XCBuildConfiguration section */")

out.append("\n/* Begin XCConfigurationList section */")
out.extend([project_cfg_list_obj, target_cfg_list_obj])
out.append("/* End XCConfigurationList section */")

out.append("\t};")
out.append(f"\trootObject = {project_id} /* Project object */;")
out.append("}")

os.makedirs(os.path.join(ROOT, "TheVault.xcodeproj"), exist_ok=True)
with open(os.path.join(ROOT, "TheVault.xcodeproj", "project.pbxproj"), "w") as f:
    f.write("\n".join(out) + "\n")

print(f"Wrote project.pbxproj with {len(swift_files)} swift files.")
