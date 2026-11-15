import QtQuick
import Quickshell
import Quickshell.I3
import qs.Common

// Sway backend, also used for Scroll (a Sway fork with the same IPC; it sets SWAYSOCK and
// I3SOCK too). Windows come from the compositor's own tree, so every window has its exact
// con_id, and a window is moved by that id: no workspace is ever switched to, which matters for
// windows on headless outputs whose workspaces are never shown.
QtObject {
    id: root

    // The IPC client: swaymsg, or scrollmsg on Scroll (whose users may not have Sway).
    property string msg: "swaymsg"

    // The window list or the focused window changed.
    signal updated

    property var windowEvents: I3IpcListener {
        subscriptions: ["window"]
        onIpcEvent: event => root.updated()
    }

    // Leaf windows, depth first, each level in Sway's focus order (a node's `focus` array lists
    // its children most recent first), which gives a rough most-recently-used order to start
    // from. Sway keeps no global focus history.
    function collect(node, out) {
        const kids = (node.nodes || []).concat(node.floating_nodes || []);
        if ((node.type === "con" || node.type === "floating_con") && kids.length === 0) {
            if (node.pid)
                out.push(node);
            return;
        }
        const focus = node.focus || [];
        const rank = n => {
            const i = focus.indexOf(n.id);
            return i < 0 ? focus.length : i;
        };
        kids.sort((a, b) => rank(a) - rank(b));
        for (let i = 0; i < kids.length; i++)
            collect(kids[i], out);
    }

    // done([{ id, title, appId }], focusedId) or done(null) when Sway could not be read.
    function refresh(done) {
        Proc.runCommand("pullWindow.sway.tree", [root.msg, "-t", "get_tree", "-r"], (stdout, exitCode) => {
            if (exitCode !== 0) {
                done(null, "");
                return;
            }
            let tree;
            try {
                tree = JSON.parse(stdout || "");
            } catch (e) {
                done(null, "");
                return;
            }
            const nodes = [];
            collect(tree, nodes);
            let focusedId = "";
            const list = nodes.map(n => {
                const appId = n.app_id || (n.window_properties && n.window_properties.class) || "";
                if (n.focused)
                    focusedId = String(n.id);
                return {
                    id: String(n.id),
                    title: n.name || appId,
                    appId: appId
                };
            });
            done(list, focusedId);
        }, 50, 5000);
    }

    // done(null) on success, done("reason") on failure.
    function pull(id, done) {
        if (!/^[0-9]+$/.test(id)) {
            done("unknown window");
            return;
        }
        const ws = I3.focusedWorkspace;
        if (!ws || !ws.name) {
            done("could not find the focused workspace");
            return;
        }
        const name = ws.name.replace(/\\/g, "\\\\").replace(/"/g, "\\\"");
        const command = "[con_id=" + id + "] move container to workspace \"" + name + "\"; [con_id=" + id + "] focus";
        Proc.runCommand("pullWindow.sway.pull", [root.msg, "-r", command], (stdout, exitCode) => {
            if (exitCode === 124) {
                done("the compositor did not respond");
                return;
            }
            let results;
            try {
                results = JSON.parse(stdout || "");
            } catch (e) {
                done("the compositor refused to move the window");
                return;
            }
            const failed = results.find(r => !r.success);
            done(failed ? "the compositor refused: " + (failed.error || "unknown error") : null);
        }, 0, 5000);
    }
}
