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

    // [{ id, title, appId }] and the focused window, kept up to date from the window events below.
    property var windows: []
    property string focusedId: ""
    property bool loaded: false

    // Each window event carries the window itself, so we update the list from that rather than
    // reading the whole tree with get_tree on every event.
    property var windowEvents: I3IpcListener {
        subscriptions: ["window"]
        onIpcEvent: event => root.apply(event.data)
    }

    function entry(node) {
        const appId = node.app_id || (node.window_properties && node.window_properties.class) || "";
        return {
            id: String(node.id),
            title: node.name || appId,
            appId: appId
        };
    }

    // Other changes (move, floating, fullscreen, urgent, mark) leave the list as it is.
    function apply(data) {
        let event;
        try {
            event = JSON.parse(data || "");
        } catch (e) {
            return;
        }
        const node = event.container;
        if (!root.loaded || !node || node.id === undefined)
            return;
        const id = String(node.id);
        const known = windows.some(w => w.id === id);
        if (event.change === "close") {
            windows = windows.filter(w => w.id !== id);
            if (focusedId === id)
                focusedId = "";
        } else if (event.change === "new" || event.change === "title" || event.change === "focus") {
            windows = known ? windows.map(w => w.id === id ? entry(node) : w) : windows.concat([entry(node)]);
            if (event.change === "focus")
                focusedId = id;
        } else {
            return;
        }
        root.updated();
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

    // done([{ id, title, appId }], focusedId) or done(null) when Sway could not be read. Answers
    // from the event-fed list, and only reads the tree with get_tree the first time and when the
    // launcher asks (full), in case an event was missed.
    function refresh(done, full) {
        if (root.loaded && !full) {
            done(windows.slice(), focusedId);
            return;
        }
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
            // Sway reports no focused window while the launcher has the keyboard, so we keep the
            // last one from the events then.
            const focused = nodes.find(n => n.focused);
            root.windows = nodes.map(n => entry(n));
            if (focused)
                root.focusedId = String(focused.id);
            root.loaded = true;
            done(root.windows.slice(), root.focusedId);
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
