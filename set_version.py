"""Stamp updater.py with the version passed as argument (e.g. v1.0.3 or 1.0.3)."""
import re, sys

v = sys.argv[1].lstrip("v")
txt = open("updater.py").read()
txt = re.sub(r'^VERSION = .*', f'VERSION = "{v}"', txt, flags=re.M)
open("updater.py", "w").write(txt)
print("Version set to", v)
