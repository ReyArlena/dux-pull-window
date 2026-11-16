import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common

// Hyprland backend. Windows come from `hyprctl clients`, identified by address, in Hyprland's
// own focus history order; a window is moved by address with the Lua dispatchers (0.55+).
QtObject {
    id: root

    // Hyprland events that change the window list or which window is focused.
    readonly property var watchedEvents: ["openwindow", "closewindow", "windowtitle", "windowtitlev2", "activewindow", "activewindowv2", "minimized"]

    // The window list or the focused window changed.
    signal updated

    property var hyprlandEvents: Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (root.watchedEvents.indexOf(event.name) >= 0)
                root.updated();
        }
    }

    // done([{ id, title, appId }], focusedId) or done(null) when Hyprland could not be read.
    function refresh(done) {
        Proc.runCommand("pullWindow.hyprland.clients", ["hyprctl", "clients", "-j"], (stdout, exitCode) => {
            if (exitCode !== 0) {
                done(null, "");
                return;
            }
            let clients;
            try {
                clients = JSON.parse(stdout || "[]");
            } catch (e) {
                done(null, "");
                return;
            }
            const history = c => typeof c.focusHistoryID === "number" ? c.focusHistoryID : 9999;
            const visible = clients.filter(c => c.mapped && !c.hidden && c.address).sort((a, b) => history(a) - history(b));
            const focused = visible.find(c => c.focusHistoryID === 0);
            done(visible.map(c => ({
                        id: c.address,
                        title: c.title || c.initialTitle || c.class || "",
                        appId: c.class || c.initialClass || ""
                    })), focused ? focused.address : "");
        }, 50, 5000);
    }

    // The active workspace of the focused monitor, or its special workspace (scratchpad) when
    // one is open there, as a Lua workspace selector; "" when it cannot be found.
    function targetWorkspace(stdout) {
        let monitors;
        try {
            monitors = JSON.parse(stdout || "");
        } catch (e) {
            return "";
        }
        const mon = Array.isArray(monitors) ? monitors.find(m => m.focused) : null;
        if (!mon)
            return "";
        const special = mon.specialWorkspace && mon.specialWorkspace.name;
        const ws = special ? special : (mon.activeWorkspace ? String(mon.activeWorkspace.id) : "");
        // It goes inside a Lua string.
        return /["\\\n]/.test(ws) ? "" : ws;
    }

    // done(null) on success, done("reason") on failure.
    function pull(id, done) {
        if (!/^0x[0-9a-f]+$/i.test(id)) {
            done("unknown window");
            return;
        }
        Proc.runCommand("pullWindow.hyprland.monitors", ["hyprctl", "monitors", "-j"], (stdout, exitCode) => {
            const ws = exitCode === 0 ? targetWorkspace(stdout) : "";
            if (!ws) {
                done(exitCode === 124 ? "Hyprland did not respond" : "could not find the focused workspace");
                return;
            }
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
        }, 0, 5000);
    }
}
