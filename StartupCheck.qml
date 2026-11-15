import QtQuick
import qs.Common
import qs.Services

// Runs once when the plugin is enabled: checks the running compositor is supported and has
// what its backend uses.
//   Hyprland: hyprctl (0.55+ for the Lua dispatcher syntax), and jq to read the focused workspace.
//   Sway / Scroll: swaymsg / scrollmsg and a reachable socket.
//   MangoWC: mmsg and a reachable Mango socket.
//   niri: niri msg and a reachable niri socket.
QtObject {
    id: root

    readonly property string minHyprland: "0.55.0"

    // DMS detects the compositor asynchronously; a check that runs before that (early at login)
    // would see no compositor and disable the plugin. Wait up to 5 s for the detection.
    property var pendingDone: null
    property int waitTicks: 0
    property var detectionWait: Timer {
        interval: 100
        repeat: true
        onTriggered: {
            root.waitTicks += 1;
            if (CompositorService.compositorDetected || root.waitTicks >= 50) {
                stop();
                root.checkCompositor(root.pendingDone);
            }
        }
    }

    function check(done) {
        if (CompositorService.compositorDetected) {
            checkCompositor(done);
            return;
        }
        pendingDone = done;
        detectionWait.start();
    }

    function checkCompositor(done) {
        if (CompositorService.isHyprland)
            checkHyprland(done);
        else if (CompositorService.isSway)
            checkSway(done, "swaymsg", "Sway");
        else if (CompositorService.isScroll)
            checkSway(done, "scrollmsg", "Scroll");
        else if (CompositorService.isMango)
            checkMango(done);
        else if (CompositorService.isNiri)
            checkNiri(done);
        else
            done({
                title: "Compositor not supported",
                details: "Pull Window works on Hyprland, Sway, Scroll, MangoWC and niri."
            });
    }

    function checkHyprland(done) {
        const script = "command -v hyprctl >/dev/null 2>&1 || exit 1\n"
            + "[ -n \"$HYPRLAND_INSTANCE_SIGNATURE\" ] || exit 2\n"
            + "command -v jq >/dev/null 2>&1 || exit 3\n"
            + "v=$(hyprctl version -j | jq -r '.version // empty' | sed 's/^v//')\n"
            + "[ -n \"$v\" ] || exit 4\n"
            + "[ \"$(printf '%s\\n%s\\n' \"$1\" \"$v\" | sort -V | head -1)\" = \"$1\" ] || { printf %s \"$v\"; exit 5; }";
        Proc.runCommand("pullWindow.startupCheck", ["sh", "-c", script, "_", minHyprland], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            const messages = {
                1: ["hyprctl not found", "Pull Window needs Hyprland's hyprctl."],
                2: ["Hyprland socket not found", "HYPRLAND_INSTANCE_SIGNATURE is not set in Dux Shell's environment."],
                3: ["jq is required", "Install jq, then enable the plugin again."],
                4: ["Could not read the Hyprland version", "hyprctl version -j returned no version."],
                5: ["Hyprland " + minHyprland + " or newer is required", "Found " + ((stdout || "").trim() || "an older version") + ". Pull Window moves windows with the Lua dispatcher syntax added in Hyprland " + minHyprland + "."]
            };
            const m = messages[exitCode] || ["Startup check failed", "Exit code " + exitCode];
            done({
                title: m[0],
                details: m[1]
            });
        });
    }

    function checkSway(done, msg, name) {
        const script = "command -v \"$1\" >/dev/null 2>&1 || exit 1\n"
            + "\"$1\" -t get_version >/dev/null 2>&1 || exit 2";
        Proc.runCommand("pullWindow.startupCheck", ["sh", "-c", script, "_", msg], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            const messages = {
                1: [msg + " not found", "Pull Window needs " + name + "'s " + msg + "."],
                2: [name + " socket not reachable", msg + " could not talk to " + name + " (is SWAYSOCK set in Dux Shell's environment?)."]
            };
            const m = messages[exitCode] || ["Startup check failed", "Exit code " + exitCode];
            done({
                title: m[0],
                details: m[1]
            });
        });
    }

    function checkMango(done) {
        const script = "command -v mmsg >/dev/null 2>&1 || exit 1\n"
            + "mmsg get version >/dev/null 2>&1 || exit 2";
        Proc.runCommand("pullWindow.startupCheck", ["sh", "-c", script], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            const messages = {
                1: ["mmsg not found", "Pull Window needs MangoWC's mmsg."],
                2: ["Mango socket not reachable", "mmsg could not talk to Mango (is MANGO_INSTANCE_SIGNATURE set in Dux Shell's environment?)."]
            };
            const m = messages[exitCode] || ["Startup check failed", "Exit code " + exitCode];
            done({
                title: m[0],
                details: m[1]
            });
        });
    }

    function checkNiri(done) {
        const script = "command -v niri >/dev/null 2>&1 || exit 1\n"
            + "niri msg version >/dev/null 2>&1 || exit 2";
        Proc.runCommand("pullWindow.startupCheck", ["sh", "-c", script], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            const messages = {
                1: ["niri not found", "Pull Window needs the niri command for niri msg."],
                2: ["niri socket not reachable", "niri msg could not talk to niri (is NIRI_SOCKET set in Dux Shell's environment?)."]
            };
            const m = messages[exitCode] || ["Startup check failed", "Exit code " + exitCode];
            done({
                title: m[0],
                details: m[1]
            });
        });
    }
}
