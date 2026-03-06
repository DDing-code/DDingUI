import os
import shutil
import subprocess

addons_dir = r"G:\wow2\World of Warcraft\_retail_\Interface\AddOns"
super_dir = r"C:\Users\D2JK\바탕화면\cd\DDingUI_Super"

def remove_readonly(func, path, excinfo):
    import stat
    os.chmod(path, stat.S_IWRITE)
    func(path)

addons = [d for d in os.listdir(addons_dir) if d.startswith('DDingUI') and os.path.isdir(os.path.join(addons_dir, d))]

for addon in addons:
    src = os.path.join(addons_dir, addon)
    dst = os.path.join(super_dir, addon)
    
    # Skip if src is already a junction/link
    # os.path.islink() works for directory junctions in Python >= 3.2
    # but to be extremely safe against older python versions or weird behaviors:
    try:
        # In python on windows, junctions have a reparse tag
        if os.stat(src).st_reparse_tag != 0:
            print(f"Skipping {addon}, is already a junction.")
            continue
    except AttributeError:
        # Fallback for Python versions that don't have st_reparse_tag
        res = subprocess.run(['cmd', '/c', 'dir', '/AL', src], capture_output=True, text=True)
        if "JUNCTION" in res.stdout or "SYMLINKD" in res.stdout:
            print(f"Skipping {addon}, is a junction.")
            continue

    if os.path.exists(dst):
        print(f"Skipping {addon}, already exists in DDingUI_Super.")
        continue

    print(f"Migrating {addon}...")
    try:
        shutil.copytree(src, dst)
        
        # Strip out any .git directories from the individual addon so it doesn't create submodules
        git_dir = os.path.join(dst, ".git")
        if os.path.exists(git_dir):
            shutil.rmtree(git_dir, onerror=remove_readonly)
            
        shutil.rmtree(src, onerror=remove_readonly)
        
        subprocess.run(['cmd', '/c', 'mklink', '/J', src, dst], check=True, capture_output=True)
        print(f"Success moving {addon}")
    except Exception as e:
        print(f"Failed moving {addon}: {e}")

print("All addons processed.")
