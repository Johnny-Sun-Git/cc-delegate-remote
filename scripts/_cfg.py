#!/usr/bin/env python3
"""Config helper for delegate-remote. Not meant to be called directly by a person;
the bash scripts in this folder shell out to it. See hosts.example.json for the schema.
"""
import json
import sys


def die(msg):
    print(msg, file=sys.stderr)
    sys.exit(1)


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        die(f"配置文件不存在: {path}\n先复制 hosts.example.json 到这个路径,改成你自己的 host/profile。")
    except json.JSONDecodeError as e:
        die(f"配置文件不是合法 JSON: {path}\n{e}")


def host_entry(cfg, host):
    h = cfg.get(host)
    if h is None:
        die(f"host 不存在: {host}(配置里有: {', '.join(k for k in cfg if not k.startswith('//'))})")
    return h


def main():
    if len(sys.argv) < 3:
        die("用法: _cfg.py <config.json> <action> [args...]")
    path, action = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    cfg = load(path)

    if action == "list-hosts":
        for k in cfg:
            if not k.startswith("//"):
                print(k)
        return

    if action == "has-host":
        sys.exit(0 if args and args[0] in cfg else 1)

    host = args[0] if args else die("缺少 host 参数")
    h = host_entry(cfg, host)

    if action == "get-remote-root":
        root = h.get("remote_task_root")
        if not root:
            die(f"host {host} 没配置 remote_task_root")
        print(root)
        return

    if action == "get-default-profile":
        print(h.get("default_profile", "default"))
        return

    if action == "list-profiles":
        for k in h.get("profiles", {}):
            print(k)
        return

    profile = args[1] if len(args) > 1 else h.get("default_profile", "default")
    profiles = h.get("profiles", {})
    p = profiles.get(profile)
    if p is None:
        die(f"host {host} 没有 profile {profile}(有: {', '.join(profiles)})")

    if action == "has-profile":
        sys.exit(0)

    if action == "get-bin":
        print(p.get("bin", "claude"))
        return

    if action == "get-args":
        for a in p.get("args", []):
            print(a)
        return

    die(f"未知 action: {action}")


if __name__ == "__main__":
    main()
