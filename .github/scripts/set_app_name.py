#!/usr/bin/env python3
"""Keep the App Store Connect app name in step with APP_STORE_NAMES below.

Run from .github/scripts/pre-build.sh. App names are unique across the whole App Store, so the
first free one from the list is used. Only possible while a version is still editable (before
anything is submitted for review); any failure is a warning, never a failed build.
"""
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402  (same folder)

BUNDLE_ID = "com.coralcoder.precisiontube"
APP_STORE_NAMES = ["StitchStep", "StitchStep: Frame by Frame", "StitchStep Yarn Video Player"]
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
            "WAITING_FOR_REVIEW", "INVALID_BINARY"}


def request(method, path, token, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(asc.API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        return error.code, {"error": error.read().decode(errors="replace")[:300]}


def main():
    token = asc.make_token()
    status, apps = request("GET", "/apps?filter[bundleId]={}&limit=1".format(BUNDLE_ID), token)
    if status != 200 or not apps.get("data"):
        print("No app record yet; not renaming"); return
    app_id = apps["data"][0]["id"]
    status, infos = request("GET", "/apps/{}/appInfos".format(app_id), token)
    infos = [i for i in infos.get("data", []) if (i.get("attributes") or {}).get("appStoreState") in EDITABLE] \
        or infos.get("data", [])
    for info in infos:
        status, locs = request("GET", "/appInfos/{}/appInfoLocalizations".format(info["id"]), token)
        for loc in locs.get("data", []):
            current = (loc.get("attributes") or {}).get("name")
            if current in APP_STORE_NAMES:
                print("App Store Connect name is already {}".format(current)); return
            for name in APP_STORE_NAMES:
                status, result = request("PATCH", "/appInfoLocalizations/{}".format(loc["id"]), token, {
                    "data": {"type": "appInfoLocalizations", "id": loc["id"], "attributes": {"name": name}}})
                if status == 200:
                    print("Renamed the app in App Store Connect: {} -> {}".format(current, name)); return
                print("Couldn't use {!r} ({}): {}".format(name, status, result.get("error", "")))
    print("::warning::Couldn't rename the app in App Store Connect; rename it there by hand if you like")


if __name__ == "__main__":
    try:
        main()
    except BaseException as error:  # asc.make_token may sys.exit
        print("::warning::App Store Connect rename skipped: {}".format(error))
