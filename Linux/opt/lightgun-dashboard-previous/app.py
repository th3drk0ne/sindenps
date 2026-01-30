
#!/usr/bin/env python3
import os
import re
import time
import subprocess
import xml.etree.ElementTree as ET
from typing import List, Dict, Tuple

from flask import Flask, jsonify, render_template_string, send_from_directory, request

app = Flask(__name__)

# ---------------------------
# Services & system utilities
# ---------------------------
SERVICES = [
    "lightgun.service",
    "lightgun-monitor.service",
]

SYSTEMCTL = "/usr/bin/systemctl"
SUDO = "/usr/bin/sudo"

# ---------------------------
# Config file locations
# ---------------------------
CONFIG_PATHS = {
    "ps2": "/home/sinden/Lightgun/PS2/LightgunMono.exe.config",
    "ps1": "/home/sinden/Lightgun/PS1/LightgunMono.exe.config",
}
DEFAULT_PLATFORM = "ps2"

# ---------------------------
# Sinden log
# ---------------------------
SINDEN_LOGFILE = "/home/sinden/Lightgun/log/sinden.log"


# ===========================
# Systemd helpers
# ===========================

def get_status(service: str) -> str:
    """Return systemd service status: 'active', 'inactive', 'failed', 'unknown', etc."""
    try:
        out = subprocess.check_output([SYSTEMCTL, "is-active", service], stderr=subprocess.STDOUT)
        return out.decode().strip()
    except subprocess.CalledProcessError:
        return "unknown"


def control_service(service: str, action: str) -> bool:
    """Run sudo systemctl <action> <service>. Returns True on success."""
    try:
        subprocess.check_output([SUDO, SYSTEMCTL, action, service], stderr=subprocess.STDOUT)
        return True
    except subprocess.CalledProcessError as e:
        print("CONTROL ERROR:", e.output.decode(errors="replace"))
        return False

# ===========================
# System power actions
# ===========================

def system_power_action(action: str) -> bool:
    """
    action: 'reboot' or 'shutdown'
    Uses: sudo systemctl reboot|poweroff
    """
    if action not in ("reboot", "shutdown"):
        return False
    try:
        cmd = [SUDO, SYSTEMCTL, "reboot" if action == "reboot" else "poweroff"]
        subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        return True
    except subprocess.CalledProcessError as e:
        print("POWER ACTION ERROR:", e.output.decode(errors="replace"))
        return False

# ===========================
# Flask routes: services
# ===========================

@app.route("/api/services")
def list_services():
    return jsonify({s: get_status(s) for s in SERVICES})


@app.route("/api/service/<name>/<action>", methods=["POST"])
def service_action(name, action):
    if name not in SERVICES:
        return jsonify({"error": "unknown service"}), 400
    if action not in ("start", "stop", "restart"):
        return jsonify({"error": "invalid action"}), 400
    ok = control_service(name, action)
    return jsonify({"success": ok, "status": get_status(name)})


@app.route("/api/logs/<service>")
def service_logs(service):
    if service not in SERVICES:
        return jsonify({"error": "unknown service"}), 400
    try:
        out = subprocess.check_output([SYSTEMCTL, "status", service, "--no-pager"], stderr=subprocess.STDOUT)
        return jsonify({"logs": out.decode(errors="replace")})
    except subprocess.CalledProcessError as e:
        return jsonify({"logs": e.output.decode(errors="replace")})


# ===========================
# Sinden log passthrough
# ===========================

@app.route("/api/sinden-log")
def sinden_log():
    try:
        with open(SINDEN_LOGFILE, "r", encoding="utf-8", errors="replace") as f:
            return jsonify({"logs": f.read()})
    except Exception as e:
        return jsonify({"logs": f"Error reading log: {e}"})


# ===========================
# XML config helpers (PS1/PS2)
# ===========================

def _resolve_platform(p: str) -> str:
    p = (p or "").lower()
    return p if p in CONFIG_PATHS else DEFAULT_PLATFORM


def _ensure_stub(path: str) -> None:
    """Create a minimal XML stub if missing."""
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(
                '<?xml version="1.0" encoding="utf-8"?>\n'
                '<configuration><appSettings></appSettings></configuration>\n'
            )


def _load_config_tree(path: str) -> ET.ElementTree:
    """Load XML tree using a parser that preserves comments/PIs."""
    _ensure_stub(path)
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
    return ET.parse(path, parser=parser)


def _appsettings_root(tree: ET.ElementTree) -> ET.Element:
    root = tree.getroot()
    appsettings = root.find("appSettings")
    if appsettings is None:
        appsettings = ET.SubElement(root, "appSettings")
    return appsettings


def _kv_items(appsettings: ET.Element) -> List[ET.Element]:
    """Return <add> elements in document order."""
    return [el for el in list(appsettings) if el.tag == "add" and "key" in el.attrib]


def _split_by_player(appsettings: ET.Element) -> Tuple[List[Dict[str, str]], List[Dict[str, str]]]:
    """Split into player1 and player2 (P2 suffix) lists, preserving order."""
    p1: List[Dict[str, str]] = []
    p2: List[Dict[str, str]] = []
    for el in _kv_items(appsettings):
        key = el.attrib.get("key", "")
        val = el.attrib.get("value", "")
        if key.endswith("P2"):
            p2.append({"key": key[:-2], "value": val})
        else:
            p1.append({"key": key, "value": val})
    return p1, p2


# ===========================
# STRICT preservation writer
# ===========================

_ADD_TAG_RE = re.compile(r"<add\b[^>]*>", re.IGNORECASE)

def _xml_escape_attr(s: str) -> str:
    """Escape for XML attribute value."""
    if s is None:
        return ""
    s = str(s)
    return (s
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&apos;"))

def _build_desired_map(p1_list, p2_list) -> Dict[str, str]:
    desired: Dict[str, str] = {}
    for item in (p1_list or []):
        k = item.get("key")
        if k:
            desired[str(k)] = str(item.get("value", ""))
    for item in (p2_list or []):
        k = item.get("key")
        if k:
            desired[str(k) + "P2"] = str(item.get("value", ""))
    return desired

def _detect_add_indentation(text: str) -> str:
    for line in text.splitlines(True):
        if "<add" in line:
            m = re.match(r"^([ \t]*)<add\b", line)
            if m:
                return m.group(1)
    return "    "

def update_config_preserve_layout(path: str, p1_list, p2_list) -> None:
    """
    Strictly preserve the original XML layout:
      - Never rebuild/pretty-print the XML
      - Patch ONLY the value= attribute of existing <add key="..."> entries
      - Insert missing keys immediately before </appSettings> (without moving comments)
    """
    desired = _build_desired_map(p1_list, p2_list)

    if not os.path.exists(path):
        _ensure_stub(path)

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        original = f.read()

    updated = original
    found_keys = set()

    def patch_add_tag(match: re.Match) -> str:
        tag = match.group(0)
        key_m = re.search(r"\bkey\s*=\s*(['\"])(.*?)\1", tag, re.IGNORECASE)
        if not key_m:
            return tag
        key = key_m.group(2)
        if key not in desired:
            return tag

        found_keys.add(key)
        new_val = _xml_escape_attr(desired[key])

        # Preserve quote style if possible
        val_m = re.search(r"\bvalue\s*=\s*(['\"])(.*?)\1", tag, re.IGNORECASE)
        if val_m:
            quote = val_m.group(1)
            # Replace only the value contents
            start, end = val_m.span(2)
            return tag[:start] + new_val + tag[end:]
        else:
            # Insert value after key attribute to minimize disturbance
            insert_at = key_m.end(0)
            return tag[:insert_at] + f' value="{new_val}"' + tag[insert_at:]

    updated = _ADD_TAG_RE.sub(patch_add_tag, updated)

    missing = [k for k in desired.keys() if k not in found_keys]
    if missing:
        indent = _detect_add_indentation(updated)
        close_m = re.search(r"</appSettings\s*>", updated, re.IGNORECASE)
        if not close_m:
            raise ValueError("Could not locate </appSettings> in config; refusing to insert missing keys.")

        insert_pos = close_m.start()
        newline = "\r\n" if "\r\n" in updated else "\n"

        insertion_lines = []
        for k in missing:
            v = _xml_escape_attr(desired[k])
            insertion_lines.append(f'{indent}<add key="{_xml_escape_attr(k)}" value="{v}" />')

        insertion = newline + "\n".join(insertion_lines) + newline
        updated = updated[:insert_pos] + insertion + updated[insert_pos:]

    if updated != original:
        # newline="" preserves existing newlines as much as possible
        with open(path, "w", encoding="utf-8", newline="") as f:
            f.write(updated)


# ===========================
# Profiles helpers
# ===========================

PROFILE_NAME_RE = re.compile(r"^[A-Za-z0-9_-]{1,60}$")

def _profiles_dir_for(path: str) -> str:
    pdir = os.path.join(os.path.dirname(path), "profiles")
    os.makedirs(pdir, exist_ok=True)
    return pdir

def _safe_profile_name(name: str) -> str:
    if not name:
        raise ValueError("Profile name is required")
    if not PROFILE_NAME_RE.match(name):
        raise ValueError("Invalid profile name. Use letters, digits, _ or -, max 60 chars.")
    return name

def _profile_path(platform: str, name: str) -> str:
    platform = _resolve_platform(platform)
    live_cfg = CONFIG_PATHS[platform]
    pdir = _profiles_dir_for(live_cfg)
    return os.path.join(pdir, f"{_safe_profile_name(name)}.config")

def _list_profiles(platform: str) -> List[Dict[str, str]]:
    """Enumerate profiles for a platform, sorted by mtime desc (name is extension-stripped correctly)."""
    platform = _resolve_platform(platform)
    live_cfg = CONFIG_PATHS[platform]
    pdir = _profiles_dir_for(live_cfg)

    items: List[Dict[str, str]] = []
    if os.path.isdir(pdir):
        for fname in os.listdir(pdir):
            if not fname.endswith(".config"):
                continue
            full = os.path.join(pdir, fname)
            try:
                st = os.stat(full)
                items.append({
                    "name": os.path.splitext(fname)[0],
                    "path": full,
                    "mtime": int(st.st_mtime),
                })
            except FileNotFoundError:
                pass

    items.sort(key=lambda x: x["mtime"], reverse=True)
    return items


# ===========================
# Flask routes: configuration
# ===========================

@app.route("/api/config", methods=["GET"])
def api_config_get():
    try:
        platform = _resolve_platform(request.args.get("platform"))
        profile_name = (request.args.get("profile") or "").strip()

        if profile_name:
            path = _profile_path(platform, profile_name)
            source = "profile"
        else:
            path = CONFIG_PATHS[platform]
            source = "live"

        tree = _load_config_tree(path)
        appsettings = _appsettings_root(tree)
        p1, p2 = _split_by_player(appsettings)

        return jsonify({
            "ok": True,
            "platform": platform,
            "path": path,
            "player1": p1,
            "player2": p2,
            "source": source,
            "profile": profile_name if profile_name else "",
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@app.route("/api/config/save", methods=["POST"])
def api_config_save():
    """Strict-preserve save: patch values in-place without changing comment/order/layout."""
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        path = CONFIG_PATHS[platform]
        p1_list = data.get("player1", [])
        p2_list = data.get("player2", [])

        ts = time.strftime("%Y%m%d-%H%M%S")
        cfg_dir = os.path.dirname(path)
        cfg_base = os.path.basename(path)
        backup_dir = os.path.join(cfg_dir, "backups")
        os.makedirs(backup_dir, exist_ok=True)
        backup_path = os.path.join(backup_dir, f"{cfg_base}.{ts}.bak")

        # Byte-for-byte backup
        if not os.path.exists(path):
            _ensure_stub(path)
        with open(path, "rb") as src, open(backup_path, "wb") as dst:
            dst.write(src.read())

        update_config_preserve_layout(path, p1_list, p2_list)
        return jsonify({"ok": True, "platform": platform, "path": path, "backup": backup_path})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/system/<action>", methods=["POST"])
def api_system_action(action):
    if action not in ("reboot", "shutdown"):
        return jsonify({"ok": False, "error": "invalid action"}), 400
    ok = system_power_action(action)
    # NOTE: Response may not be delivered if system goes down quickly—this is normal.
    return jsonify({"ok": ok})

# ===========================
# Profiles API
# ===========================

@app.route("/api/config/profiles", methods=["GET"])
def api_profiles_list():
    try:
        platform = _resolve_platform(request.args.get("platform"))
        return jsonify({"ok": True, "platform": platform, "profiles": _list_profiles(platform)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/config/profile/save", methods=["POST"])
def api_profile_save():
    """Copy LIVE config to profiles/<name>.config (byte-for-byte)."""
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        name = _safe_profile_name((data.get("name") or "").strip())
        overwrite = bool(data.get("overwrite", False))

        live_path = CONFIG_PATHS[platform]
        prof_path = _profile_path(platform, name)

        if not os.path.exists(live_path):
            _ensure_stub(live_path)

        if os.path.exists(prof_path) and not overwrite:
            return jsonify({"ok": False, "error": "Profile already exists"}), 409

        os.makedirs(os.path.dirname(prof_path), exist_ok=True)
        with open(live_path, "rb") as src, open(prof_path, "wb") as dst:
            dst.write(src.read())

        os.chmod(prof_path, 0o664)
        return jsonify({"ok": True, "platform": platform, "profile": name, "path": prof_path})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/config/profile/load", methods=["POST"])
def api_profile_load():
    """Overwrite LIVE config with selected profile (byte-for-byte), backing up live first."""
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        name = _safe_profile_name((data.get("name") or "").strip())

        live_path = CONFIG_PATHS[platform]
        prof_path = _profile_path(platform, name)

        if not os.path.exists(prof_path):
            return jsonify({"ok": False, "error": "Profile not found"}), 404

        if not os.path.exists(live_path):
            _ensure_stub(live_path)

        ts = time.strftime("%Y%m%d-%H%M%S")
        cfg_dir = os.path.dirname(live_path)
        cfg_base = os.path.basename(live_path)
        backup_dir = os.path.join(cfg_dir, "backups")
        os.makedirs(backup_dir, exist_ok=True)
        backup_path = os.path.join(backup_dir, f"{cfg_base}.{ts}.bak")

        with open(live_path, "rb") as src, open(backup_path, "wb") as dst:
            dst.write(src.read())

        with open(prof_path, "rb") as src, open(live_path, "wb") as dst:
            dst.write(src.read())

        os.chmod(live_path, 0o664)
        return jsonify({"ok": True, "platform": platform, "profile": name, "path": live_path, "backup": backup_path})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/config/profile/delete", methods=["POST"])
def api_profile_delete():
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        name = _safe_profile_name((data.get("name") or "").strip())

        prof_path = _profile_path(platform, name)
        if not os.path.exists(prof_path):
            return jsonify({"ok": False, "error": "Profile not found"}), 404

        os.remove(prof_path)
        return jsonify({"ok": True, "platform": platform, "profile": name})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


# ===========================
# Backups: list & restore (NEW, additive; existing functions unchanged)
# ===========================

def _backup_dir_for_platform(platform: str) -> Tuple[str, str, str]:
    """
    Returns (backup_dir, cfg_base, live_path) for the resolved platform.
    - backup_dir: <cfg_dir>/backups
    - cfg_base: e.g. "LightgunMono.exe.config"
    - live_path: full path to live config
    """
    platform = _resolve_platform(platform)
    live_path = CONFIG_PATHS[platform]
    cfg_dir = os.path.dirname(live_path)
    backup_dir = os.path.join(cfg_dir, "backups")
    os.makedirs(backup_dir, exist_ok=True)
    return backup_dir, os.path.basename(live_path), live_path


@app.route("/api/config/backups", methods=["GET"])
def api_backup_list():
    """List backups for a platform, sorted by mtime desc."""
    try:
        platform = _resolve_platform(request.args.get("platform"))
        backup_dir, cfg_base, _ = _backup_dir_for_platform(platform)

        items: List[Dict[str, str]] = []
        if os.path.isdir(backup_dir):
            for fname in os.listdir(backup_dir):
                if not (fname.startswith(cfg_base + ".") and fname.endswith(".bak")):
                    continue
                full = os.path.join(backup_dir, fname)
                try:
                    st = os.stat(full)
                    items.append({
                        "name": fname,
                        "path": full,
                        "mtime": int(st.st_mtime),
                        "size": st.st_size,
                    })
                except FileNotFoundError:
                    pass

        items.sort(key=lambda x: x["mtime"], reverse=True)
        return jsonify({"ok": True, "platform": platform, "backups": items})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


@app.route("/api/config/backup/restore", methods=["POST"])
def api_backup_restore():
    """
    Restore a selected backup file to the live config for the platform.
    - Validates filename to prevent traversal and cross-platform restores
    - Makes a safety backup of the current live file before overwriting
    """
    try:
        data = request.get_json(force=True) or {}
        platform = _resolve_platform(data.get("platform"))
        filename = (data.get("filename") or "").strip()

        backup_dir, cfg_base, live_path = _backup_dir_for_platform(platform)

        # Validate filename
        if not filename or "/" in filename or "\\" in filename:
            return jsonify({"ok": False, "error": "Invalid filename"}), 400
        if not (filename.startswith(cfg_base + ".") and filename.endswith(".bak")):
            return jsonify({"ok": False, "error": "Not a valid backup for this platform"}), 400

        src_path = os.path.join(backup_dir, filename)
        if not os.path.exists(src_path):
            return jsonify({"ok": False, "error": "Backup not found"}), 404

        # Ensure live exists so our safety copy is consistent
        if not os.path.exists(live_path):
            _ensure_stub(live_path)

        # Safety backup of current live (fixed f-string)
        ts = time.strftime("%Y%m%d-%H%M%S")
        safety_backup = os.path.join(backup_dir, f"{cfg_base}.{ts}.restore.bak")
        with open(live_path, "rb") as src, open(safety_backup, "wb") as dst:
            dst.write(src.read())

        # Restore selected backup to live
        with open(src_path, "rb") as src, open(live_path, "wb") as dst:
            dst.write(src.read())
        os.chmod(live_path, 0o664)

        return jsonify({
            "ok": True,
            "platform": platform,
            "path": live_path,
            "restored_from": src_path,
            "safety_backup": safety_backup,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 400


# ===========================
# Static passthroughs & index
# ===========================

@app.route("/logo.png")
def logo():
    return send_from_directory("/opt/lightgun-dashboard", "logo.png")


@app.route("/")
def index():
    with open("/opt/lightgun-dashboard/index.html", "r", encoding="utf-8") as f:
        return render_template_string(f.read())


@app.route("/healthz")
def healthz():
    return jsonify({"ok": True}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
