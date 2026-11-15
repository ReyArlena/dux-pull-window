import QtQuick
import Quickshell
import qs.Common
import qs.Services

// Launcher plugin: lists open windows and pulls the chosen one onto the workspace you are on.
// The opposite of moving the active window away with SUPER + SHIFT + <n>.
//
// This file is the compositor-neutral core: search, ranking, most-recently-used order, launcher
// items. Each compositor has a backend (HyprlandBackend.qml, SwayBackend.qml, MangoBackend.qml,
// NiriBackend.qml) that lists windows with the compositor's own ids and moves them; see `backend`
// below for the interface.
QtObject {
    id: root

    readonly property string pluginKey: "pullWindow"
    readonly property int maxResults: 50
    // Backends report changes as they happen, so the list is ready when the launcher opens.
    // The TTL is a fallback in case an event was missed, without a refresh on every keystroke.
    readonly property int cacheTtlMs: 1000

    property var pluginService: null
    property string trigger: ":pw"

    // Backend interface:
    //   signal updated                      the window list or the focused window changed
    //   refresh(done)                       done([{ id, title, appId }], focusedId), or done(null)
    //   pull(id, done)                      done(null) on success, done("reason") on failure
    property var backend: null

    // [{ id, title, appId }], most recently used first.
    property var windows: []
    // Window ids, most recently used first. Kept across refreshes; a backend's own order only
    // places windows the core has not seen yet (all of them on the first refresh).
    property var recent: []
    property double refreshedAt: 0
    property bool refreshing: false

    signal itemsChanged

    // The launcher does not listen to itemsChanged; requestLauncherUpdate is what makes it
    // re-query, so results that arrive after the launcher opened show up straight away.
    onItemsChanged: {
        if (pluginService && typeof pluginService.requestLauncherUpdate === "function")
            pluginService.requestLauncherUpdate(pluginKey);
    }

    Component.onCompleted: {
        loadSettings();
        createBackend();
    }

    onPluginServiceChanged: {
        if (!pluginService)
            return;
        loadSettings();
        // Warm the cache so the first open has something to show straight away.
        refresh();
    }

    property var backendConnection: Connections {
        target: root.backend
        enabled: root.backend !== null

        function onUpdated() {
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

    // Loaded by file, so only the running compositor's backend (and its Quickshell module) loads.
    function createBackend() {
        if (backend)
            return;
        const file = CompositorService.isHyprland ? "HyprlandBackend.qml" : CompositorService.isSway ? "SwayBackend.qml" : CompositorService.isMango ? "MangoBackend.qml" : CompositorService.isNiri ? "NiriBackend.qml" : "";
        if (!file)
            return;
        const component = Qt.createComponent(Qt.resolvedUrl(file));
        if (component.status !== Component.Ready) {
            console.error("Pull Window: could not load " + file + ": " + component.errorString());
            return;
        }
        backend = component.createObject(root);
    }

    function refresh() {
        if (!backend)
            return;
        refreshing = true;
        backend.refresh((list, focusedId) => {
            refreshing = false;
            if (list)
                applyList(list, focusedId);
        });
    }

    function applyList(list, focusedId) {
        const byId = {};
        for (let i = 0; i < list.length; i++)
            byId[list[i].id] = list[i];
        // Closed windows drop out; new ones go after the known ones, in the backend's order.
        let order = recent.filter(id => byId[id] !== undefined);
        const known = {};
        for (let i = 0; i < order.length; i++)
            known[order[i]] = true;
        for (let i = 0; i < list.length; i++) {
            if (!known[list[i].id])
                order.push(list[i].id);
        }
        // The focused window is the most recent.
        if (focusedId && byId[focusedId] !== undefined)
            order = [focusedId].concat(order.filter(id => id !== focusedId));
        recent = order;
        windows = order.map(id => byId[id]);
        refreshedAt = Date.now();
        itemsChanged();
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

    function iconFor(appId) {
        const entry = appId ? DesktopEntries.heuristicLookup(appId) : null;
        return entry && entry.icon ? "image:" + entry.icon : "material:web_asset";
    }

    function getItems(query) {
        if (Date.now() - refreshedAt > cacheTtlMs && !refreshing)
            refresh();

        const search = (query || "").trim().toLowerCase();
        const matches = [];
        for (let i = 0; i < windows.length; i++) {
            const w = windows[i];
            // App id first so "firefox" or "ghostty" finds every window of that app.
            const s = Math.max(score(w.appId + " " + w.title, search), score(w.title, search));
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
                comment: w.appId,
                action: "pull:" + w.id,
                icon: iconFor(w.appId),
                categories: ["Pull Window"],
                // Stops the launcher re-scoring against the full query and dropping results.
                _preScored: 1000 - i
            });
        }
        return items;
    }

    function executeItem(item) {
        if (!backend || !item || !item.action || item.action.indexOf("pull:") !== 0)
            return;
        const id = item.action.substring(5);
        // Only ids the backend listed; the backend checks their format again.
        if (!windows.some(w => w.id === id))
            return;
        backend.pull(id, error => {
            if (error)
                ToastService.showError("Pull Window: " + error);
        });
    }
}
