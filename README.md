# Claude Desktop Runtime Chinese UI

**English** | [简体中文](README.zh-CN.md)

A third-party Chinese interface script for Claude Desktop on Windows. Run the launcher to translate interface text in the current window. Page translation must be reapplied after a restart or full page refresh. Native menu language persists until restored.

**Current version: v0.5.1. This is not an official Anthropic project.**

## Download and use

1. Download [`Claude-runtime-zh-v0.5.1.zip`](https://github.com/Su-1003/claude-runtime-zh/raw/refs/heads/main/release-assets/v0.5.1/Claude-runtime-zh-v0.5.1.zip) and extract the entire archive to a writable folder. Its SHA-256 is listed in the same folder.
2. Open Claude Desktop. Before first use, enable **Developer Mode** yourself. If DevTools shows a paste safety prompt, review and handle it yourself.
3. Double-click **一键启动汉化.cmd** (apply Chinese). Avoid using the keyboard, mouse, or clipboard while it runs so that focus and copied content remain stable.
4. Wait for `SUCCESS` and confirm that the interface is in Chinese. To restore English, double-click **一键恢复英文.cmd** (restore English).

The main window typically takes about 10–25 seconds. Processing an open inference configuration window as well may take about 20–50 seconds, depending on the machine and window state. Press **Esc** to cancel.

You can move or rename the extracted folder. Keep its internal structure intact and recreate any shortcuts after moving it. The launcher creates `logs/claude-zh-owned-drafts` in the folder's parent directory, storing only request IDs and payload hashes. The parent directory must therefore also be writable.

## Compatibility and scope

- Supports the current Windows desktop main window and an already-open third-party inference configuration window. If you open the configuration window later, run the same launcher again.
- Development validation used Windows, Windows PowerShell 5.1, and Claude Desktop **4.4212.0.0**. Other versions have not been individually verified. The launcher does not support macOS or Linux.
- Does not modify Claude's EXE or ASAR files, install startup tasks or background services, or change API keys, gateways, models, or proxy settings.
- The page script does not initiate network requests. This statement does not cover Claude's own network activity.
- Attempts to skip input fields, code, common conversation content, file previews, and recognized custom project names, model names, and dynamic paths. These protections need revalidation when the interface structure changes.
- Supports native context-menu labels such as Undo, Redo, Cut, Copy, Paste, Select All, and Inspect Element through Claude Desktop's existing language bridge and built-in `zh-Hans` catalog. This also affects other native UI labels and persists across restarts. The prior locale is backed up in page-local storage before changing it. The restore launcher reverts that saved locale only if it has not since been changed elsewhere.
- If the native language bridge is unavailable, page translation still works and a console warning reports that native menus were skipped. Native locale changes or verification failures stop the launcher. Unlisted text and new interface structures may not be translated.

## Troubleshooting

**The interface returns to English after restarting.**

Page translation runs in the current page. Run the launcher again after restarting Claude or fully refreshing it. Native menu language persists separately until you use the restore launcher.

**DevTools opens, but the interface stays in English.**

Check the `STOPPED:` message in the launcher window. Avoid keyboard, mouse, and clipboard activity while it runs. If it cannot focus the target, click the intended Claude window and try again. Yellow console warnings alone do not establish that translation failed.

**The launcher reports an unknown unfinished command.**

Inspect and handle that command yourself before retrying. The launcher does not clear unrecognized drafts. It only replaces an older translation draft when its complete hash matches a local record. Moving the folder does not automatically migrate these records, so an old draft may require manual handling afterward.

**DevTools shows a paste safety prompt.**

Review this project's code and decide how to handle the prompt yourself. The script does not dismiss or bypass this protection for you.

**Some Chinese text remains after restoring English.**

Try the restore launcher again. A full refresh or restart removes the page script, but does not reset the native menu language. Keep the page-local locale backup until restoration succeeds; clearing app/site data can remove it. If no backup exists, or the native language was already Chinese before applying this script, restoration does not force a different native language.

**The clipboard contains a long block of code.**

The launcher temporarily uses the clipboard and may leave translation code there afterward. It does not automatically overwrite content you copy later.

Manual fallback launchers are `copy-script.cmd` and `restore.cmd`. Older configuration-specific launchers are in `兼容入口`; use the unified launcher for everyday use.

## Development and verification

Running the launcher does not require installing Python or Node.js. These tools are only needed for development tests.

```powershell
node --check claude-zh.js
node test-safety.cjs
node test-native-menu.cjs
node test-native-payload.cjs
python -m unittest test_dictionary.py
powershell.exe -NoProfile -MTA -ExecutionPolicy Bypass -File test-unified-launcher.ps1
powershell.exe -NoProfile -MTA -ExecutionPolicy Bypass -File test-launcher-reliability.ps1
```

On Windows with Edge installed, run the standalone DOM tests:

```powershell
python verify.py
python verify.py --page configuration-preview.html --report configuration-verification.json
python verify.py --page confirmation-preview.html --report confirmation-verification.json
python verify.py --page optimization-preview.html --report optimization-verification.json
```

These tests use isolated local fixtures. They do not approve permissions, delete files, or send messages in a real Claude window. Real-window compatibility requires separate validation. See [TESTING.md](TESTING.md) for the recorded test scope and results in Chinese, and [integrity-v050.json](integrity-v050.json) for the unchanged installation hashes and Valid signature.

To rebuild the dictionary:

```powershell
python build_dictionary.py --source "path/to/claude-desktop-zh-cn-main.zip" --resources "path/to/Claude/app/resources"
```

The build reads input resources and writes only to this project directory. Generated provenance reports may contain local absolute paths; remove those paths before publishing.

## Attribution and license

Translation data is adapted from [javaht/claude-desktop-zh-cn](https://github.com/javaht/claude-desktop-zh-cn), matched against English resources from the corresponding application version. Input hashes are recorded in `dictionary-provenance.json`. The upstream MIT license is preserved in `UPSTREAM-LICENSE.txt`.

This project is licensed under the [MIT License](LICENSE). The repository does not include Claude installation files. Claude and related trademarks belong to their respective owners.

When reporting an issue, include your Claude version, script version, and any `STOPPED:` message. Hide account details, API keys, conversation content, and other private information before sharing screenshots.
