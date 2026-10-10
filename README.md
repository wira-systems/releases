# Wira Systems releases

Where Wira Systems' apps are **built**, never where they are published. This repository is public so that GitHub's Linux, Windows and macOS machines build here for free; it holds no source and keeps no installers. Each app's source is read privately during a build, and its finished files are handed to that app's own **private** repository, where only Wira Systems sees them.

Shops get Wira POS from the app stores (Microsoft Store, Mac App Store, Snap Store for Ubuntu), not from here.

## The apps

| App | Its private repository | Workflow here | Its tags |
| --- | --- | --- | --- |
| **Wira POS**, the point of sale shops use | `wira-systems/pos` | `.github/workflows/pos.yml` (Wira POS) | `v0.10.0`, `v0.11.0-beta.1` |
| **Activator**, Wira Systems' own tool that issues activation keys; never for shops | `wira-systems/activator` | `.github/workflows/activator.yml` (Activator) | `v0.1.0` |

## How a build works

Both workflows run **only by hand**, for a tag of the app that already exists. Nothing runs on a schedule.

1. **Find:** it checks the tag exists in the app's private repository, reading it with that app's read-only deploy key.
2. **Draft:** it makes a draft release here, `pos-v0.10.0-in-transit` or `activator-v0.1.0-in-transit`. Drafts are seen only by members of the organization, never the public.
3. **Build:** each platform builds the app at the tag and attaches its file to the draft:
   - Linux: the `.deb`, on Ubuntu 22.04;
   - Windows: the setup `.exe`, with Inno Setup;
   - macOS: the `.dmg`, one app for Apple Silicon and Intel, signed ad hoc.

   Wira POS also has an Android `.apk`, built only when asked for (`only: apk`), which needs the Android signing secrets below. Each build is checked: Wira POS installs and opens on each system and must carry nothing of the Activator; the Activator must carry no private key, register or backup. Logs are public, so no step prints the source: builds write to logs kept on the machine, and only what went wrong is shown.
4. **Handover:** the files, and the draft's notes for each file, are put on the app's **own release for the tag** in its private repository, using a token that can write to that repository alone. For Wira POS that release is normally made already by pos's release script, with its changelog; the files join it, and a file of the same name is replaced. Where there is none, one is made.
5. **Cleanup:** the draft here is deleted, whether the build got that far or not. Nothing of either app stays in this repository.

## Releasing, step by step

### Wira POS

| Step | Who | What |
| --- | --- | --- |
| 1 | the agent | Runs every check in pos (`python scripts/check.py --all`), fixes what fails on a branch, and opens the promotion PR `development` → `staging`. |
| 2 | **you** | Merge the PR into `staging`. |
| 3 | the agent | Runs the workflow plugin's `release.py --apply` in pos: tags `vX.Y.0-beta.1` on `staging` and publishes its notes on pos's release page. A beta gets no installers. Then opens the PR `staging` → `main`. |
| 4 | **you** | Merge the PR into `main`. |
| 5 | the agent | Runs `release.py --apply` again: tags `vX.Y.0` on `main`, with its notes on pos's release page. |
| 6 | the agent | Starts the build: `gh workflow run pos.yml -R wira-systems/releases -f tag=vX.Y.0`, and watches it (about 12 minutes). |
| 7 | — | The `.deb`, `.exe` and `.dmg` appear on `wira-systems/pos`'s release `vX.Y.0`. |
| 8 | **you**, with the agent's help | Send the new version to each store (see below). |

A file that failed can be built again alone: `gh workflow run pos.yml -R wira-systems/releases -f tag=vX.Y.0 -f only=exe` (`deb`, `exe`, `dmg` or `apk`); it replaces the one on pos's release. To try a branch's builds without handing anything over: `-f try=feat/some-branch`.

### Activator

| Step | Who | What |
| --- | --- | --- |
| 1 | the agent | Runs every check in activator (`python scripts/check.py --all`) and opens the PR `development` → `staging`. |
| 2 | **you** | Merge it. |
| 3 | the agent | `release.py --apply --no-github` in activator: tags the beta on `staging`, with no release page (the workflow makes it). Opens the PR `staging` → `main`. |
| 4 | **you** | Merge it. |
| 5 | the agent | `release.py --apply --no-github` again: tags `vX.Y.Z` on `main`. |
| 6 | the agent | `gh workflow run activator.yml -R wira-systems/releases -f tag=vX.Y.Z`, and watches it (about 10 minutes). |
| 7 | — | The three installers appear on `wira-systems/activator`'s release `vX.Y.Z`, seen only by those with access to it. Install them only on Wira Systems' own computers; the register and the signing keys reach a new computer as a backup restored there, never in an installer. |

## What each side must have in place

Set up once, and kept. If a build fails at **Handover**, check the token first: it may have expired.

| What | Where | Made by | What it does |
| --- | --- | --- | --- |
| Deploy key "wira-systems/releases (read-only, builds releases)" | `wira-systems/pos` → Settings → Deploy keys, read-only | the agent | Lets the Wira POS workflow read pos's source. |
| Secret `POS_DEPLOY_KEY` | this repository → Settings → Secrets and variables → Actions | the agent | The private half of that key. |
| Deploy key "wira-systems/releases (read-only, builds the Activator)" | `wira-systems/activator` → Settings → Deploy keys, read-only | the agent | Lets the Activator workflow read its source. |
| Secret `ACTIVATOR_DEPLOY_KEY` | this repository's secrets | the agent | The private half of that key. |
| Secret `POS_TOKEN` | this repository's secrets | **you** | A fine-grained token: owner `wira-systems`, only `wira-systems/pos`, permission **Contents: Read and write** (Metadata, read-only, comes with it). Lets the handover put files on pos's release. |
| Secret `ACTIVATOR_TOKEN` | this repository's secrets | **you** | The same, for `wira-systems/activator` alone. |
| Secrets `ANDROID_KEYSTORE_BASE`, `ANDROID_KEYSTORE_PASSWORD` | this repository's secrets | not set yet | Sign Wira POS's `.apk`, only when one is asked for; the key lives in `~/.config/axent-android` and the private `axent-labs/android-signing`. |

A token is made on GitHub: your picture → **Settings** → **Developer settings** → **Personal access tokens** → **Fine-grained tokens** → **Generate new token**, with the owner, repository and permission above. Save it without it passing through anyone else, by running this and pasting it when asked:

```
gh secret set POS_TOKEN -R wira-systems/releases
```

The agent can make and register deploy keys (`ssh-keygen`, `gh repo deploy-key add`, `gh secret set`) and never keeps their private halves on disk. Only you can make tokens, and only you merge into `staging` and `main`.

## The stores

Shops install Wira POS from the stores, which take a store package and an account in Wira Systems' name, each yours to open:

| Store | Account | Package |
| --- | --- | --- |
| Microsoft Store | Partner Center, as a company | MSIX |
| Mac App Store | Apple Developer Program | a sandboxed, signed and notarised app |
| Snap Store (Ubuntu) | Snapcraft, as Wira Systems | snap |

Building those packages here and sending them to the stores is planned work, not done yet; until then the installers on pos's releases are for Wira Systems' own use and testing.

## Help

A security problem is never an issue: see [Security](https://github.com/wira-systems/.github/blob/main/SECURITY.md).

Made in Kenya.
