import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import "../code/untis.js" as Untis

PlasmoidItem {
    id: root
    implicitWidth: compact ? 280 : 620
    implicitHeight: compact ? 86 : 620
    preferredRepresentation: compactRepresentation
    switchWidth: 420
    switchHeight: 180

    property bool compact: width < switchWidth || height < switchHeight
    property bool loading: false
    property string statusText: "QR-Code in den Einstellungen hinterlegen"
    property string errorText: ""
    property string cooldownText: ""
    property var lessons: []
    property var cancellations: []
    property var inbox: []
    property var account: ({ qrPayload: "", url: "", school: "" })

    function refresh(force) {
        if (loading)
            return
        var payload = String(plasmoid.configuration.qrPayload || "").trim()
        if (!payload) {
            statusText = "QR-Code in den Einstellungen hinterlegen"
            return
        }
        if (!force && Untis.cooldownMinutes() > 0) {
            cooldownText = "Aktualisierung in " + Untis.cooldownMinutes() + " Min."
            return
        }
        loading = true
        errorText = ""
        cooldownText = ""
        statusText = "Anmeldung läuft …"
        try {
            account.qrPayload = payload
            var qr = Untis.parseQr(account.qrPayload)
            account.url = qr.url
            account.school = qr.school
            account.username = qr.user
            Untis.login(account, function() {
                statusText = "Daten werden geladen …"
                Untis.getData(account, function(data) {
                    lessons = Untis.timetableEntries(data.week).map(Untis.mapLesson)
                    inbox = Untis.mapInbox(data.inbox || {})
                    cancellations = lessons.filter(function(item) { return item.cancelled })
                    statusText = "Zuletzt aktualisiert: " + Qt.formatTime(new Date(), "HH:mm")
                    errorText = ""
                    cooldownText = ""
                    loading = false
                    }, fail, force)
            }, fail)
        } catch (error) {
            fail(error.message || String(error))
        }
    }

    function fail(message) {
        loading = false
        var text = String(message || "Unbekannter Fehler")
        if (text.indexOf("cooldown:") === 0) {
            cooldownText = "Aktualisierung in " + text.substring(9) + " Min."
            return
        }
        errorText = text
        statusText = "Keine aktuellen Daten"
    }

    function dateKey(date) {
        return Qt.formatDate(date, "yyyyMMdd")
    }

    function displayDate() {
        var now = new Date()
        var today = dateKey(now)
        var remainingToday = lessons.some(function(item) {
            if (item.date !== today || item.cancelled) return false
            var parts = item.endTime.split(":")
            return new Date(now.getFullYear(), now.getMonth(), now.getDate(), Number(parts[0]), Number(parts[1])) > now
        })
        if (remainingToday) return today
        var upcoming = lessons.filter(function(item) {
            return item.date > today && !item.cancelled
        }).sort(function(a, b) { return a.date.localeCompare(b.date) })
        return upcoming.length ? upcoming[0].date : dateKey(new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1))
    }

    function displayDayLabel() {
        var today = dateKey(new Date())
        var target = displayDate()
        if (target === today) return "Heute"
        var targetDate = new Date(Number(target.substring(0, 4)), Number(target.substring(4, 6)) - 1, Number(target.substring(6, 8)))
        var days = Math.round((targetDate - new Date(new Date().getFullYear(), new Date().getMonth(), new Date().getDate())) / 86400000)
        if (days === 1) return "Morgen"
        return "In " + days + " Tagen"
    }

    function todayLessons() {
        var target = displayDate()
        return lessons.filter(function(item) { return item.date === target }).sort(function(a, b) { return a.startTime.localeCompare(b.startTime) })
    }

    function nextDate() {
        var current = displayDate()
        var dates = lessons.filter(function(item) { return item.date > current }).map(function(item) { return item.date })
        dates.sort()
        return dates.length ? dates[0] : ""
    }

    function nextDayLessons() {
        var target = nextDate()
        return lessons.filter(function(item) { return target && item.date === target }).sort(function(a, b) { return a.startTime.localeCompare(b.startTime) })
    }

    function nextDayLabel() {
        var target = nextDate()
        if (!target) return "Nächster Tag"
        var date = new Date(Number(target.substring(0, 4)), Number(target.substring(4, 6)) - 1, Number(target.substring(6, 8)))
        var today = new Date()
        var base = new Date(today.getFullYear(), today.getMonth(), today.getDate())
        var days = Math.round((date - base) / 86400000)
        return days === 1 ? "Morgen" : "In " + days + " Tagen"
    }

    function nextLesson() {
        var now = new Date()
        var currentDate = dateKey(now)
        var current = lessons.filter(function(item) {
            if (item.cancelled) return false
            if (item.date > currentDate) return true
            if (item.date < currentDate) return false
            var parts = item.startTime.split(":")
            return new Date(now.getFullYear(), now.getMonth(), now.getDate(), Number(parts[0]), Number(parts[1])) > now
        }).sort(function(a, b) { return a.date.localeCompare(b.date) || a.startTime.localeCompare(b.startTime) })
        return current.length ? current[0] : null
    }

    Timer {
        interval: 1000
        repeat: false
        running: true
        onTriggered: root.refresh(false)
    }

    Timer {
        interval: 60000
        repeat: true
        running: plasmoid.configuration.refreshEnabled
        onTriggered: root.refresh(false)
    }

    compactRepresentation: Item {
        implicitWidth: 280
        implicitHeight: 86
        Layout.minimumWidth: 220
        Layout.minimumHeight: 72
        MouseArea { anchors.fill: parent; onClicked: root.expanded = !root.expanded }
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                Controls.Label {
                    Layout.fillWidth: true
                    text: root.nextLesson() ? root.nextLesson().startTime + " – " + root.nextLesson().subject : "Kein weiterer Unterricht"
                    font.bold: true
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.2
                    elide: Text.ElideRight
                }
                Controls.Label {
                    text: root.nextLesson() ? "Ende " + root.nextLesson().endTime : ""
                    color: Kirigami.Theme.disabledTextColor
                }
            }
            Controls.Label {
                visible: root.errorText.length > 0
                text: root.errorText
                color: Kirigami.Theme.negativeTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    fullRepresentation: Item {
        implicitWidth: 620
        implicitHeight: 620
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing
            RowLayout {
                Layout.fillWidth: true
                Controls.Label {
                    text: "Untis"
                    font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.4
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Controls.Button {
                    text: loading ? "Lädt …" : "Aktualisieren"
                    enabled: !loading
                    onClicked: root.refresh(true)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Controls.Label {
                    visible: root.errorText.length > 0
                    text: root.errorText
                    color: Kirigami.Theme.negativeTextColor
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
                Controls.Label {
                    text: root.cooldownText || root.statusText
                    color: Kirigami.Theme.disabledTextColor
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.largeSpacing
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Controls.Label { text: root.displayDayLabel(); font.bold: true }
                    Controls.ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            width: parent.width
                            spacing: 1
                            Repeater {
                                model: root.todayLessons()
                                delegate: RowLayout {
                                    Layout.fillWidth: true
                                    Controls.Label { text: modelData.completed ? "✓" : ""; Layout.preferredWidth: 18; color: Kirigami.Theme.positiveTextColor }
                                    Controls.Label { text: modelData.startTime; Layout.preferredWidth: 48 }
                                    Controls.Label { text: modelData.subject + (modelData.cancelled ? " · entfällt" : ""); Layout.fillWidth: true; elide: Text.ElideRight; color: modelData.cancelled ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor }
                                }
                            }
                            Controls.Label { visible: root.todayLessons().length === 0; text: "Keine Stunden für " + root.displayDayLabel().toLowerCase() + "."; color: Kirigami.Theme.disabledTextColor }
                        }
                    }
                }
                ColumnLayout {
                    Layout.preferredWidth: 220
                    Layout.fillHeight: true
                    Controls.Label { text: root.nextDayLabel(); font.bold: true }
                    Controls.ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        ColumnLayout {
                            width: parent.width
                            Repeater {
                                model: root.nextDayLessons()
                                delegate: Controls.Label {
                                    Layout.fillWidth: true
                                    text: modelData.startTime + "  " + modelData.subject
                                    wrapMode: Text.Wrap
                                    color: modelData.cancelled ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                }
                            }
                            Controls.Label { visible: root.nextDayLessons().length === 0; text: "Keine Stunden."; color: Kirigami.Theme.disabledTextColor }
                        }
                    }
                }
            }
            Controls.Label { text: "Inbox"; font.bold: true }
            Controls.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                ColumnLayout {
                    width: parent.width
                    spacing: Kirigami.Units.largeSpacing
                    Repeater {
                        model: root.inbox
                        delegate: ColumnLayout {
                            Layout.fillWidth: true
                            Controls.Label { text: modelData.teacher + "  " + modelData.subject; font.bold: true; Layout.fillWidth: true }
                            Controls.Label { text: modelData.text; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            Controls.Label { visible: modelData.attachment || modelData.url; text: modelData.attachment ? "Anhang verfügbar" : modelData.url; color: Kirigami.Theme.linkColor; elide: Text.ElideMiddle; Layout.fillWidth: true }
                            Controls.Label { text: modelData.sentAt; color: Kirigami.Theme.disabledTextColor; font.pixelSize: Kirigami.Theme.smallFont.pixelSize }
                        }
                    }
                    Controls.Label { visible: root.inbox.length === 0; text: "Keine Nachrichten im Posteingang."; color: Kirigami.Theme.disabledTextColor }
                }
            }
        }
    }
}
