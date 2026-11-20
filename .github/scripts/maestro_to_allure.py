#!/usr/bin/env python3
"""Ubah hasil debug Maestro (commands.json) menjadi hasil Allure lengkap dengan step.

Maestro tidak punya output Allure, dan JUnit XML-nya tidak menyimpan step.
Detail per langkah ada di `<test-output-dir>/<timestamp>/<flow>/commands.json`
(data yang sama dipakai Maestro untuk laporan HTML-DETAILED).

Pemakaian:
    python3 maestro_to_allure.py <maestro-test-output-dir> <allure-results-dir> [flow.yaml ...]

Kalau file flow disebutkan, flow yang tidak punya output (mis. Maestro gagal
diinstal atau emulator crash) tetap masuk laporan sebagai "broken".
"""

import hashlib
import json
import os
import re
import shutil
import sys
import uuid

STATUS = {
    "COMPLETED": "passed",
    "WARNED": "passed",
    "FAILED": "failed",
    "SKIPPED": "skipped",
}
# Langkah internal Maestro yang tidak perlu tampil (kecuali kalau gagal).
HIDDEN = {"defineVariablesCommand", "applyConfigurationCommand"}


def selector_text(sel):
    for key in ("textRegex", "idRegex", "text", "id"):
        if sel.get(key):
            return sel[key]
    return json.dumps(sel)


def describe(kind, cmd):
    """Nama step yang mudah dibaca, mengikuti gaya laporan HTML Maestro."""
    if kind == "launchAppCommand":
        name = f'Launch app "{cmd.get("appId")}"'
        if cmd.get("clearState"):
            name += " with clear state"
        if cmd.get("stopApp") is False:
            name += " (without stopping app)"
        return name
    if kind == "assertConditionCommand":
        cond = cmd.get("condition", {})
        if "visible" in cond:
            return f'Assert that "{selector_text(cond["visible"])}" is visible'
        if "notVisible" in cond:
            return f'Assert that "{selector_text(cond["notVisible"])}" is not visible'
        return "Assert condition"
    if kind == "tapOnElement":
        return f'Tap on "{selector_text(cmd.get("selector", {}))}"'
    if kind == "repeatCommand":
        return f'Repeat {cmd.get("times", "")} times'.replace("  ", " ")
    if kind == "pressKeyCommand":
        return f'Press {cmd.get("code")} key'
    if kind == "stopAppCommand":
        return f'Stop app "{cmd.get("appId")}"'
    if kind == "inputTextCommand":
        return f'Input text "{cmd.get("text")}"'
    if kind == "takeScreenshotCommand":
        return f'Take screenshot "{cmd.get("path")}"'
    # Fallback: "scrollCommand" -> "Scroll"
    words = re.sub(r"(?<!^)(?=[A-Z])", " ", kind.removesuffix("Command"))
    return words.capitalize()


def attach(results_dir, src, name, mime):
    ext = os.path.splitext(src)[1]
    target = f"{uuid.uuid4()}-attachment{ext}"
    shutil.copy(src, os.path.join(results_dir, target))
    return {"name": name, "source": target, "type": mime}


def convert_flow(flow_dir, results_dir):
    commands = json.load(open(os.path.join(flow_dir, "commands.json")))
    screenshots = sorted(
        os.listdir(os.path.join(flow_dir, "screenshots"))
        if os.path.isdir(os.path.join(flow_dir, "screenshots"))
        else []
    )

    flow_name = os.path.basename(flow_dir)
    tags = []
    file_name = None
    root_steps, stack = [], []  # stack: (depth, step)
    failure = None
    start = stop = None

    for entry in commands:
        kind, cmd = next(iter(entry["command"].items()))
        meta = entry.get("metadata", {})
        status = STATUS.get(meta.get("status"), "skipped")

        if kind == "applyConfigurationCommand":
            flow_name = cmd.get("config", {}).get("name") or flow_name
            tags = cmd.get("config", {}).get("tags") or []
        if kind == "defineVariablesCommand":
            file_name = cmd.get("env", {}).get("MAESTRO_FILENAME")
        if kind in HIDDEN and status != "failed":
            continue

        # `- takeScreenshot: nama` di flow: tempel gambarnya ke step sebelumnya
        # (level yang sama) dan jangan tampilkan sebagai step tersendiri.
        if kind == "takeScreenshotCommand" and status != "failed":
            depth = meta.get("depth", 0)
            while stack and stack[-1][0] > depth:
                stack.pop()
            path = cmd.get("path", "")
            png = os.path.join(flow_dir, "takeScreenshot", path if path.endswith(".png") else f"{path}.png")
            if stack and os.path.isfile(png):
                stack[-1][1]["attachments"].append(attach(results_dir, png, os.path.basename(png), "image/png"))
                continue

        ts = meta.get("timestamp")
        dur = meta.get("duration") or 0
        if ts is not None:
            start = ts if start is None else min(start, ts)
            stop = ts + dur if stop is None else max(stop, ts + dur)

        step = {
            "name": describe(kind, cmd),
            "status": status,
            "stage": "finished",
            "start": ts,
            "stop": ts + dur if ts is not None else None,
            "steps": [],
            "attachments": [],
        }
        error = meta.get("error")
        if error:
            step["statusDetails"] = {
                "message": error.get("message", ""),
                "trace": error.get("debugMessage", ""),
            }
            if failure is None:
                failure = step["statusDetails"]

        # Screenshot Maestro diberi nama step-<urutan+1>-..., pasangkan ke stepnya.
        prefix = f"step-{meta.get('sequenceNumber', -2) + 1:03d}-"
        for shot in screenshots:
            if shot.startswith(prefix):
                step["attachments"].append(
                    attach(results_dir, os.path.join(flow_dir, "screenshots", shot), shot, "image/png")
                )

        depth = meta.get("depth", 0)
        while stack and stack[-1][0] >= depth:
            stack.pop()
        (stack[-1][1]["steps"] if stack else root_steps).append(step)
        stack.append((depth, step))

    statuses = []

    def collect(steps):
        for s in steps:
            statuses.append(s["status"])
            collect(s["steps"])

    collect(root_steps)
    status = "failed" if "failed" in statuses else "passed"

    attachments = []
    log = os.path.join(flow_dir, "logs", "maestro.log")
    if os.path.isfile(log):
        attachments.append(attach(results_dir, log, "maestro.log", "text/plain"))

    labels = [
        {"name": "framework", "value": "maestro"},
        {"name": "suite", "value": "Maestro"},
    ]
    if file_name:
        labels.append({"name": "subSuite", "value": file_name})
    labels += [{"name": "tag", "value": t} for t in tags]

    result = {
        "uuid": str(uuid.uuid4()),
        "historyId": hashlib.md5(flow_name.encode()).hexdigest(),
        "name": flow_name,
        "fullName": f"maestro.{file_name or flow_name}",
        "status": status,
        "stage": "finished",
        "start": start,
        "stop": stop,
        "labels": labels,
        "steps": root_steps,
        "attachments": attachments,
    }
    if failure:
        result["statusDetails"] = failure
    write_result(results_dir, result)
    return flow_name, status, file_name


def write_result(results_dir, result):
    with open(os.path.join(results_dir, f"{result['uuid']}-result.json"), "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)


def read_header(flow_file):
    """Ambil `name` dan `tags` dari header flow (bagian sebelum `---`)."""
    name, tags, in_tags = None, [], False
    for line in open(flow_file):
        if line.strip() == "---":
            break
        if line.startswith("name:"):
            name = line.split(":", 1)[1].strip().strip("\"'")
        in_tags = line.startswith("tags:") or (in_tags and line.lstrip().startswith("-"))
        if in_tags and line.lstrip().startswith("-"):
            tags.append(line.lstrip()[1:].strip().strip("\"'"))
    return name, tags


def write_broken(results_dir, flow_file):
    """Flow yang tidak menghasilkan output tetap dicatat di laporan."""
    file_name = os.path.splitext(os.path.basename(flow_file))[0]
    name, tags = read_header(flow_file)
    name = name or file_name
    run_url = "{}/{}/actions/runs/{}".format(
        os.environ.get("GITHUB_SERVER_URL", ""),
        os.environ.get("GITHUB_REPOSITORY", ""),
        os.environ.get("GITHUB_RUN_ID", ""),
    )
    labels = [
        {"name": "framework", "value": "maestro"},
        {"name": "suite", "value": "Maestro"},
        {"name": "subSuite", "value": file_name},
    ] + [{"name": "tag", "value": t} for t in tags]
    write_result(results_dir, {
        "uuid": str(uuid.uuid4()),
        "historyId": hashlib.md5(name.encode()).hexdigest(),
        "name": name,
        "fullName": f"maestro.{file_name}",
        "status": "broken",
        "stage": "finished",
        "labels": labels,
        "steps": [],
        "attachments": [],
        "statusDetails": {
            "message": "Flow tidak jalan: Maestro tidak menghasilkan output "
                       "(mis. Maestro gagal diinstal atau emulator bermasalah). "
                       f"Cek log job di {run_url}",
        },
    })
    return name


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    debug_dir, results_dir, flow_files = sys.argv[1], sys.argv[2], sys.argv[3:]
    os.makedirs(results_dir, exist_ok=True)
    done = set()
    for root, _, files in os.walk(debug_dir):
        if "commands.json" in files:
            name, status, file_name = convert_flow(root, results_dir)
            print(f"{status:>7}  {name}")
            done.add(file_name)
    for flow_file in flow_files:
        if os.path.splitext(os.path.basename(flow_file))[0] not in done:
            print(f"{'broken':>7}  {write_broken(results_dir, flow_file)}")
    if not done and not flow_files:
        sys.exit(f"Tidak ada commands.json di {debug_dir}")


if __name__ == "__main__":
    main()
