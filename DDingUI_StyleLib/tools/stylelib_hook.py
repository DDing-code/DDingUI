"""Claude Code PostToolUse hook: re-sync StyleLib copies after an edit.

Reads the hook payload on stdin.  When the edited file belongs to the master
``DDingUI_StyleLib/`` or to any ``<Addon>/Libs/DDingUI_StyleLib/`` copy, the
edit is folded into the master and propagated to every embedded copy.  Other
paths are ignored silently.  Never blocks the tool call.
"""
import io
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync_stylelib as sync  # noqa: E402


def is_stylelib(path: Path) -> bool:
    try:
        parts = path.resolve().relative_to(sync.ROOT).parts
    except ValueError:
        return False
    if parts[:1] == ("DDingUI_StyleLib",):
        return len(parts) > 1 and parts[1] not in sync.MASTER_ONLY
    return len(parts) > 3 and parts[1:3] == ("Libs", "DDingUI_StyleLib") and parts[0] not in sync.FROZEN


def main() -> int:
    try:
        payload = json.loads(sys.stdin.buffer.read().decode("utf-8-sig"))
    except ValueError:
        return 0
    tool_input = payload.get("tool_input") or {}
    raw = tool_input.get("file_path") or (payload.get("tool_response") or {}).get("filePath")
    if not raw or not is_stylelib(Path(raw)):
        return 0
    out = io.StringIO()
    try:
        with redirect_stdout(out):
            code = sync.main(["--from", raw])
        text = out.getvalue().strip()
    except Exception as exc:  # report, never block the edit
        code, text = 1, f"StyleLib sync failed: {exc}"
    message = "StyleLib auto-sync: " + text.replace("\n", "; ")
    sys.stdout.reconfigure(encoding="utf-8")
    print(json.dumps({
        "systemMessage": message,
        "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": message},
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
