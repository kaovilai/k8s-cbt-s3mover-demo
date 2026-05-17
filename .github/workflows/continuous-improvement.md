---
on:
  push:
    branches: [main]
  schedule: weekly
  workflow_dispatch:
engine: copilot
permissions:
  contents: read
  issues: read
  pull-requests: read
  actions: read
tools:
  edit:
  bash: ["git log", "git diff", "git status", "find", "grep", "cat", "ls", "wc", "head", "tail"]
  github:
    toolsets: [repos, issues, pull_requests]
safe-outputs:
  create-pull-request:
    max: 1
    title-prefix: "[improve] "
    labels: [automation, improvement]
    reviewers: [kaovilai]
    protected-files: fallback-to-issue
  create-issue:
    max: 5
    title-prefix: "[improve] "
    labels: [automation, improvement]
  add-comment:
    max: 10
---

# Continuous Improvement — K8s CBT S3 Mover Demo

You are an expert in Kubernetes, shell scripting, and cloud-native backup/restore workflows. Your job is to review this CBT (Changed Block Tracking) S3 mover demo repository and propose **small, focused improvements** — grouping fixes of the same type into a single PR.

## Repository Context

This repo demonstrates K8s Changed Block Tracking with S3-based data movement. Key areas:
- `scripts/` — Shell scripts for demo automation
- `manifests/` — Kubernetes/OpenShift YAML manifests
- `tools/` — Utility tools
- `demo/` — Demo presentation materials
- `docs/` — Documentation

## Step 1: Check Existing Issues and PRs

1. Search for all open issues with the `improvement` label
2. Search for all open PRs with the `improvement` label
3. **Do NOT create duplicates.** If an existing issue or PR already covers the same topic, stop.

## Step 2: Scan for Improvements

Pick ONE category and find ALL instances:

### High Priority
- **Shell script safety**: Add `set -euo pipefail`, quote variables, handle errors, check command availability
- **Security**: Validate inputs, avoid hardcoded credentials, check for insecure patterns
- **K8s manifest quality**: Add resource limits, health checks, proper labels/annotations

### Medium Priority
- **Code quality**: Extract magic strings, reduce duplication in scripts, improve naming
- **Documentation**: Fix outdated instructions, add missing steps, clarify prerequisites
- **Portability**: Ensure scripts work on both Linux and macOS, handle missing tools gracefully

### Low Priority
- **Demo polish**: Improve presentation materials, add diagrams
- **CI/CD**: Improve workflow reliability

### What NOT to Suggest
- Style-only changes (formatting, whitespace)
- Changes that would break the demo workflow sequence
- Adding complex dependencies

## Step 3: Create PR

1. Create one branch with all fixes of the chosen category
2. Verify shell scripts with `bash -n` syntax check
3. Create ONE PR with clear description

## Important Rules

- **One category per PR** — bundle all fixes of the same type
- **Never break the demo flow** — scripts must work end-to-end
- **Never include `Closes #N` or `Fixes #N` in issue bodies** — only in PR descriptions
