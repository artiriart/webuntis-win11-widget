# WebUntis for Windows 11

Windows 11 desktop app and native Widgets Board provider for WebUntis. API behavior is taken from the KDE Plasma applet in `reference/kde-widget`. See [docs/phase-1-analysis.md](docs/phase-1-analysis.md).

## Status

Phase 2 is the packaged skeleton.

What works:

- `WebUntis.Core` is a portable .NET 10 library. It does not call WebUntis yet.
- `WebUntis.App` is a WinUI 3 window that shows the product name and a not-signed-in state.
- The same executable registers `IWidgetProvider` when the widget host starts it with `-RegisterProcessAsComServer`.
- The widget definition `WebUntis_Today` supports small, medium, and large. It currently sends placeholder Adaptive Card text and does not fetch a timetable.
- `.github/workflows/build.yml` creates a development certificate, signs the MSIX, and uploads `WebUntis.msix` with the public `WebUntis.cer`. The private key is not stored.

What remains:

- QR login, timetable and inbox client.
- Week and day views.
- Credential Locker and the shared cache.
- Real widget content, countdown, and the open-app action.
- Installing the signed package on a Windows 11 machine and confirming the window and widget.

## Account model

The KDE widget signs in with a WebUntis QR payload:

```text
untis://setschool?url={host}&school={school}&user={user}&key={secret}
```

That payload is not stored yet. Do not put one in a settings file, a log, or this repository.

## Install a CI build

Download the `webuntis-msix` artifact from a successful run of `.github/workflows/build.yml`. Trust `WebUntis.cer`, then install `WebUntis.msix`. The full steps are in [docs/install-windows.md](docs/install-windows.md). Developer Mode is not a substitute for trusting the certificate.

The package includes the Windows App Runtime, so a separate runtime install is not required. The widget appears in the Widgets Board only after the MSIX is installed.

## Build

WinUI 3 does not build on Linux. The check is `.github/workflows/build.yml` on `windows-latest`. It generates a self-signed certificate in the runner's certificate store, signs the package, verifies the signature, and uploads the public certificate beside the MSIX. No private key, PFX, or certificate password is written to the repository or the artifact.

```text
src/WebUntis.Core/     portable client library
src/WebUntis.App/      WinUI 3 app and widget COM server
tests/                 core tests
reference/kde-widget/  API reference
```

## License

MIT. See [LICENSE](LICENSE).
