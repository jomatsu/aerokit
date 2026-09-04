/// Single source of the app version: the settings pane and `--version` read
/// it directly, and scripts/install-app.sh greps it into the bundle's
/// Info.plist so the binary and the bundle can never disagree.
public enum AppVersion {
    public static let current = "0.2.1"
}
