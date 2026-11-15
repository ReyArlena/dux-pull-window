import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common
import qs.Services

// Launcher plugin: lists open windows and pulls the chosen one onto the workspace you are on.
// The opposite of moving the active window away with SUPER + SHIFT + <n>.
QtObject {
    id: root

    readonly property string pluginKey: "pullWindow"
    readonly property int maxResults: 50
    // The window list is kept current from Hyprland events, so it is ready when the launcher opens.
    // The TTL is a fallback in case an event was missed, without running hyprctl on every keystroke.
    readonly property int cacheTtlMs: 1000
    // Hyprland events that change the list or its order.
    readonly property var watchedEvents: ["openwindow", "closewindow", "windowtitle", "windowtitlev2", "activewindow", "activewindowv2", "minimized"]

    property var pluginService: null
    property string trigger: ":pw"

    // [{ address, title, cls, focusHistoryID }]
    property var windows: []
    property double refreshedAt: 0
    property bool refreshing: false

    signal itemsChanged

    Component.onCompleted: loadSettings()

    onPluginServiceChanged: {
        if (!pluginService)
            return;
        loadSettings();
        // Warm the cache so the first open has something to show straight away.
        refresh();
    }

    property var hyprlandEventsConnection: Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (root.watchedEvents.indexOf(event.name) >= 0)
                root.refresh();
        }
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

    // Calls within the debounce window (a burst of events) collapse into one run.
    function refresh() {
        refreshing = true;
        Proc.runCommand("pullWindow.refresh", ["hyprctl", "clients", "-j"], (stdout, exitCode) => {
            refreshing = false;
            if (exitCode !== 0)
                return;
            let clients = [];
            try {
                clients = JSON.parse(stdout || "[]");
            } catch (e) {
                return;
            }
            windows = clients.filter(c => c.mapped && !c.hidden && c.address).map(c => ({
                        address: c.address,
                        title: c.title || c.initialTitle || c.class || "",
                        cls: c.class || c.initialClass || "",
                        focusHistoryID: typeof c.focusHistoryID === "number" ? c.focusHistoryID : 9999
                    })).sort((a, b) => a.focusHistoryID - b.focusHistoryID);
            refreshedAt = Date.now();
            itemsChanged();
            // The launcher does not listen to itemsChanged; this is what makes it re-query, so the
            // first open (empty cache) fills in once hyprctl returns.
            if (pluginService && typeof pluginService.requestLauncherUpdate === "function")
                pluginService.requestLauncherUpdate(pluginKey);
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
                comment: w.cls,
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
        // Target: the active workspace on the focused monitor, or its open special workspace.
        const script = 'ws=$(hyprctl monitors -j | jq -r \'.[] | select(.focused) | if .specialWorkspace.name != "" then .specialWorkspace.name else (.activeWorkspace.id | tostring) end\')\n'
            + '[ -n "$ws" ] || exit 1\n'
            + '[ "$(hyprctl dispatch "hl.dsp.window.move({ workspace = \\"$ws\\", follow = false, window = \\"address:$1\\" })")" = ok ] || exit 2\n'
            + '[ "$(hyprctl dispatch "hl.dsp.focus({ window = \\"address:$1\\" })")" = ok ] || exit 3';
        Proc.runCommand("pullWindow.pull", ["sh", "-c", script, "_", address], (stdout, exitCode) => {
            const errors = {
                1: "could not find the focused workspace",
                2: "Hyprland refused to move the window",
                3: "moved the window but could not focus it",
                124: "Hyprland did not respond"
            };
            if (exitCode !== 0)
                ToastService.showError("Pull Window: " + (errors[exitCode] || "failed (exit " + exitCode + ")"));
        }, 0, 5000);
    }
}
