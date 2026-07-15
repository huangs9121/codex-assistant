# Codex Assistant Monorepo Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the existing Codex Quota repository into a future-ready `codex助手` monorepo, preserve Git history, rebuild from the new path, and publish it as a public MIT-licensed GitHub repository.

**Architecture:** The Git root becomes `/Users/openclaw/Projects/codex助手`; the current Swift package lives at `apps/codex-quota`, shared project documentation lives at `docs`, and generated artifacts remain local under ignored `outputs`. The existing build script's two-level workspace lookup will resolve to the new monorepo root without extra path abstraction.

**Tech Stack:** Git, GitHub CLI, Swift Package Manager, AppKit, shell, Markdown, MIT License.

---

### Task 1: Move the repository and preserve history

**Files:**
- Move repository: `work/CodexQuota` → `/Users/openclaw/Projects/codex助手`
- Move package files: repository root → `apps/codex-quota`
- Modify: `.gitignore`

- [ ] Confirm the source repository is clean and the destination does not exist.
- [ ] Move the complete repository directory so `.git` history is preserved.
- [ ] Use `git mv` for `Package.swift`, `Scripts`, `Sources`, and `Tests` into `apps/codex-quota`.
- [ ] Ignore root `outputs/` and Swift build/cache directories at any depth.

### Task 2: Consolidate documentation and artifacts

**Files:**
- Move: `work/docs/superpowers` → `docs/superpowers`
- Move: `outputs` → `/Users/openclaw/Projects/codex助手/outputs`
- Create: `README.md`
- Create: `LICENSE`

- [ ] Move the existing project specs and plans into the repository.
- [ ] Move the current App and ZIP into ignored root `outputs`.
- [ ] Add a Chinese README covering vision, current functionality, directory layout, build commands, data source, and privacy.
- [ ] Add the standard MIT License for 2026 `huangs9121`.

### Task 3: Verify and commit the migrated project

- [ ] Run `swift run -Xswiftc -warnings-as-errors CodexQuotaCoreTests` from `apps/codex-quota` and expect 62/62.
- [ ] Run the transactional build script from `/tmp` and verify App/ZIP signatures, arm64 architecture, permissions, and extraction.
- [ ] Stop the old-path process and launch the App from the new `outputs` path for at least one 15-second cycle.
- [ ] Review `git status`, staged diff, ignored artifacts, and secret scan before committing.
- [ ] Commit the monorepo migration on `main`.

### Task 4: Create and verify the public GitHub repository

- [ ] Create `huangs9121/codex-assistant` as a public GitHub repository with description `Codex 使用辅助工具合集` and source set to the migrated local repository.
- [ ] Push local `main` and set upstream tracking.
- [ ] Verify repository visibility is `PUBLIC`, license metadata is MIT, default branch is `main`, and local HEAD matches `origin/main`.
- [ ] Return the local path, GitHub URL, commit hash, test count, and distribution paths.
