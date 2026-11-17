import QtQuick
import qs.Common
import qs.Services

// niri backend. Windows come from DMS's NiriService with niri's own window ids, and a window is
// moved by id onto the focused workspace without switching any view, so it also works for windows
// on headless outputs.
QtObject {
    id: root

    // The window list or the focused window changed.
    signal updated

    // NiriService already keeps the window list up to date from DMS's own event stream, so we
    // just follow it rather than running a second stream and a `niri msg` on every event
    property var niriEvents: Connections {
        target: NiriService

        function onWindowsChanged() {
            root.updated();
        }
    }

    function parse(stdout) {
        try {
            return JSON.parse(stdout || "");
        } catch (e) {
            return null;
        }
    }

    function stamp(w) {
        const t = w.focus_timestamp;
        return t ? t.secs * 1e9 + t.nanos : -1;
    }

    // done([{ id, title, appId }], focusedId). Ordered by niri's own focus timestamps, so the
    // most-recently-used order is right from the first refresh. NiriService doesn't update the
    // timestamps after that, but the core tracks focus changes itself from then on.
    function refresh(done) {
        const windows = (NiriService.windows || []).slice();
        windows.sort((a, b) => stamp(b) - stamp(a));
        let focusedId = "";
        const list = windows.map(w => {
            if (w.is_focused)
                focusedId = String(w.id);
            return {
                id: String(w.id),
                title: w.title || w.app_id || "",
                appId: w.app_id || ""
            };
        });
        done(list, focusedId);
    }

    function action(args, next) {
        Proc.runCommand("pullWindow.niri.action", ["niri", "msg", "action"].concat(args), (stdout, exitCode) => next(exitCode), 0, 5000);
    }

    // done(null) on success, done("reason") on failure. The target is the focused workspace.
    // niri exits 0 even for an unknown window, so the window is read back to confirm.
    function pull(id, done) {
        if (!/^[0-9]+$/.test(id)) {
            done("unknown window");
            return;
        }
        const workspaces = NiriService.allWorkspaces || [];
        const target = workspaces.find(ws => ws.is_focused);
        const win = (NiriService.windows || []).find(w => String(w.id) === id);
        if (!target) {
            done("could not find the focused workspace");
            return;
        }
        if (!win) {
            done("the window is gone");
            return;
        }
        const from = workspaces.find(ws => ws.id === win.workspace_id);
        // A workspace index refers to the window's own monitor, so a window on another
        // monitor goes with move-window-to-monitor, which puts it on that monitor's active
        // workspace: the focused one.
        const move = from && from.output === target.output ? ["move-window-to-workspace", "--window-id", id, "--focus", "false", String(target.idx)] : ["move-window-to-monitor", "--id", id, target.output];
        action(move, moveCode => {
            if (moveCode !== 0) {
                done(moveCode === 124 ? "niri did not respond" : "niri refused to move the window");
                return;
            }
            action(["focus-window", "--id", id], focusCode => {
                // Asks niri directly here. It only runs when a window is picked, and the
                // read-back has to see the move straight away, which NiriService only does once
                // niri's event arrives.
                Proc.runCommand("pullWindow.niri.verify", ["niri", "msg", "-j", "windows"], (after, afterCode) => {
                    const list = afterCode === 0 ? parse(after) : null;
                    const moved = Array.isArray(list) ? list.find(w => String(w.id) === id) : null;
                    if (!moved || moved.workspace_id !== target.id)
                        done("niri did not move the window");
                    else
                        done(focusCode === 0 ? null : "moved the window but could not focus it");
                }, 0, 5000);
            });
        });
    }
}
