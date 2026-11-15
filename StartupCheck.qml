import QtQuick
import qs.Common

// Runs once when the plugin is enabled. Window listing and moving go through Hyprland's hyprctl
// (0.55+ for the Lua dispatcher syntax), and jq reads the focused workspace when a window is pulled.
QtObject {
    readonly property string minHyprland: "0.55.0"

    function check(done) {
        // Windows are moved with the Lua dispatcher syntax (hl.dsp.*), added with Lua config in 0.55.
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
                1: ["hyprctl not found", "Pull Window only works on Hyprland."],
                2: ["Not running on Hyprland", "Pull Window only works on Hyprland."],
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
}
