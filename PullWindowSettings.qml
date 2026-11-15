import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Services

PluginSettings {
    id: root
    pluginId: "pullWindow"

    StyledText {
        width: parent.width
        text: "Pull Window"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Search open windows from the launcher and pull the chosen one onto the workspace you are on. Type the trigger, then part of a window title or app name."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // Trigger with an explicit Save button, so it is clear when the value is stored.
    Column {
        id: triggerSetting
        width: parent.width
        spacing: Theme.spacingS

        readonly property string defaultTrigger: ":pw"
        property string saved: defaultTrigger
        readonly property string pending: (triggerField.text || "").trim() || defaultTrigger
        readonly property bool dirty: pending !== saved

        function load() {
            if (!root.pluginService)
                return;
            saved = (root.loadValue("trigger", defaultTrigger) || "").trim() || defaultTrigger;
            triggerField.text = saved;
        }

        function save() {
            if (!dirty)
                return;
            root.saveValue("trigger", pending);
            saved = pending;
            triggerField.text = pending;
            ToastService.showInfo("Pull Window trigger saved: " + pending);
        }

        StyledText {
            text: "Trigger"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Theme.fontWeightMedium
            color: Theme.surfaceText
        }

        StyledText {
            width: parent.width
            text: "Launcher prefix for this plugin. Avoid prefixes used by DMS or other plugins (e.g. :e, :ow, /). Left empty, :pw is used. Press Save or Enter to apply."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DTextField {
                id: triggerField
                width: parent.width - saveButton.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: triggerSetting.defaultTrigger
                onAccepted: triggerSetting.save()
            }

            DButton {
                id: saveButton
                anchors.verticalCenter: parent.verticalCenter
                text: triggerSetting.dirty ? "Save" : "Saved"
                reserveText: "Saved"
                iconName: triggerSetting.dirty ? "save" : "check"
                enabled: triggerSetting.dirty
                onClicked: triggerSetting.save()
            }
        }
    }

    onPluginServiceChanged: triggerSetting.load()
    Component.onCompleted: Qt.callLater(triggerSetting.load)

    ToggleSetting {
        settingKey: "hideCurrentWorkspace"
        label: "Hide windows on this workspace"
        description: "Leave out windows already on the workspace you are on, since there is nothing to pull. Off, they are listed too and choosing one focuses it."
        defaultValue: false
    }

    StyledRect {
        width: parent.width
        height: referenceColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surface

        Column {
            id: referenceColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            Row {
                spacing: Theme.spacingM

                DIcon {
                    name: "code"
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: "Reference"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            StyledText {
                text: "View this project on <a href=\"https://github.com/ReyArlena/dux-pull-window\" style=\"color: " + Theme.primary + ";\">GitHub</a> for documentation, or <a href=\"https://github.com/ReyArlena/dux-pull-window/issues\" style=\"color: " + Theme.primary + ";\">open an issue</a> to report a bug or suggest a feature."
                textFormat: Text.RichText
                linkColor: Theme.primary
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
                width: parent.width
                lineHeight: 1.4
                onLinkActivated: link => Qt.openUrlExternally(link)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: parent.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }
        }
    }
}
