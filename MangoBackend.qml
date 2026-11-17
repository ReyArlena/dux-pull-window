import QtQuick
import qs.Common
import qs.Services

// MangoWC backend. Windows come from DMS's MangoService with Mango's own client ids, and a window
// is moved by id onto the focused monitor's active tag without switching any view, so it also
// works for windows on headless outputs.
QtObject {
    id: root

    // The window list or the focused window changed.
    signal updated

    // MangoService already watches Mango's client list for DMS, so we just follow it rather than
    // running a second `mmsg watch` and an `mmsg get` on every change
    property var mangoEvents: Connections {
        target: MangoService

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

    // done([{ id, title, appId }], focusedId). Mango keeps no focus history; its list is newest
    // first, which seeds the core's order.
    function refresh(done) {
        let focusedId = "";
        const list = (MangoService.windows || []).map(c => {
            if (c.is_focused)
                focusedId = String(c.id);
            return {
                id: String(c.id),
                title: c.title || c.appid || "",
                appId: c.appid || ""
            };
        });
        done(list, focusedId);
    }

    // done(null) on success, done("reason") on failure. The target is the focused monitor's
    // first active tag. mmsg reports success even when nothing moved (an unknown monitor is
    // ignored), so the window is read back to confirm.
    function pull(id, done) {
        if (!/^[0-9]+$/.test(id)) {
            done("unknown window");
            return;
        }
        const mon = MangoService.getOutputState(MangoService.activeOutput);
        const tag = mon && mon.activeTags && mon.activeTags.length ? mon.activeTags[0] : 0;
        if (!mon || !tag) {
            done("could not find the focused monitor and tag");
            return;
        }
        const c = (MangoService.windows || []).find(w => String(w.id) === id);
        if (!c || !c.monitor) {
            done("the window is gone");
            return;
        }
        // Same monitor: tagcrossmon retags it (that path compares with the selected
        // monitor, which is this one). Another monitor: tagmon moves it, adopting the
        // target monitor's current tag, and leaves every view as it was.
        const action = c.monitor === mon.name ? "tagcrossmon," + tag + "," + mon.name : "tagmon," + mon.name + ",0";
        Proc.runCommand("pullWindow.mango.pull", ["mmsg", "dispatch", action, "client," + id], (reply, replyCode) => {
            if (replyCode === 124) {
                done("Mango did not respond");
                return;
            }
            const r = parse(reply);
            if (!r || r.error) {
                done("Mango refused: " + (r && r.error ? r.error : "no reply"));
                return;
            }
            // Asks Mango directly here. It only runs when a window is picked, and the
            // read-back has to see the move straight away, which MangoService only does once
            // Mango's watch sends the next list.
            Proc.runCommand("pullWindow.mango.verify", ["mmsg", "get", "client", id], (after, afterCode) => {
                const moved = afterCode === 0 ? parse(after) : null;
                const ok = moved && moved.monitor === mon.name && (moved.tags || []).indexOf(tag) >= 0;
                done(ok ? null : "Mango did not move the window");
            }, 0, 5000);
        }, 0, 5000);
    }
}
