# WebUntis for Windows 11

Windows 11 desktop app and native Widgets Board provider for WebUntis. API behavior is taken from the KDE Plasma applet in `reference/kde-widget`. See [docs/phase-1-analysis.md](docs/phase-1-analysis.md).

## Status

Phase 2 is the packaged skeleton.

What works:

- `WebUntis.Core` is a portable .NET 10 library. It does not call WebUntis yet.
- `WebUntis.App` is a WinUI 3 window that shows the product name and a not-signed-in state.
- The same executable registers `IWidgetProvider` when the widget host starts it with `-RegisterProcessAsComServer`.
- The widget definition `WebUntis_Today` supports small, medium, and large. It currently sends placeholder Adaptive Card text and does not fetch a timetable.
- The Windows build workflow is written at `.github/workflows/build.yml`. It is not on GitHub yet: the v0 GitHub App cannot create workflow files until the Workflows permission is granted.

What remains:

- QR login, timetable and inbox client.
- Week and day views.
- Credential Locker and the shared cache.
- Real widget content, countdown, and the open-app action.
- A signed package. The current MSIX is unsigned.

## Account model

The KDE widget signs in with a WebUntis QR payload:

```text
untis://setschool?url={host}&school={school}&user={user}&key={secret}
```

That payload is not stored yet. Do not put one in a settings file, a log, or this repository.

## Build

WinUI 3 does not build on Linux. The check is `.github/workflows/build.yml` on `windows-latest`.

The package is framework-dependent. Sideloading needs Windows 11, Developer Mode, and the Windows App Runtime that matches Windows App SDK 2.6. The widget appears in the Widgets Board only after the MSIX is installed, because registration is package identity.

```text
src/WebUntis.Core/     portable client library
src/WebUntis.App/      WinUI 3 app and widget COM server
tests/                 core tests
reference/kde-widget/  API reference
```

## License

MIT. See [LICENSE](LICENSE).
