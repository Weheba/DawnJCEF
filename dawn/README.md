# DawnJCEF native codec build

This branch pins JavaCEF commit
`d3de8278626c160d4631db3fda2df7b77cc1e5c4`, the commit used by Dawn's
`me.friwi:jcefmaven:146.0.10` dependency.

No Java or JNI API changes are required for native H.264/AAC decoding. This
fork adds an explicit `CEF_ROOT` input so JavaCEF can be linked against the
patched binary distribution built by `Weheba/DawnCEFSource`.
Generic matching `CEF_ROOT` distributions remain supported. The Dawn build
helpers enable `DAWN_NATIVE_CODECS`, which additionally requires the pinned
codec marker before configuration can proceed.

## Windows

```powershell
.\dawn\build-windows.ps1 `
  -CefRoot D:\DawnCEFBuild\chromium_git\chromium\src\cef\binary_distrib\<distribution> `
  -PythonExecutable D:\depot_tools\.cipd_bin\3.11\bin\python.exe
```

The script configures a Release x64 build, compiles JCEF, and packages a
launcher-compatible native runtime jar under `dawn-artifacts`. It accepts a
`native-codecs.3` distribution (`146.0.15+g566c566`, the shipping Windows
runtime) or a `native-codecs.5` one (`146.0.27+g8a3c83a`, without OpenH264,
whose marker must also say `media.use-openh264=false`); the CEF root's marker
picks the revision. `native-codecs.4` was never released and is refused. The pinned
Chromium formatter downloader requires Python 3.11 or older; pass a compatible
interpreter explicitly when the system default is newer.

`build_meta.json`'s `jcef_url` names the DawnJCEF commit the runtime was built
from: the checked-out `HEAD`, which must have no uncommitted changes, or
`-JcefSourceCommit <sha>` when packaging a build made elsewhere. Packaging fails
if `jcef.dll`'s version stamp (`+g<sha>`) names a different commit. Launchers pin
`jcef_url`, so bump the launcher's pin with every new runtime.

### Synthetic packaging verification

To verify the Windows packaging contract without compiling JCEF, run:

```powershell
.\dawn\verify-windows-packaging-synthetic.ps1
```

The script uses the tracked fixture under
`dawn/test-fixtures/windows-packaging/cef-root`, generates placeholder runtime
files, and verifies that the packaged artifact name and `build_meta.json`
identify `native-codecs.3`. `-CodecRevision native-codecs.5` retargets the
fixture and checks the revision 5 name and metadata instead.

## macOS

```bash
./dawn/build-macos.sh "$HOME/DawnCEFBuild/.../<distribution>"
DAWN_MAC_ARCH=x86_64 ./dawn/build-macos.sh "$HOME/DawnCEFBuild/.../<x64 distribution>" jcef_build_x64
```

The macOS build requires the full Xcode 26 toolchain selected with
`xcode-select`, and `cmake`, `ninja` and `ant` on `PATH`. It needs a
`native-codecs.5` distribution (`146.0.27+g8a3c83a`), the first Dawn CEF build
for macOS; its marker must also say `media.use-openh264=false`. The package name and `build_meta.json` platform follow
the architecture of the built `libjcef.dylib`: `macosx-arm64`, or
`macosx-amd64` for an x86_64 build cross-compiled on Apple silicon.

The packaged files are unsigned (the arm64 linker adds ad-hoc signatures). The
launcher's release signs every nested Mach-O and bundle with its Developer ID
during packaging, as it does for the upstream natives.

## Runtime contract

The Java classes remain the upstream `146.0.10` classes. Dawn changes only the
native archive coordinates and pins its SHA-256. The custom native engine is
`146.0.15+g566c566+chromium-146.0.7680.179` (`native-codecs.3`) or
`146.0.27+g8a3c83a+chromium-146.0.7680.179` (`native-codecs.5`), while the
package keeps the upstream JCEF compatibility tag:

```text
jcef-d3de827+cef-146.0.10+g8219561+chromium-146.0.7680.179
```

Every runtime package includes `build_meta.json` with its
`dawn_codec_revision` (`native-codecs.3` for the shipping Windows runtime), and
the asset filename also includes the codec revision. Keeping the upstream `release_tag` is required because the
upstream `jcefmaven:146.0.10` Java API verifies it before initializing an
already-installed native runtime. Dawn also writes its own `install.lock` and
`dawn-jcef-runtime.properties` markers when assembling the launcher app image.

Do not publish this package under the upstream `jcefmaven` coordinates or reuse
the upstream SHA-256. It is a different native engine even though the Java ABI
and Chromium version are unchanged.

Linux remains on the upstream `146.0.10` native artifact. The Dawn native-codec
variant is deliberately Windows/macOS only because those platforms provide the
required H.264 and AAC operating-system decoders.

## Dawn native extras (`native/DawnCefExtras_N.cpp`)

JNI entry points for `org.cef.browser.DawnCefExtras`, a class that ships in the Dawn launcher (core:browser),
not in the upstream `jcef-api` jar. They add API without changing any upstream class, signature or the JCEF
compatibility tag, and a launcher running an older runtime just sees the capability as absent
(`UnsatisfiedLinkError` on first use, caught once).

- `N_ExtrasVersion()` - capability probe: 1 for the entry points below, 2 adds `N_SetAudioMuted`.
- `N_WasHidden(browser, hidden)` - `CefBrowserHost::WasHidden` for off-screen browsers. Stock JCEF's
  `setWindowVisibility` is a no-op outside macOS windowed browsers, so OSR pages never learned they were
  hidden (compositor kept producing frames, no timer throttling, foreground renderer priority).
- `N_CreatePersistentContext(handler, cachePath, persistSessionCookies)` - `CefRequestContext::CreateContext`
  with a disk `cache_path` (the upstream TODO in `CefRequestContext_N.cpp`). With the Chrome runtime the path
  must be a DIRECT child of `CefSettings.root_cache_path`, otherwise CEF logs "Cannot create profile at path"
  and falls back to the global profile.
- `N_SetAudioMuted(browser, muted)` (extras 2) - `CefBrowserHost::SetAudioMuted` for one browser, so the launcher
  can keep ads silent without Chromium's process-wide `--mute-audio` (which also silences the browsers that are
  meant to play sound). The mute holds for every frame and later navigation of that browser. On the CEF UI
  thread it applies synchronously and returns whether `IsAudioMuted` now matches, so a call from
  `onAfterCreated` (before CEF starts the first navigation) is checked; elsewhere it returns whether the request
  reached a live browser host.

Linked against the upstream 146.0.10 binary distribution, the resulting `jcef.dll` loads and runs against
Dawn's 146.0.15 native-codec `libcef.dll` (same API hash); release builds still link against the DawnCEF
distribution through `dawn/build-windows.ps1`.
