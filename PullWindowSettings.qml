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
}
