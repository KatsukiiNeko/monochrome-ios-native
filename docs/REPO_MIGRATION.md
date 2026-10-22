# Repository migration — `main` now holds the native app

Date: 2026-10-22. Pushes went to `origin` (`KatsukiiNeko/monochrome-ios-native`)
only. Nothing was pushed to `upstream` and no GitHub settings were touched.

## Facts

| Item | Value |
|---|---|
| `OLD` (previous `origin/main`, old web app) | `a3c86df0436a3eedc341ab5163fc5ee6b1688b5d` |
| `NATIVE` (first native commit, `origin/main` now) | `d2b453d7e5bd4ae10af97b0481d46be8d602e4e5` |
| Backup branch (remote) | `archive/webapp-main-before-native-2026-10-22` |
| Backup branch (local) | `backup/pre-native-rebuild` (same commit) |
| Topology | `OLD` is an ancestor of `NATIVE`, so `main` was fast-forwarded |
| `upstream` | `https://github.com/monochrome-music/monochrome.git` (fetch only, push DISABLED) |

## Commands that ran

```bash
git ls-remote --heads origin
git remote show origin                 # HEAD branch: main
git fetch origin
git fetch upstream
git merge-base --is-ancestor a3c86df d2b453d   # exit 0 -> fast-forward
git push origin a3c86df:refs/heads/archive/webapp-main-before-native-2026-10-22
git push --dry-run origin d2b453d:refs/heads/main
git push origin d2b453d:refs/heads/main
git ls-remote origin refs/heads/main refs/heads/archive/webapp-main-before-native-2026-10-22
git branch -f main d2b453d
git branch --set-upstream-to=origin/main main
git switch -c feat/online-streaming-and-ui d2b453d
```

Verified afterwards: `origin/main` = `d2b453d7…`, archive ref = `a3c86df0…`,
`git remote -v` unchanged. All network git commands ran with
`GIT_TERMINAL_PROMPT=0` and `GIT_SSH_COMMAND='ssh -o BatchMode=yes'`.

## How to restore the old web-app `main` (instructions only, not executed)

```bash
# 1. Fetch the backup branch.
git fetch origin archive/webapp-main-before-native-2026-10-22
# 2. Point local main at it.
git branch -f main origin/archive/webapp-main-before-native-2026-10-22
# 3. Publish it. The remote main has diverged, so a lease-protected force is required.
git push --force-with-lease=main:d2b453d7e5bd4ae10af97b0481d46be8d602e4e5 \
  origin origin/archive/webapp-main-before-native-2026-10-22:refs/heads/main
```

Only run this if you actually want the web app back on `main`; the native
history stays reachable through `feat/online-streaming-and-ui`.

## Side effects to know about

- The old tree contained `.github/workflows/deploy.yml` (plus lint, tests,
  lighthouse, editors-picks and desktop-build workflows). They no longer exist
  on `main`, but a push event may still have triggered an external/hosted deploy
  before or while they were removed. Nothing here can see or undo that; no
  GitHub setting was read or changed.
- GitHub's **Sync fork** on the fork will now offer to reset `main` to
  `upstream/main`, which would discard the native app. Do not use it; merge
  upstream changes into a branch instead.
- `upstream/main` is now `86dc77aa…` and is far ahead of the old fork point, so
  "behind upstream" is expected and harmless.
