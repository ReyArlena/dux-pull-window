import QtQuick
import qs.Common

// Runs once when the plugin is enabled. Window listing and moving go through Hyprland's hyprctl,
// and jq reads the focused workspace when a window is pulled.
QtObject {
    function check(done) {
        Proc.runCommand("pullWindow.startupCheck", ["sh", "-c", "command -v hyprctl >/dev/null 2>&1 || exit 1\n[ -n \"$HYPRLAND_INSTANCE_SIGNATURE\" ] || exit 2\ncommand -v jq >/dev/null 2>&1 || exit 3"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            const messages = {
                1: ["hyprctl not found", "Pull Window only works on Hyprland."],
                2: ["Not running on Hyprland", "Pull Window only works on Hyprland."],
                3: ["jq is required", "Install jq, then enable the plugin again."]
            };
            const m = messages[exitCode] || ["Startup check failed", "Exit code " + exitCode];
            done({
                title: m[0],
                details: m[1]
            });
        });
    }
}
