#!/usr/bin/env python3
"""Fork-only CI helper: summarize unit test and Android Lint results as Markdown.

Not part of any contribution. Writes the report to stdout.
"""
import glob
import os
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict

MAX_LINT_ROWS = 400

out = []
sha = os.environ.get("REPORT_SHA", "")[:8]
out.append(f"## CI report for `{sha}`\n")

# ---- Unit tests ----
files = sorted(glob.glob("app/build/test-results/testDefaultDebugUnitTest/TEST-*.xml"))
total = failures = errors = skipped = 0
per_class = Counter()
failed = []
for f in files:
    try:
        root = ET.parse(f).getroot()
    except ET.ParseError as ex:
        failed.append((f, "unparseable result file", str(ex)))
        continue
    for case in root.iter("testcase"):
        cls = case.get("classname", "?")
        name = case.get("name", "?")
        total += 1
        per_class[cls] += 1
        for tag in ("failure", "error"):
            el = case.find(tag)
            if el is not None:
                if tag == "failure":
                    failures += 1
                else:
                    errors += 1
                msg = (el.get("message") or el.text or "").strip().splitlines()
                failed.append((cls, name, msg[0][:300] if msg else ""))
        if case.find("skipped") is not None:
            skipped += 1

out.append("### Unit tests\n")
out.append(f"TESTS_TOTAL={total} TESTS_FAILED={failures} TESTS_ERRORS={errors} TESTS_SKIPPED={skipped} RESULT_FILES={len(files)}\n")
if failed:
    out.append("\nFailed:\n")
    for cls, name, msg in failed:
        out.append(f"- FAIL `{cls}` :: `{name}` :: {msg}")
out.append("\n<details><summary>Tests per class</summary>\n")
for cls, n in sorted(per_class.items()):
    out.append(f"- `{cls}` {n}")
out.append("\n</details>\n")

# ---- Android Lint ----
lint_files = sorted(glob.glob("app/build/reports/lint-results-*.xml"))
out.append("### Android Lint\n")
if not lint_files:
    out.append("LINT_REPORT=missing\n")
else:
    issues = []
    for lf in lint_files:
        root = ET.parse(lf).getroot()
        for issue in root.iter("issue"):
            loc = issue.find("location")
            path = loc.get("file", "") if loc is not None else ""
            path = path.split("/app/", 1)[-1] if "/app/" in path else path
            line = loc.get("line", "") if loc is not None else ""
            issues.append((issue.get("severity", "?"), issue.get("id", "?"), path, line, (issue.get("message") or "").replace("\n", " ")[:240]))
    sev = Counter(i[0] for i in issues)
    out.append(f"LINT_FILE={','.join(os.path.basename(x) for x in lint_files)} LINT_TOTAL={len(issues)} " + " ".join(f"LINT_{k.upper()}={v}" for k, v in sorted(sev.items())) + "\n")
    by_id = defaultdict(int)
    for i in issues:
        by_id[(i[0], i[1])] += 1
    out.append("\n| severity | id | count |\n|---|---|---|")
    for (s, i), n in sorted(by_id.items(), key=lambda x: (-x[1], x[0])):
        out.append(f"| {s} | {i} | {n} |")
    out.append("\n<details><summary>Issues</summary>\n")
    order = {"Fatal": 0, "Error": 1, "Warning": 2, "Information": 3}
    for s, i, p, ln, m in sorted(issues, key=lambda x: (order.get(x[0], 9), x[1], x[2], int(x[3] or 0)))[:MAX_LINT_ROWS]:
        out.append(f"- LINT|{s}|{i}|{p}:{ln}|{m}")
    if len(issues) > MAX_LINT_ROWS:
        out.append(f"- ... {len(issues) - MAX_LINT_ROWS} more")
    out.append("\n</details>\n")

text = "\n".join(out)
print(text[:64000])
