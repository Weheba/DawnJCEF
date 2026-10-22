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
launcher-compatible native runtime jar under `dawn-artifacts`. The pinned
Chromium formatter downloader requires Python 3.11 or older; pass a compatible
interpreter explicitly when the system default is newer.

### Synthetic packaging verification

To verify the Windows packaging contract without compiling JCEF, run:

```powershell
.\dawn\verify-windows-packaging-synthetic.ps1
```

The script uses the tracked fixture under
`dawn/test-fixtures/windows-packaging/cef-root`, generates placeholder runtime
files, and verifies that the packaged artifact name and `build_meta.json`
identify `native-codecs.3`.

## macOS arm64

```bash
./dawn/build-macos.sh "$HOME/DawnCEFBuild/.../<distribution>"
```

The macOS build requires the full Xcode 26 toolchain selected with
`xcode-select`.

## Runtime contract

The Java classes remain the upstream `146.0.10` classes. Dawn changes only the
native archive coordinates and pins its SHA-256. The custom native engine is
`146.0.15+g566c566+chromium-146.0.7680.179`, while the package keeps the
upstream JCEF compatibility tag:

```text
jcef-d3de827+cef-146.0.10+g8219561+chromium-146.0.7680.179
```

Every runtime package includes `build_meta.json` with
`dawn_codec_revision=native-codecs.3`, and the asset filename also includes the
codec revision. Keeping the upstream `release_tag` is required because the
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

- `N_ExtrasVersion()` - capability probe (1).
- `N_WasHidden(browser, hidden)` - `CefBrowserHost::WasHidden` for off-screen browsers. Stock JCEF's
  `setWindowVisibility` is a no-op outside macOS windowed browsers, so OSR pages never learned they were
  hidden (compositor kept producing frames, no timer throttling, foreground renderer priority).
- `N_CreatePersistentContext(handler, cachePath, persistSessionCookies)` - `CefRequestContext::CreateContext`
  with a disk `cache_path` (the upstream TODO in `CefRequestContext_N.cpp`). With the Chrome runtime the path
  must be a DIRECT child of `CefSettings.root_cache_path`, otherwise CEF logs "Cannot create profile at path"
  and falls back to the global profile.

Linked against the upstream 146.0.10 binary distribution, the resulting `jcef.dll` loads and runs against
Dawn's 146.0.15 native-codec `libcef.dll` (same API hash); release builds still link against the DawnCEF
distribution through `dawn/build-windows.ps1`.
