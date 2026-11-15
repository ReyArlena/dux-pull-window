import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// MangoWC backend. Windows come from `mmsg get all-clients` with Mango's own client ids, and a
// window is moved by id onto the focused monitor's active tag without switching any view, so it
// also works for windows on headless outputs.
QtObject {
    id: root

    // The window list or the focused window changed.
    signal updated

    // `mmsg watch all-clients` prints the whole client list on every change (open, close,
    // title, focus): each line only triggers a refresh. Restarted if it ever exits.
    property var clientWatch: Process {
        command: ["mmsg", "watch", "all-clients"]
        running: true
        stdout: SplitParser {
            onRead: line => root.updated()
        }
        onExited: (exitCode, exitStatus) => restartWatch.start()
    }

    property var restartWatch: Timer {
        interval: 2000
        onTriggered: root.clientWatch.running = true
    }

    function parse(stdout) {
        try {
            return JSON.parse(stdout || "");
        } catch (e) {
            return null;
        }
    }

    // done([{ id, title, appId }], focusedId) or done(null) when Mango could not be read.
    // Mango keeps no focus history; its list is newest first, which seeds the core's order.
    function refresh(done) {
        Proc.runCommand("pullWindow.mango.clients", ["mmsg", "get", "all-clients"], (stdout, exitCode) => {
            const data = exitCode === 0 ? parse(stdout) : null;
            if (!data || !data.clients) {
                done(null, "");
                return;
            }
            let focusedId = "";
            const list = data.clients.map(c => {
                if (c.is_focused)
                    focusedId = String(c.id);
                return {
                    id: String(c.id),
                    title: c.title || c.appid || "",
                    appId: c.appid || ""
                };
            });
            done(list, focusedId);
        }, 50, 5000);
    }

    // done(null) on success, done("reason") on failure. The target is the focused monitor's
    // first active tag. mmsg reports success even when nothing moved (an unknown monitor is
    // ignored), so the window is read back to confirm.
    function pull(id, done) {
        if (!/^[0-9]+$/.test(id)) {
            done("unknown window");
            return;
        }
        Proc.runCommand("pullWindow.mango.monitors", ["mmsg", "get", "all-monitors"], (stdout, exitCode) => {
            const data = exitCode === 0 ? parse(stdout) : null;
            const mon = data && data.monitors ? data.monitors.find(m => m.active) : null;
            const tag = mon && mon.active_tags && mon.active_tags.length ? mon.active_tags[0] : 0;
            if (!mon || !tag) {
                done("could not find the focused monitor and tag");
                return;
            }
            Proc.runCommand("pullWindow.mango.client", ["mmsg", "get", "client", id], (out, code) => {
                const c = code === 0 ? parse(out) : null;
                if (!c || c.error || !c.monitor) {
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
                    Proc.runCommand("pullWindow.mango.verify", ["mmsg", "get", "client", id], (after, afterCode) => {
                        const moved = afterCode === 0 ? parse(after) : null;
                        const ok = moved && moved.monitor === mon.name && (moved.tags || []).indexOf(tag) >= 0;
                        done(ok ? null : "Mango did not move the window");
                    }, 0, 5000);
                }, 0, 5000);
            }, 0, 5000);
        }, 0, 5000);
    }
}
