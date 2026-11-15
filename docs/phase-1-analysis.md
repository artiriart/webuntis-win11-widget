# Phase 1: KDE source analysis and Windows architecture

Status: analysis only. No application code yet.

The supplied package is a KDE Plasma 6 applet (`org.kde.plasma.untis`, "Untis Dash"), not a full desktop client. Its behavior is the source of truth for WebUntis calls. The Windows app will reuse that flow and add the desktop timetable and native widget the brief asks for.

## What the KDE widget actually does

Settings (`contents/config/main.xml`, `contents/ui/configGeneral.qml`):

- `qrPayload`: the full `untis://setschool?...` string.
- `refreshEnabled`: automatic refresh, default true.
- There is no separate school, username, or password field. The QR string is the account.

Compact view (`contents/ui/main.qml`):

- Next non-cancelled lesson: start time, subject, end time.
- Error text when login or fetch fails.

Expanded view:

- Manual refresh.
- Status or cooldown line.
- Primary day: today if a non-cancelled lesson is still running or upcoming, otherwise the next day that has lessons, otherwise tomorrow.
- Secondary column: the day after that primary day.
- Inbox: up to five messages.

Refresh rules:

- First load after one second.
- A one-minute timer calls refresh only when `refreshEnabled` is true.
- `getData` refuses another network fetch for 15 minutes unless refresh is forced.
- Forced refresh still logs in again, then fetches.

## Authentication, copied from `contents/code/untis.js`

QR URI, case-insensitive scheme:

```text
untis://setschool?url={host}&school={school}&user={user}&key={base32-secret}
```

`url`, `school`, `user`, and `key` are required. Values are URL-decoded, with `+` treated as a space.

Login request:

- `POST https://{host}/WebUntis/jsonrpc_intern.do?m=getUserData2017&school={school}&v=i2.2`
- JSON-RPC 2.0 method `getUserData2017`
- Params: `[{ auth: { clientTime: <unix-ms>, user, otp } }]`
- `otp` is TOTP: Base32 secret, HMAC-SHA1, 30-second step, 6 digits.
- Timeout: 20 seconds.

The browser keeps the session with `withCredentials`. The Windows client must store the `Set-Cookie` value from this response (typically `JSESSIONID`) and send it on later calls. The cookie is memory-only.

Person identity is not a fixed field. The client walks the login result for the first `elemId` (type from `elemType` or `elementType`). If that is missing, it falls back to `personId` or `userPersonId`. Type strings map to WebUntis element types: student 5, class 1, teacher 2. Anything else defaults to student (5). Login fails if no id is found.

The widget does not call the public `authenticate` password method. Password login is a documented JSON-RPC method on `jsonrpc.do`, but it is not what this widget uses. Phase 3 will implement QR login first. A password form will be added only as a second path through that documented `authenticate` method, because the brief asks for username and password and because some schools do not issue a QR secret.

## Timetable

- `POST https://{host}/WebUntis/jsonrpc.do?school={school}`
- Method: `getTimetable` (not `getTimetable2017`).
- Params are wrapped in `options`:
  - `element`: `{ id, type }` from the login person.
  - `startDate` / `endDate`: integers `YYYYMMDD`.
  - Initial range: today through six days later.
  - Flags already requested: `showLsText`, `showStudentgroup`, `showLsNumber`, `showSubstText`, `showInfo`, `showBooking`.
  - Field lists for room, teacher, subject, and class: `id`, `name`, `longname`, `externalkey`.
- If the error text contains "school year", "single school year", or "Schuljahr", retry once for the next Monday-Sunday. Do not invent other retries.

Lesson fields used by the widget:

| Widget field | Source fields |
| --- | --- |
| Date | `date` or `dat`, digits only |
| Start / end | `startTime` or `start`, `endTime`, as `HHMM` integers |
| Subject | `subjects[0]` or `su[0]`, `name` then `longName` / `longname` |
| Teacher | `teachers[0]` or `te[0]` |
| Info | `lessonText`, `lstext`, `substText`, `info` |
| Cancelled | `code` cancelled/cancel, `cellState` CANCELLED/CANCEL, or `isCancelled` |

Subject display is a local map (`b` Bio, `M` Mathe, `ph` Physik, `sp` Sport, `WI` Wirtschaft, `E` Englisch, `inf` Informatik, `mu` Musik, `d` Deutsch, `g` Geschichte, `eth` Ethik, `geo` Erdkunde). Digits are stripped before lookup. A leading capital marks a Leistungskurs (`(LK)`). Unknown ids stay as the stripped id. This map is presentation only and will remain configurable later rather than being treated as API data.

Room is requested (`roomFields`) but not shown. The Windows UI will read `rooms` or `ro` with the same name/longname fallback. That is display of a field the existing request already asks for, not a new endpoint.

Substitution is not a separate flag in the widget. `substText` is folded into `info`. The Windows UI will show a substitution when `substText` is present, and will keep the existing cancellation test unchanged.

## Inbox

Used only when timetable fetch succeeds.

1. If login returned `jwt_token`, `GET /WebUntis/api/rest/view/v1/messages` with `Authorization: Bearer`.
2. Otherwise `GET /WebUntis/api/token/new`, accept `jwt_token`, `jwtToken`, `token`, or `access_token`, then call messages.
3. Read `incomingMessages` or `messages`. Sort by `sentDateTime`, `date`, or `createdAt`. Keep five.
4. Sender display name, subject/title, content/text/preview, attachment flag, unread (`isMessageRead === false`), reply flag, and url/link.

Inbox failure fails the whole refresh in the current widget. The Windows client will keep the last good timetable if inbox fails, and surface the inbox error separately. Timetable is the primary feature.

## Security constraints taken from the source

- The QR `key` is a TOTP secret. It must never be written to logs, settings files, or git.
- Session cookies and JWTs stay in memory.
- Requests go only to the host embedded in the QR URI. No proxy.
- The 15-minute cooldown stays, including for the widget, unless the user forces a refresh.

## Proposed Windows architecture

```text
WebUntis.sln
  src/WebUntis.Core          net8.0 class library
  src/WebUntis.App           WinUI 3 / Windows App SDK, net8.0-windows
  src/WebUntis.Widget        same package, COM local server for IWidgetProvider
  tests/WebUntis.Core.Tests  timetable mapping, QR parsing, TOTP, cooldown
```

`WebUntis.Core` has no WinUI dependency, so its tests can run on the Linux workspace and on `windows-latest`. Windows-only projects compile in GitHub Actions. This sandbox cannot build WinUI 3.

### Core

- `QrAccountParser`: the URI rules above, nothing else.
- `Totp`: 30-second HMAC-SHA1, implemented with `System.Security.Cryptography`, not a third-party port of the JS SHA-1.
- `WebUntisClient`: one `HttpClient`, cookie container, 20-second timeout, the two endpoints above, plus inbox token/messages.
- `TimetableService`: week range, school-year retry, lesson mapping, day selection (`Heute` / `Morgen` / `In N Tagen`), next lesson, countdown.
- `TimetableCache`: last successful payload plus fetch time. Serves stale data during cooldown and after a failed refresh.
- `AccountStore` interface. The WinUI app implements it with PasswordVault. Tests use an in-memory store.

### Desktop app

WinUI 3, Fluent, packaged as MSIX so it shares identity with the widget.

- Login page: paste QR payload. Optional password login is phase 3b, behind the documented `authenticate` method, and is not required for the first working build.
- Week page: the home screen. Seven columns, lessons in time order, cancellation styling, substitution note, room and teacher.
- Day page: the KDE primary-day list plus the next day.
- Inbox page: the five-message list.
- Settings: refresh on/off, cooldown display, sign out (deletes the vault entry and memory session).
- Manual refresh bypasses the cooldown. Automatic refresh does not.

### Widget

Official model, checked against Microsoft Learn (`Implement a widget provider in a win32 app`, Windows App SDK 1.6+ / current stable):

- The provider is an out-of-process COM server implementing `Microsoft.Windows.Widgets.Providers.IWidgetProvider`.
- Package manifest registers `windows.appExtension` category `com.microsoft.windows.widgets` and a `com:Extension` class id.
- The host calls `CreateWidget`, `DeleteWidget`, `Activate`, `Deactivate`, `OnActionInvoked`, and `OnWidgetContextChanged`.
- Updates go through `WidgetManager.GetDefault().UpdateWidget` with Adaptive Card JSON. Template objects passed into callbacks are not stored.
- `Activate` refreshes if the cache is older than 15 minutes. `Deactivate` stops the countdown timer. Pushing updates while inactive is avoided.
- Sizes: small = next lesson and countdown; medium = current or next plus remaining count; large = remaining lessons, room, teacher, cancellations.
- An Adaptive Card action opens the desktop app. No second login.

App and widget share data because they are the same MSIX identity: PasswordVault and `ApplicationData` are per package and per Windows user. A local JSON cache holds timetable data only. The QR secret never goes in that file.

### CI

`.github/workflows/build.yml` on `windows-latest`, for pushes and pull requests:

1. `dotnet restore`
2. `dotnet test` for Core
3. `dotnet build -c Release` for the WinUI app and widget provider
4. Unsigned MSIX via the Windows App SDK packaging targets
5. Upload the MSIX and build logs as artifacts

No certificate, password, or QR payload in the repo or in Actions secrets. Sideloading the unsigned package needs Developer Mode.

## Phase plan

| Phase | Deliverable | Compile check |
| --- | --- | --- |
| 1 | This analysis | None, no app code |
| 2 | Solution skeleton, WinUI window, widget COM stub, workflow that restores and builds | `windows-latest` |
| 3 | QR login, TOTP, cookie session, timetable and inbox client, Core tests | Core tests here; full build in Actions |
| 4 | Week view, day view, settings shell | Actions |
| 5 | PasswordVault account store, shared cache, re-login on HTTP 401 / JSON-RPC auth error | Actions |
| 6 | `IWidgetProvider`, Adaptive Cards, small/medium/large | Actions, widget board needs a Windows 11 device |
| 7 | Same cache for app and widget, open-app action, single sign-in | Actions |
| 8 | MSIX artifact, README install notes | Actions |

## Decisions made from the source

- QR login is the primary account model. The brief's username/password screen is secondary and will not replace the QR flow.
- `getTimetable` and `getUserData2017` stay as implemented. `getTimetable2017` is not used.
- Room is shown from fields the existing request already returns.
- Inbox failure does not wipe a good timetable.
- German strings from the widget stay as the default UI language. English can follow once the flows work.
