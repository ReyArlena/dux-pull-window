import QtQuick
import Quickshell.Io
import qs.Services

// Daemon component: IPC for a compositor keybind. DMS registers plugin IPC handlers from the
// daemon (instantiated once), not from the launcher component. It's a QtObject rather than an
// Item since it draws nothing; an Item logs "Created graphical object was not placed in the
// graphics scene" on every load.
//   dms ipc call pullWindow toggle   opens the launcher in Pull Window mode, or closes it
//   dms ipc call pullWindow open     opens it (no toggle)
QtObject {
    id: root

    property var pluginService: null
    property string pluginId: "pullWindow"

    // The user's trigger, read at call time so a changed trigger needs no reload.
    function query() {
        const saved = pluginService ? pluginService.loadPluginData(pluginId, "trigger", ":pw") : ":pw";
        return ((saved || "").trim() || ":pw") + " ";
    }

    property var ipc: IpcHandler {
        target: "pullWindow"

        function open(): string {
            PopoutService.openDankLauncherV2WithQuery(root.query());
            return "PULL_WINDOW_OPEN_SUCCESS";
        }

        function toggle(): string {
            PopoutService.toggleDankLauncherV2WithQuery(root.query());
            return "PULL_WINDOW_TOGGLE_SUCCESS";
        }
    }
}
