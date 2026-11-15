import QtQuick
import qs.Common
import qs.Services

// Runs once when the plugin is enabled: checks the running compositor is supported and has
// what its backend uses.
//   Hyprland: hyprctl (0.55+ for the Lua dispatcher syntax), and jq to read the focused workspace.
//   Sway: swaymsg and a reachable Sway socket.
//   MangoWC: mmsg and a reachable Mango socket.
QtObject {
    readonly property string minHyprland: "0.55.0"

    function check(done) {
        if (CompositorService.isHyprland)
            checkHyprland(done);
        else if (CompositorService.isSway)
            checkSway(done);
        else if (CompositorService.isMango)
            checkMango(done);
        else
            done({
                title: "Compositor not supported",
                details: "Pull Window works on Hyprland, Sway and MangoWC."
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

    function checkSway(done) {
        const script = "command -v swaymsg >/dev/null 2>&1 || exit 1\n"
            + "swaymsg -t get_version >/dev/null 2>&1 || exit 2";
        Proc.runCommand("pullWindow.startupCheck", ["sh", "-c", script], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            const messages = {
                1: ["swaymsg not found", "Pull Window needs Sway's swaymsg."],
                2: ["Sway socket not reachable", "swaymsg could not talk to Sway (is SWAYSOCK set in Dux Shell's environment?)."]
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
}
