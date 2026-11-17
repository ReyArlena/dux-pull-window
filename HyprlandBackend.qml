import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common

// Hyprland backend. Windows come from Quickshell's Hyprland.toplevels, identified by address, in
// Hyprland's own focus history order; a window is moved by address with the Lua dispatchers (0.55+).
QtObject {
    id: root

    // Hyprland events that change the window list or which window is focused.
    readonly property var watchedEvents: ["openwindow", "closewindow", "windowtitle", "windowtitlev2", "activewindow", "activewindowv2", "minimized"]

    // The list below is already in Hyprland's focus history order, so the core uses it as is
    // rather than tracking focus itself.
    readonly property bool ownHistory: true

    // The window list or the focused window changed.
    signal updated

    property var hyprlandEvents: Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (root.watchedEvents.indexOf(event.name) >= 0)
                settle.restart();
        }
    }

    // DMS refreshes the window data (focus history, mapped, hidden) on these events, so we wait a
    // moment for that to land. It also means a title that keeps changing only refreshes once.
    property var settle: Timer {
        interval: 200
        onTriggered: root.updated()
    }

    // done([{ id, title, appId }], focusedId). Reads what Quickshell already has, so nothing is
    // run in the background. A window opened a moment ago may not have its IPC data yet, so it
    // counts as mapped and goes last until the next refresh.
    function refresh(done) {
        const visible = [];
        const toplevels = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        for (let i = 0; i < toplevels.length; i++) {
            const t = toplevels[i];
            const ipc = t.lastIpcObject || {};
            if (!t.address || ipc.mapped === false || ipc.hidden)
                continue;
            visible.push({
                id: "0x" + t.address,
                title: t.title || ipc.title || ipc.initialTitle || "",
                appId: ipc.class || ipc.initialClass || (t.wayland ? t.wayland.appId : "") || "",
                history: typeof ipc.focusHistoryID === "number" ? ipc.focusHistoryID : 9999
            });
        }
        visible.sort((a, b) => a.history - b.history);
        const focused = visible.find(w => w.history === 0);
        done(visible.map(w => ({
                    id: w.id,
                    title: w.title || w.appId,
                    appId: w.appId
                })), focused ? focused.id : "");
    }

    // The active workspace of the focused monitor, or its special workspace (scratchpad) when
    // one is open there, as a Lua workspace selector; "" when it cannot be found. DMS refreshes
    // the monitor data on workspace and special workspace changes.
    function targetWorkspace() {
        const mon = Hyprland.focusedMonitor;
        const ipc = mon ? mon.lastIpcObject || {} : {};
        const special = ipc.specialWorkspace && ipc.specialWorkspace.name;
        const active = ipc.activeWorkspace ? ipc.activeWorkspace.id : (mon && mon.activeWorkspace ? mon.activeWorkspace.id : null);
        const ws = special ? special : (active !== null && active !== undefined ? String(active) : "");
        // It goes inside a Lua string.
        return /["\\\n]/.test(ws) ? "" : ws;
    }

    // done(null) on success, done("reason") on failure.
    function pull(id, done) {
        if (!/^0x[0-9a-f]+$/i.test(id)) {
            done("unknown window");
            return;
        }
        const ws = targetWorkspace();
        if (!ws) {
            done("could not find the focused workspace");
            return;
        }
        // hyprctl dispatch replies "ok" or an error, so it's run directly rather than through
        // Hyprland.dispatch(), which gives no reply. It only runs when a window is picked.
        const script = '[ "$(hyprctl dispatch "hl.dsp.window.move({ workspace = \\"$2\\", follow = false, window = \\"address:$1\\" })")" = ok ] || exit 2\n'
            + '[ "$(hyprctl dispatch "hl.dsp.focus({ window = \\"address:$1\\" })")" = ok ] || exit 3';
        Proc.runCommand("pullWindow.hyprland.pull", ["sh", "-c", script, "_", id, ws], (out, code) => {
            const errors = {
                2: "Hyprland refused to move the window",
                3: "moved the window but could not focus it",
                124: "Hyprland did not respond"
            };
            done(code === 0 ? null : (errors[code] || "failed (exit " + code + ")"));
        }, 0, 5000);
    }
}
