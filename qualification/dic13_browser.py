"""DIC-13 disposable Windows acceptance: real Brave UI actions; no production data."""
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import zipfile
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:19871/strategy"
STAGE = "INIT"

def stage(name):
    global STAGE
    STAGE = name
CANARY = "DIC13_PRIVATE_CANARY_NEVER_EXPORT"
def require(condition, code):
    if not condition:
        raise AssertionError("DIC13_" + code)

def marker(name):
    print("DIC13_" + name + "=PASS", flush=True)

def verify_support_zip(raw):
    require(len(raw) > 1000 and raw[:2] == b"PK", "ZIP_BINARY_INVALID")
    with zipfile.ZipFile(io.BytesIO(raw), "r") as z:
        names = set(z.namelist())
        require(len(names) == len(z.namelist()), "ZIP_DUPLICATE_ENTRY")
        require({"summary.json", "manifest.json", "MANIFEST.sha256", "PRIVACY.txt"}.issubset(names), "ZIP_REQUIRED_FILES_MISSING")
        blobs = {n: z.read(n) for n in names}
        require(sum(map(len, blobs.values())) < 64 * 1024 * 1024, "ZIP_OVERSIZE")
        for name, body in blobs.items():
            require(not name.startswith("/") and ".." not in name.split("/"), "ZIP_PATH_ESCAPE")
            require(CANARY.encode("utf8") not in body, "ZIP_SECRET_CANARY_LEAK")
            require(b"-----BEGIN PRIVATE KEY-----" not in body, "ZIP_PRIVATE_KEY_LEAK")
        manifest = json.loads(blobs["manifest.json"])
        entries = manifest.get("entries", [])
        require(len(entries) > 2, "ZIP_MANIFEST_EMPTY")
        for entry in entries:
            name = entry["path"]
            require(name in blobs, "ZIP_MANIFEST_ENTRY_MISSING")
            require(hashlib.sha256(blobs[name]).hexdigest() == entry["sha256"], "ZIP_MANIFEST_DIGEST_MISMATCH")
            require(len(blobs[name]) == entry["bytes"], "ZIP_MANIFEST_LENGTH_MISMATCH")
        summary = json.loads(blobs["summary.json"])
        require("KTRADE" in summary.get("purpose", ""), "ZIP_BRANDING_MISSING")
        require("KTRADE" in blobs["PRIVACY.txt"].decode("utf8"), "ZIP_PRIVACY_BRANDING_MISSING")
        require(summary.get("broker_read_performed") is False, "ZIP_BROKER_READ")
        require(summary.get("broker_mutation_performed") is False, "ZIP_BROKER_MUTATION")
        require(summary.get("runtime_state_write_performed") is False, "ZIP_RUNTIME_MUTATION")
        require(summary.get("browser_persistence_used") is False, "ZIP_BROWSER_PERSISTENCE")
    marker("ZIP_MANIFEST_HASHES_AND_PRIVACY")

def main():
    stage("BRAVE_BINARY")
    brave, profile, scratch = map(Path, sys.argv[1:])
    require(brave.name.lower() == "brave.exe" and brave.is_file(), "BRAVE_EXECUTABLE_MISSING")
    require(os.environ.get("KTRADE_CI_COINBASE_ALLOWED") == "0", "BROKER_ENV_UNSAFE")
    scratch.mkdir(parents=True, exist_ok=True)
    stage("BRAVE_LAUNCH")
    with sync_playwright() as playwright:
        context = playwright.chromium.launch_persistent_context(
            user_data_dir=str(profile),
            executable_path=str(brave),
            headless=True,
            accept_downloads=True,
            args=["--disable-background-networking", "--disable-extensions",
                  "--no-first-run", "--no-default-browser-check", "--disable-sync"],
            viewport={"width": 1500, "height": 970},
        )
        try:
            def safe_route(route):
                parsed = urlparse(route.request.url)
                if parsed.scheme in ("http", "ws") and parsed.hostname in ("127.0.0.1", "localhost"):
                    route.continue_()
                else:
                    route.abort()
            context.route("**/*", safe_route)
            page = context.pages[0] if context.pages else context.new_page()
            stage("PAGE_GOTO")
            response = page.goto(URL, wait_until="domcontentloaded", timeout=45000)
            require(response is not None and response.status == 200, "BRAVE_OPERATOR_NOT_READY")
            require("KTRADE" in page.title().upper(), "BRAVE_KTRADE_IDENTITY")
            marker("REAL_BRAVE_PAGE")
            stage("DISCLOSURE_OPEN")
            disclosure = page.locator("#incidentReportingDisclosure")
            require(disclosure.count() == 1, "INCIDENT_DISCLOSURE_MISSING")
            # An inner evidence <details> has another <summary>; select only
            # the operator-controlled disclosure's immediate summary.
            summary = disclosure.locator(":scope > summary")
            require(summary.count() == 1, "INCIDENT_DISCLOSURE_SUMMARY_AMBIGUOUS")
            require(summary.is_visible(), "INCIDENT_DISCLOSURE_NOT_VISIBLE")
            summary.click(timeout=25000)
            require(disclosure.get_attribute("open") is not None, "INCIDENT_DISCLOSURE_NOT_OPEN")
            marker("BRAVE_INCIDENT_DISCLOSURE_CLICK")
            stage("INCIDENT_INSPECT")
            inspect = page.locator("#nativeIncidentReviewRefresh")
            inspect.click(timeout=25000)
            page.wait_for_function("() => !['CHECKING','ON DEMAND'].includes(document.getElementById('nativeIncidentReviewState')?.textContent.trim())", timeout=25000)
            status = page.locator("#nativeIncidentReviewState").inner_text().strip()
            require(status != "UNAVAILABLE", "BRAVE_NATIVE_INCIDENT_REVIEW_UNAVAILABLE")
            marker("BRAVE_INSPECT_CLICK")
            stage("INCIDENT_SAVE")
            page.locator("#nativeIncidentSave").click(timeout=25000)
            page.wait_for_function("() => document.getElementById('nativeIncidentSavedStatus')?.textContent.includes('Local report saved and verified:')", timeout=25000)
            marker("BRAVE_INCIDENT_SAVE_CLICK")
            stage("INCIDENT_LIST")
            page.locator("#nativeIncidentList").click(timeout=25000)
            page.wait_for_function("() => document.getElementById('nativeIncidentSavedStatus')?.textContent.includes('Local verified reports:')", timeout=25000)
            marker("BRAVE_INCIDENT_LIST_CLICK")
            stage("INCIDENT_EXPORT")
            link = page.locator("#nativeIncidentDownload")
            require("hidden" not in (link.get_attribute("class") or "").split(), "BRAVE_INCIDENT_DOWNLOAD_HIDDEN")
            with page.expect_download(timeout=25000) as task:
                link.click(timeout=25000)
            incident = task.value
            require(incident.suggested_filename.lower().endswith(".json"), "BRAVE_INCIDENT_EXPORT_FORMAT")
            payload = Path(incident.path()).read_bytes()
            require(len(payload) > 100 and CANARY.encode() not in payload, "BRAVE_INCIDENT_EXPORT_PRIVACY")
            obj = json.loads(payload)
            require(isinstance(obj, dict), "BRAVE_INCIDENT_EXPORT_JSON")
            marker("BRAVE_INCIDENT_EXPORT_CLICK")
            # Real UI user action: select a synthetic product before clicking Export.
            stage("PRODUCT_SELECT")
            product = page.evaluate("() => (typeof S !== 'undefined' && S.product) ? S.product : ''")
            if not product:
                page.locator("#newProduct").fill("BTC-USDC")
                page.locator("#addProduct").click(timeout=25000)
                page.wait_for_function("() => (typeof S !== 'undefined' && !!S.product)", timeout=30000)
            marker("BRAVE_SYNTHETIC_PRODUCT_SELECTED")
            stage("SUPPORT_BUTTON")
            button = page.locator('[data-action="export-support-bundle"]:visible').first
            button.wait_for(state="visible", timeout=20000)
            stage("SUPPORT_DOWNLOAD")
            with page.expect_download(timeout=45000) as task:
                button.click(timeout=20000)
            archive = task.value
            require(re.fullmatch(r"ktrade-support-[a-z0-9_]+-\d{8}T\d{6}Z\.zip", archive.suggested_filename, flags=re.I) is not None, "BRAVE_SUPPORT_FILENAME")
            stage("ZIP_VALIDATION")
            verify_support_zip(Path(archive.path()).read_bytes())
            marker("BRAVE_SUPPORT_EXPORT_CLICK")
            require(page.evaluate("() => location.host") == "127.0.0.1:19871", "BRAVE_ORIGIN_DRIFT")
            marker("BRAVE_LOOPBACK_ONLY")
        finally:
            context.close()

if __name__ == "__main__":
    try:
        main()
    except AssertionError as exc:
        # Emit only fixed internal assertion identifiers; never browser tracebacks.
        code = str(exc)
        if re.fullmatch(r"DIC13_[A-Z0-9_]{2,100}", code):
            print(code + "=FAIL", flush=True)
        else:
            print("DIC13_FAILURE_STAGE_" + STAGE + "=FAIL", flush=True)
        sys.exit(1)
    except Exception:
        # Browser exceptions can contain private URLs, state, or response bodies.
        print("DIC13_FAILURE_STAGE_" + STAGE + "=FAIL", flush=True)
        sys.exit(1)
