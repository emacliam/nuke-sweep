#!/bin/zsh
set -eu
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build --disable-sandbox --scratch-path .build
APP="$PWD/dist/Nuke Sweep Development.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/debug/Nuke "$APP/Contents/MacOS/Nuke"
python3 - "$APP" <<'PY'
import plistlib,sys,hashlib,subprocess,json
from pathlib import Path
root=Path(sys.argv[1])
info={'CFBundleExecutable':'Nuke','CFBundleIdentifier':'local.nuke.mac.development','CFBundleName':'Nuke Sweep Development','CFBundleDisplayName':'Nuke Sweep Development','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.9.0','CFBundleVersion':'11.1','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication','CFBundleURLTypes':[{'CFBundleURLSchemes':['nuke-development']}],'NukeBuildChannel':'development'}
(root/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
files=[Path('Package.swift')]+sorted(Path('Sources').rglob('*.swift'))
manifest={'channel':'development','head':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'dirty':bool(subprocess.check_output(['git','status','--porcelain'],text=True).strip()),'binarySHA256':hashlib.sha256((root/'Contents/MacOS/Nuke').read_bytes()).hexdigest(),'sourceSHA256':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(root/'Contents/BuildManifest.json').unlink(missing_ok=True)
(root/'Contents/Resources/BuildManifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "Development app (isolated data and preferences): $APP"
