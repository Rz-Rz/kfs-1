#!/usr/bin/env python3
from __future__ import annotations

import argparse

from kfs_metrics import repo_root_for, sync_branch_lifecycle


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sync KFS branch lifecycle metrics")
    parser.add_argument("--no-fetch", action="store_true", help="skip 'git fetch --prune origin'")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = repo_root_for(__file__)
    sync_branch_lifecycle(repo_root, fetch_remote=not args.no_fetch)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
