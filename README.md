# WebUntis for Windows 11

Windows 11 desktop app and native Widgets Board provider for WebUntis. API behavior is taken from the KDE Plasma applet in `reference/kde-widget`. See [docs/phase-1-analysis.md](docs/phase-1-analysis.md).

## Status

Phase 2 is the packaged skeleton.

What works:

- `WebUntis.Core` is a portable .NET 10 library. It does not call WebUntis yet.
- `WebUntis.App` is a WinUI 3 window that shows the product name and a not-signed-in state.
- The same executable registers `IWidgetProvider` when the widget host starts it with `-RegisterProcessAsComServer`.
- The widget definition `WebUntis_Today` supports small, medium, and large. It currently sends placeholder Adaptive Card text and does not fetch a timetable.
- `.github/workflows/build.yml` publishes an unsigned MSIX. Signing for a local test is done on your PC, not in CI.

What remains:

- QR login, timetable and inbox client.
- Week and day views.
- Credential Locker and the shared cache.
- Real widget content, countdown, and the open-app action.
- Installing the package on a Windows 11 machine and confirming the window and widget.

## Account model

The KDE widget signs in with a WebUntis QR payload:

```text
untis://setschool?url={host}&school={school}&user={user}&key={secret}
```

That payload is not stored yet. Do not put one in a settings file, a log, or this repository.

## Install a CI build

Download the `webuntis-msix` artifact. With Developer Mode enabled, install the unsigned package:

```powershell
Add-AppxPackage -Path .\WebUntis.msix -AllowUnsigned
```

To sign it yourself first, run `ci/sign-local.ps1` and follow [docs/install-windows.md](docs/install-windows.md). Azure Trusted Signing is a later production step. It is not required for this test. The private key stays on your PC.

The package includes the Windows App Runtime. The widget appears in the Widgets Board only after the MSIX is installed.

## Build

WinUI 3 does not build on Linux. The check is `.github/workflows/build.yml` on `windows-latest`. It uploads an unsigned MSIX and does not create a certificate.

```text
src/WebUntis.Core/     portable client library
src/WebUntis.App/      WinUI 3 app and widget COM server
tests/                 core tests
reference/kde-widget/  API reference
```

## License

MIT. See [LICENSE](LICENSE).
