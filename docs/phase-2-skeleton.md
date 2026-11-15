# Phase 2: Windows skeleton

The app and the widget provider are one MSIX so they can later share Credential Locker and `ApplicationData`. A normal launch opens the WinUI window. The widget host launches `WebUntis.App.exe -RegisterProcessAsComServer` and receives the COM class `b6e2c4a1-9d37-4f58-8a16-3c7e5d90f2ab`.

That class implements `Microsoft.Windows.Widgets.Providers.IWidgetProvider` and answers with one Adaptive Card. `IsPlaceholderContent` is true. There is no timetable request in this phase.

The provider keeps widget ids only. It does not keep the `WidgetContext` objects passed into callbacks. The process exits after the last widget is removed, which matches the current Microsoft C# walkthrough and is not the final lifetime policy.

Build settings:

- .NET 10, because .NET 8 left support on 10 November 2026.
- Windows App SDK 2.6.5.
- Minimum OS 10.0.22000.0, because the Widgets Board is Windows 11.
- Signed development MSIX. `.github/workflows/build.yml` creates the certificate during the job. The subject is `CN=artiriart`, matching the package publisher. Only `WebUntis.cer` is exported. `*.pfx` is ignored and is not produced.

Installation is documented in [install-windows.md](install-windows.md).
