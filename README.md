# WebUntis for Windows 11

Windows 11 desktop app and native Widgets Board provider for WebUntis. The behavior is ported from the KDE Plasma applet in `reference/kde-widget`, not rewritten against guessed endpoints.

## Status

Phase 1 is done: the KDE client, login flow, and timetable mapping are documented in [docs/phase-1-analysis.md](docs/phase-1-analysis.md). Application code starts in phase 2.

What works now:

- The reference client and its settings are preserved in `reference/kde-widget`.
- Login, timetable, inbox, caching, and widget-host integration are specified from that code and from the current Windows App SDK widget provider docs.

What remains:

- WinUI 3 app, WebUntis client, Credential Locker storage, native widget, and the GitHub Actions MSIX build.

## Account model

The KDE widget signs in with a WebUntis QR payload:

```text
untis://setschool?url={host}&school={school}&user={user}&key={secret}
```

The Windows app will store that payload in Windows Credential Locker. Do not put it in a settings file, a log, or this repository.

## Build

WinUI 3 needs a Windows runner. This repository will build on `windows-latest` once phase 2 adds the solution. An unsigned MSIX can be sideloaded on Windows 11 with Developer Mode. Widget registration is package identity, so the widget and the app ship in one MSIX.

## Layout

```text
reference/kde-widget/   KDE Plasma source used as the API reference
docs/                   Phase notes and architecture
```

## License

MIT. See [LICENSE](LICENSE).
