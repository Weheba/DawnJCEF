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
  -CefRoot D:\DawnCEFBuild\chromium_git\chromium\src\cef\binary_distrib\<distribution>
```

The script configures a Release x64 build, compiles JCEF, and packages a
launcher-compatible native runtime jar under `dawn-artifacts`.

## macOS arm64

```bash
./dawn/build-macos.sh "$HOME/DawnCEFBuild/.../<distribution>"
```

The macOS build requires the full Xcode 26 toolchain selected with
`xcode-select`.

## Runtime contract

The Java classes remain the upstream `146.0.10` classes. Dawn changes only the
native archive coordinates and pins its SHA-256. The native package keeps the
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
and upstream CEF version string are unchanged.

Linux remains on the upstream `146.0.10` native artifact. The Dawn native-codec
variant is deliberately Windows/macOS only because those platforms provide the
required H.264 and AAC operating-system decoders.
