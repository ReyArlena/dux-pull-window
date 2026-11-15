import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Launcher plugin: lists open windows and pulls the chosen one onto the workspace you are on.
// The opposite of moving the active window away with SUPER + SHIFT + <n>.
QtObject {
    id: root

    readonly property string pluginKey: "pullWindow"
    readonly property int maxResults: 50
    // The window list is refreshed in the background; a short TTL keeps it current each time the
    // launcher opens without running hyprctl on every keystroke.
    readonly property int cacheTtlMs: 1000

    property var pluginService: null
    property string trigger: ":pw"

    // [{ address, title, cls, workspace, workspaceId, focusHistoryID }]
    property var windows: []
    // Workspace the launcher was opened on, as a Hyprland workspace selector ("3", "special:scratch").
    property string target: ""
    property double refreshedAt: 0
    property bool refreshing: false

    signal itemsChanged

    Component.onCompleted: loadSettings()

    onPluginServiceChanged: {
        if (pluginService)
            loadSettings();
    }

    property var pluginDataChangedConnection: Connections {
        target: pluginService
        enabled: pluginService !== null

        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === root.pluginKey)
                loadSettings();
        }
    }

    function loadSettings() {
        if (!pluginService)
            return;
        // An empty trigger would answer every launcher query.
        trigger = (pluginService.loadPluginData(pluginKey, "trigger", ":pw") || "").trim() || ":pw";
    }

    // Workspace on the focused monitor (the one the mouse is on, where the launcher opens).
    // An open special workspace (scratchpad) wins, since that is what is on screen.
    function targetOf(monitors) {
        for (let i = 0; i < monitors.length; i++) {
            const m = monitors[i];
            if (!m.focused)
                continue;
            if (m.specialWorkspace && m.specialWorkspace.name)
                return m.specialWorkspace.name;
            return String(m.activeWorkspace.id);
        }
        return "";
    }

    function selectorOf(ws) {
        return ws.id < 0 ? ws.name : String(ws.id);
    }

    // One process: clients, a separator line, then monitors.
    function refresh() {
        refreshing = true;
        Proc.runCommand("pullWindow.refresh", ["sh", "-c", "hyprctl clients -j || exit 1\necho '\x1e'\nhyprctl monitors -j || exit 2"], (stdout, exitCode) => {
            refreshing = false;
            if (exitCode !== 0)
                return;
            const parts = (stdout || "").split("\x1e");
            if (parts.length < 2)
                return;
            let clients = [];
            let monitors = [];
            try {
                clients = JSON.parse(parts[0]);
                monitors = JSON.parse(parts[1]);
            } catch (e) {
                return;
            }
            target = targetOf(monitors);
            windows = clients.filter(c => c.mapped && !c.hidden && c.address).map(c => ({
                        address: c.address,
                        title: c.title || c.initialTitle || c.class || "",
                        cls: c.class || c.initialClass || "",
                        workspace: c.workspace ? (c.workspace.name || String(c.workspace.id)) : "",
                        workspaceId: c.workspace ? selectorOf(c.workspace) : "",
                        focusHistoryID: typeof c.focusHistoryID === "number" ? c.focusHistoryID : 9999
                    })).sort((a, b) => a.focusHistoryID - b.focusHistoryID);
            refreshedAt = Date.now();
            itemsChanged();
        }, 50, 5000);
    }

    function isWordStart(lower, idx) {
        return idx === 0 || "-_. ".indexOf(lower[idx - 1]) >= 0;
    }

    // Higher is better, 0 means no match. Space-separated tokens must match in order, each as a
    // substring (preferring word starts) or else as a subsequence. Same scorer as Open With.
    function score(name, query) {
        const tokens = query.split(/\s+/).filter(t => t.length > 0);
        if (tokens.length === 0)
            return 1;
        const lower = name.toLowerCase();
        if (lower === query)
            return 10000;

        let total = 0;
        let pos = 0;
        for (let t = 0; t < tokens.length; t++) {
            const token = tokens[t];
            let idx = -1;
            for (let i = lower.indexOf(token, pos); i >= 0; i = lower.indexOf(token, i + 1)) {
                if (isWordStart(lower, i)) {
                    idx = i;
                    break;
                }
                if (idx < 0)
                    idx = i;
            }
            if (idx >= 0) {
                total += token.length * 10 + (isWordStart(lower, idx) ? 50 : 0) + (idx === 0 ? 50 : 0);
                pos = idx + token.length;
                continue;
            }
            let qi = 0;
            let i = pos;
            for (; i < lower.length && qi < token.length; i++) {
                if (lower[i] === token[qi])
                    qi++;
            }
            if (qi < token.length)
                return 0;
            total += token.length * 2;
            pos = i;
        }
        return Math.max(1, total * 10 - lower.length);
    }

    function iconFor(cls) {
        const entry = cls ? DesktopEntries.heuristicLookup(cls) : null;
        return entry && entry.icon ? "image:" + entry.icon : "material:web_asset";
    }

    function getItems(query) {
        if (Date.now() - refreshedAt > cacheTtlMs && !refreshing)
            refresh();

        const search = (query || "").trim().toLowerCase();
        const matches = [];
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            // Already here, nothing to pull.
            if (w.workspaceId === target)
                continue;
            // Class first so "firefox" or "ghostty" finds every window of that app.
            const s = Math.max(score(w.cls + " " + w.title, search), score(w.title, search));
            if (s > 0)
                matches.push({ w: w, score: s, order: i });
        }
        // Empty query keeps most recently used first; a search ranks by match.
        if (search.length > 0)
            matches.sort((a, b) => b.score - a.score || a.order - b.order);

        const items = [];
        for (let i = 0; i < matches.length && i < maxResults; i++) {
            const w = matches[i].w;
            items.push({
                name: w.title,
                comment: w.cls + "  -  workspace " + w.workspace,
                action: "pull:" + w.address,
                icon: iconFor(w.cls),
                categories: ["Pull Window"],
                // Stops the launcher re-scoring against the full query and dropping results.
                _preScored: 1000 - i
            });
        }
        return items;
    }

    function executeItem(item) {
        if (!item || !item.action || item.action.indexOf("pull:") !== 0)
            return;
        const address = item.action.substring(5);
        if (!/^0x[0-9a-f]+$/i.test(address))
            return;
        // Re-read the target now: the list may be up to a second old.
        const script = 'ws=$(hyprctl monitors -j | jq -r \'.[] | select(.focused) | if .specialWorkspace.name != "" then .specialWorkspace.name else (.activeWorkspace.id | tostring) end\')\n'
            + '[ -n "$ws" ] || exit 1\n'
            + 'hyprctl dispatch "hl.dsp.window.move({ workspace = \\"$ws\\", follow = false, window = \\"address:$1\\" })" >/dev/null\n'
            + 'hyprctl dispatch "hl.dsp.focus({ window = \\"address:$1\\" })" >/dev/null';
        Proc.runCommand("pullWindow.pull", ["sh", "-c", script, "_", address], (stdout, exitCode) => {
            if (exitCode !== 0)
                ToastService.showError("Pull Window: could not find the focused workspace");
        }, 0, 5000);
    }
}
