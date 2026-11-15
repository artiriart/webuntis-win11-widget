import QtQuick 2.0
import QtQuick.Controls 2.5 as Controls
import QtQuick.Layouts 1.0
import org.kde.kirigami 2.4 as Kirigami

Kirigami.FormLayout {
    property alias cfg_qrPayload: qrPayload.text
    property alias cfg_refreshEnabled: refreshEnabled.checked

    Controls.Label {
        Kirigami.FormData.label: i18n("QR login payload")
        text: i18n("Paste the complete untis://setschool?... value from WebUntis.")
        wrapMode: Text.Wrap
        Layout.maximumWidth: Kirigami.Units.gridUnit * 28
    }
    Controls.TextArea {
        id: qrPayload
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 6
        placeholderText: "untis://setschool?url=...&school=...&user=...&key=..."
        Accessible.name: i18n("WebUntis QR payload")
        wrapMode: TextEdit.WrapAnywhere
    }
    Controls.CheckBox {
        id: refreshEnabled
        Kirigami.FormData.label: i18n("Updates")
        text: i18n("Refresh automatically every 15 minutes")
        enabled: true
    }
    Controls.Label {
        Kirigami.FormData.label: i18n("Privacy")
        text: i18n("The QR payload stays in this plasmoid configuration. Requests are sent directly to your WebUntis host.")
        wrapMode: Text.Wrap
        color: Kirigami.Theme.disabledTextColor
        Layout.maximumWidth: Kirigami.Units.gridUnit * 28
    }
}
