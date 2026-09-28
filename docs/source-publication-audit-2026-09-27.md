# Source publication audit — 2026-09-27

## Result and scope

No blocking issue was found for making the GitHub repository public after the
source fixes in this audit. Repository visibility was not changed. This is a
pattern-based local review, not a guarantee that arbitrary/encrypted secrets
cannot exist or a legal certification of third-party rights.

The initial review covered the branch and local-ref history through `53501e3`,
tracked files, Git object sizes, source dependencies, attribution and build
instructions. The source-readiness commit is `814a399`; a follow-up fixes clean
imports and adds this record.

## History and private files

- No detected credentials or credential-bearing URLs in branch/remote histories.
- The largest branch-history blob is the Ukon avatar, 20,861,788 bytes. No blob
  reaches 50 MiB or GitHub's 100 MiB individual-file limit. Git LFS is not
  required for the current tracked assets.
- Local Codex checkpoint refs captured an untracked credential file and local
  presentation/encoder artifacts. These refs are not project branches and were
  not pushed. Do not mirror this development checkout or push its internal
  checkpoint refs. Ordinary `main` pushes and a GitHub visibility change do not
  publish them. The files themselves were preserved and now have ignore rules.
- Development notes contain historical local paths and test addresses. They
  are evidence/examples, not private checkout requirements in active builds.

## Licensing and dependency fixes

- Added `UNLICENSE` for original project work and `LICENSES.md` explaining the
  exclusions, third-party terms, asset attribution and unofficial inspiration.
- Confirmed that existing `CREDITS.md` includes kitsune_tsuki's required Ukon
  attribution and custom VRoid permission URL. The model is not CC0.
- Preserved the existing font, animation, addon, forest, audio and viseme notices.
  Future package scripts also copy the project license/credits plus VRM,
  MToon, XR hand and editor-icon notices.
- Added a standalone pinned Nix development shell. Active builds no longer
  assume a private Prim checkout. Windows Rust/MinGW/Opus staging remains
  manual and is explicitly documented.
- Published the missing microphone gate/mute/RMS additions to public
  godot-network-audio at `c76728fa4748defc1137c30d2af055d0dc5d37ca`.
  Existing PCM tap changes were already public. Prim's live remote matched
  local `30d0273`; no Prim changes or visibility changes were needed.
- Verified anonymous access to the pinned NetEq and public Godot integration
  source. Exact revisions and the GNA license-file/Cargo-metadata discrepancy
  are recorded in `docs/native-dependency-provenance.md`.

## Fresh-checkout verification

Created a transport-based local clone with `git clone --no-local`, excluding
untracked files and internal Codex refs. Built Steam Audio and the patched
Godot from pinned public sources, generated WAVs, and ran the standalone Nix
shell with `cargo check --locked` and a full native debug build.
The Nix store and Cargo download cache were available; this was not an
empty-cache/offline build. An anonymous clone of Mushi itself remains a check
for after the owner changes repository visibility.

The first check exposed incomplete fresh imports: `--editor --quit` exited
before fonts/textures were ready. Launcher and check scripts now use
`--import`, which waits for imports. Unused XR Tools Blender sources no longer
require Blender because direct `.blend` import is disabled; runtime GLB assets
remain available. See [Godot's import settings documentation](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-filesystem-import-blender-enabled).

With those exact follow-up files applied to the otherwise clean checkout:

- `./check.sh` passed, including actual UI callbacks, formation forces and
  simulation checks. It also passed in the development checkout.
- Standalone native checks and all four native tests passed, including the
  eight-player localhost relay/capacity test.
- The fresh native debug library linked and loaded into Godot.
- A rendered Vulkan Mobile desktop scene with 512 mushi captured successfully
  and exited with status 0, without script/resource errors in the run log.
- Initial editor plugin startup produced transient icon/preload errors before
  assets were imported. A subsequent editor import resolved those errors;
  minor editor shutdown resource-leak diagnostics remain. They did not prevent
  imports, tests or the rendered game from succeeding.
- Changed shell scripts passed `bash -n`; staged changes passed
  `git diff --check`.

Local logs/capture are retained under the ignored
`artifacts/source-public-audit-20260927/` folder. Temporary checkout and compiler
intermediates were removed after verification. Final published ZIPs and their
hashes were preserved. These documentation/import changes did not rebuild or
replace the submitted jam binaries. Native Windows, headset and WAN behavior
were not retested during this source audit.
