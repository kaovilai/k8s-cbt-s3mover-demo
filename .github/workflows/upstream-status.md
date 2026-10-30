---
on:
  schedule: weekly
  workflow_dispatch:
engine: copilot
permissions:
  contents: read
  issues: read
  pull-requests: read
tools:
  bash: ["cat", "ls", "find", "grep", "head", "tail", "wc"]
  github:
    toolsets: [repos, issues, pull_requests]
    allowed-repos:
      - kubernetes/enhancements
      - kubernetes-csi/external-snapshot-metadata
      - ceph/ceph-csi
      - ceph/ceph-csi-operator
      - velero-io/velero
      - rook/rook
    # Read public upstream repos we do not control, so no author-trust
    # filtering: "approved" would silently drop real PR state and turn a
    # changed item into a false "no change".
    min-integrity: none
network:
  allowed:
    - defaults
    - github
safe-outputs:
  create-issue:
    max: 1
    title-prefix: "[upstream] "
  add-comment:
    max: 3
---

# Upstream Status Check

The Velero and Ceph claims in this repo go stale. Your job is to find out whether
upstream moved, and to say exactly which line of our own materials needs to change.

You are **not** fixing anything. Do not edit files. Do not open a pull request.

## What our materials claim

Read these two files and treat their statements as the baseline:

- `demo/slides.md` — the Velero section: Velero 1.19.0 supports Case 1 (no base
  snapshot needed) and not Case 2 (base snapshot required, Ceph RBD); Ceph falls
  back to a full copy; base-snapshot retention is a proposal tracked by issues
  #10743 and #10744, aimed at a 1.19.x patch with OADP 1.7 as a target and not a
  commitment; the decision order is volume policy, then the driver's
  `requireBaseSnapshotForDelta` flag, then default do-not-keep; a PR status legend
  (MERGED / OPEN / DRAFT / CLOSED) for 10698, 10696, 10700, 10699, 10708, 10710,
  10718, 10691, 10716.
- `README.md` — the same claims in long form, plus the validated Ceph RBD results,
  the note that external-snapshot-metadata#258 is merged but unreleased, and that
  Velero cannot read the driver flag until #10722 lands.

## What to check upstream

1. **kubernetes/enhancements#6479** — the KEP-3314 change documenting
   `requireBaseSnapshotForDelta`. Merged yet? If merged, did the KEP text change
   again afterwards?
2. **kubernetes-csi/external-snapshot-metadata#258** and its releases — is the CRD
   field in a tagged release yet? Compare the latest release date against the PR's
   merge date.
3. **ceph/ceph-csi#6680** (RBD advertising the field) and **#6679** (SELinux host
   mount, fixed by `enableSelinuxHostMount`) — merged or closed?
4. **velero-io/velero** — issues #10743, #10744, #10722 and PRs #10691, #10699,
   #10708, #10710, #10718, #10740: any state change?
5. **velero-io/velero releases** — a new 1.19.x? If so, do the notes mention CBT,
   Ceph RBD, base-snapshot retention, or data mover memory?
6. **rook/rook#18636** and **ceph/ceph-csi-operator#649** — merged?

Fetch each item directly. If one is 404, renamed, or forbidden, say so and skip it —
never guess its state.

## Decide whether to report

If nothing moved, call `noop` with a one-line explanation and stop. Do not create an
issue just to say "no change"; a quiet week should produce no notification.

If something did move, first look for an existing open issue whose title starts with
`[upstream]`. When one is already open, add a comment to it with the new findings
rather than opening a second issue.

## Report format

Keep it short — a maintainer should be able to act without reading the rest of the
thread:

1. **Changed since last check** — one line per item, with the URL.
2. **Materials to update** — for each delta, the `file:line` and one concrete
   suggested wording change. Mirror the repository's existing tone: factual, no
   hype, and keep every hedge ("proposal", "target, not a commitment").
3. **Unchanged** — the items that did not move, one line.

Never invent a fact. If a date, version, or state cannot be confirmed from the
fetched data, write "unconfirmed" instead of filling it in.
