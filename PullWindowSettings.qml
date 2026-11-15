import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

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

    StringSetting {
        settingKey: "trigger"
        label: "Trigger"
        description: "Launcher prefix for this plugin. Avoid prefixes used by DMS or other plugins (e.g. :e, :ow, /). Left empty, :pw is used."
        placeholder: ":pw"
        defaultValue: ":pw"
    }

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
