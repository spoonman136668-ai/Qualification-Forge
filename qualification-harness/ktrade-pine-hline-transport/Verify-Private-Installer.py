"""Read-only isolated ZIP verification; never extracts or executes package code."""
import argparse, hashlib, io, json, re, stat, zipfile
from pathlib import Path, PurePosixPath
def require(ok, message):
    if not ok: raise RuntimeError(message)
def sha(data): return hashlib.sha256(data).hexdigest()
def read_zip(raw):
    z=zipfile.ZipFile(io.BytesIO(raw)); seen=set()
    require(z.testzip() is None, "ZIP_CRC_FAILED")
    for item in z.infolist():
        name=item.filename; p=PurePosixPath(name)
        require(name and not name.startswith(("/", "\\")) and "\\" not in name and ":" not in name and ".." not in p.parts, "UNSAFE_ZIP_PATH")
        require(name.casefold() not in seen, "DUPLICATE_ZIP_PATH")
        seen.add(name.casefold())
        require(not stat.S_ISLNK(item.external_attr >> 16), "ZIP_LINK_REFUSED")
    return z
def inspect(raw, expected_hash, expected_source):
    require(sha(raw)==expected_hash, "INSTALLER_HASH_MISMATCH")
    installer=read_zip(raw)
    wanted={"KTRADE-Setup.ps1","Manage-KTRADE-FreshInstall.ps1","release-setup.exe","release-launch.exe","release-maintain.exe","KTRADE-Setup.exe","KTRADE-Payload.zip"}
    require(set(installer.namelist())==wanted|{"installer-manifest.json"}, "INSTALLER_FILE_SET_MISMATCH")
    manifest=json.loads(installer.read("installer-manifest.json"))
    require(manifest["schema"]=="ktrade.setup-bundle.v2" and manifest["source_sha"]==expected_source and manifest["live_armed"] is False and manifest["release_authority"]=="none" and manifest["signature_status"]=="unsigned", "INSTALLER_AUTHORITY_MISMATCH")
    require(len(manifest["files"])==7 and {f["name"] for f in manifest["files"]}==wanted, "INSTALLER_MANIFEST_FILE_SET_MISMATCH")
    for row in manifest["files"]:
        data=installer.read(row["name"])
        require(len(data)==row["size"] and sha(data)==row["sha256"], "INSTALLER_COMPONENT_HASH_MISMATCH")
    payload=read_zip(installer.read("KTRADE-Payload.zip"))
    names=payload.namelist()
    roots={n.split("/")[0] for n in names}
    require(len(roots)==1 and re.fullmatch(r"ktrade-rc-package-[a-f0-9]{32}", next(iter(roots))), "PAYLOAD_NONCE_ROOT_MISMATCH")
    prefix=next(iter(roots))+"/KTRADE-WailsPortable/"
    require(all(n.startswith(prefix) for n in names), "PAYLOAD_TOPOLOGY_MISMATCH")
    files={n[len(prefix):]:payload.read(n) for n in names if not n.endswith("/")}
    require(not any(PurePosixPath(n).name.lower() in {".env","config.json","id_rsa","cdp_api_key.json"} for n in files) and not any(n.startswith("data/") and not n.endswith("-proof.json") for n in files), "NONFRESH_PROFILE_OR_CREDENTIALS_REFUSED")
    shell=sha(files["ktrade.exe"]); engine=sha(files["ktrade-engine.exe"])
    for path,schema in [("wails-paper-package-proof.json","ktrade.wails.paper-package.v1"),("data/wails-paper-fresh-data-proof.json","ktrade.wails.fresh-data.v1")]:
        proof=json.loads(files[path])
        require(proof["schema"]==schema and proof["wails_exe_sha256"]==shell and proof["engine_exe_sha256"]==engine and proof["live_armed"] is False, "WAILS_PAIR_PROOF_MISMATCH")
    for path,schema in [("paper-package-proof.json","ktrade.paper.portable-package.v1"),("data/paper-fresh-data-proof.json","ktrade.paper.fresh-data.v1")]:
        proof=json.loads(files[path])
        require(proof["schema"]==schema and proof["exe_sha256"]==engine and proof["live_armed"] is False, "ENGINE_PAIR_PROOF_MISMATCH")
    assets={n:b for n,b in files.items() if n.startswith(("static/","templates/","strategies/"))}
    digest=sha("\n".join(sorted(n+"|"+str(len(b))+"|"+sha(b) for n,b in assets.items())).encode())
    proof=json.loads(files["release-candidate-proof.json"])
    require(proof["schema"]=="ktrade.fresh-release-candidate.v2" and proof["source_sha"]==expected_source and proof["wails_exe_sha256"]==shell and proof["engine_exe_sha256"]==engine and proof["live_armed"] is False and proof["release_authority"]=="none" and proof["installed_data"]=="fresh-only" and proof["asset_files"]==len(assets) and proof["asset_digest_sha256"]==digest, "RELEASE_PAIR_OR_ASSET_PROOF_MISMATCH")
    vendor=json.loads(files["static/vendor/assets-manifest.json"])
    require(vendor["schema"]=="ktrade.offline-vendor.v1" and len(vendor["files"])==118, "EXPECTED_118_VENDOR_MANIFEST_ROWS")
    listed={row["path"] for row in vendor["files"]}
    actual={n[len("static/vendor/"):] for n in assets if n.startswith("static/vendor/")}
    require(len(listed)==118 and "assets-manifest.json" not in listed and actual==listed|{"assets-manifest.json"}, "EXACT_VENDOR_FILE_SET_MISMATCH")
    for row in vendor["files"]:
        require(sha(files["static/vendor/"+row["path"]])==row["sha256"], "VENDOR_CONTENT_HASH_MISMATCH")
    require(len(assets)==180, "EXPECTED_180_ASSETS_MISMATCH")
    return assets, {"installer_sha256":sha(raw),"asset_files":len(assets),"vendor_files":118,"asset_digest_sha256":digest,"wails_sha256":shell,"engine_sha256":engine,"installer_components":7,"zip_layers_crc_and_safe_paths_verified":2}
def main():
    p=argparse.ArgumentParser();p.add_argument("--installer",required=True);p.add_argument("--expected-hash",required=True);p.add_argument("--source",required=True);p.add_argument("--source-tree",required=True);p.add_argument("--checkout",required=True);p.add_argument("--previous-installer",required=True)
    a=p.parse_args()
    assets, result=inspect(Path(a.installer).read_bytes(),a.expected_hash,a.source)
    previous,_=inspect(Path(a.previous_installer).read_bytes(),"83fa999103f8f6c0ce9eb23c2c3ea2a0f707d9ffad471e195fe6656426b94baf","3901f737474f8fb5428dbb0d77a14fcb53d68d89")
    added=sorted(set(assets)-set(previous));removed=sorted(set(previous)-set(assets));changed=sorted(n for n in assets.keys()&previous.keys() if assets[n]!=previous[n])
    require(added==[] and removed==[] and changed==["static/pine_plot_renderer.js"],"EXACT_ONE_ASSET_GUIDE_DELTA_REQUIRED")
    for name in changed:
        require(assets[name].decode("utf-8-sig").replace("\r\n","\n")==Path(a.checkout,name).read_text(encoding="utf-8-sig").replace("\r\n","\n"), "PACKAGED_MARKER_ASSET_SOURCE_MISMATCH")
    result.update(source_sha=a.source,source_tree=a.source_tree,delta_vs_qualified_pr235={"added":added,"removed":removed,"changed":changed,"all_other_179_assets_byte_identical":True,"changed_files_normalized_match_pinned_source":True},owner_data_accessed=False,app_executed=False,live_armed=False,outer_archive_verification="GitHub original artifact digest and transport metadata; outer ZIP bytes not independently inspected in this hosted verification")
    print("PR236_INDEPENDENT_PRIVATE_INSTALLER_VERIFICATION="+json.dumps(result,separators=(",",":")))
if __name__=="__main__": main()
