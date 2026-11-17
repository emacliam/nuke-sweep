# Mounted volumes

The Files toolbar includes a **Volumes** menu listing mounted volumes with free space. Selecting one:

- remembers the volume for folder access;
- starts a normal bounded Files scan rooted at the volume;
- uses the same review, evidence and Trash flow as any folder.

The boot volume is listed first, then internal volumes, then external volumes by name. Hidden system volumes are skipped by the volume enumeration. The scan is bounded by the same entry/time limits as other folder scans; large external drives can therefore produce partial results.

Nothing is selected or cleaned when choosing a volume. The menu is only a navigation shortcut.

Tests verify that the mounted-volume list is non-empty, contains the root volume, exposes valid capacity values, and sorts the root first.

Cleanup also offers **Check an external or network volume**. It reports the
largest measured folders and checks the mounted volume’s identity before
scanning, after scanning, and before opening it in Files. If macOS still shows
an ordinary folder at the former mount path after ejecting the volume, the
app asks the user to refresh the volume list.
