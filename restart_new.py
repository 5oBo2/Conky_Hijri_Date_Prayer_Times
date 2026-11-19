#!/usr/bin/env python3
"""Compatibility shortcut for Weather v2 users; delegates to canonical restart.py."""
from restart import main

if __name__ == '__main__':
    raise SystemExit(main(['--widget', 'new', *__import__('sys').argv[1:]]))
