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
identify `native-codecs.2`.

## macOS arm64

```bash
./dawn/build-macos.sh "$HOME/DawnCEFBuild/.../<distribution>"
```

The macOS build requires the full Xcode 26 toolchain selected with
`xcode-select`.

## Runtime contract

The Java classes remain the upstream `146.0.10` classes. Dawn changes only the
native archive coordinates and pins its SHA-256. The custom native engine is
`146.0.12+g316d9cf+chromium-146.0.7680.179`, while the package keeps the
upstream JCEF compatibility tag:

```text
jcef-d3de827+cef-146.0.10+g8219561+chromium-146.0.7680.179
```

Every runtime package includes `build_meta.json` with
`dawn_codec_revision=native-codecs.2`, and the asset filename also includes the
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
