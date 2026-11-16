# Nuke Sweep 0.9.2 beta test

Use the [notarized 0.9.2 release](https://github.com/emacliam/nuke-sweep/releases/tag/v0.9.2). Record the macOS version, build number, whether Full Disk Access was granted, and the outcome of each task. Use a spare macOS account or test Mac with disposable files for cleanup tasks.

| Task | Evidence to record |
| --- | --- |
| Run the first check. Switch to Files or Developer while scanning, return to Cleanup, and stop the scan. Start it again and open the completed result from the menu bar. | Whether navigation and Stop responded, approximate completion time, and whether partial results were clear. |
| Open Developer and switch among caches, projects, and simulator devices. Review one disposable project’s generated output. | Whether each tab was easy to find, how long review took, and whether the review distinguished generated output from source files. Cancel the review if the selection includes anything unexpected. |
| In Personal Files, preview a disposable installer or recording. Select it, review the move, confirm, then restore it from History. | Which controls were easy to find, whether the file appeared in Trash, and whether it returned to its original location. |
| Enable weekly checks and automatic cleanup with dry run enabled. Leave Nuke Sweep running until a scheduled check occurs. | Whether the preview explained which locations passed review and whether those files remained in place. |
| On the disposable account only, disable dry run for a scheduled check with eligible idle caches. Use **Put everything back** from the resulting alert. | Whether the alert appeared, whether History matched the move, and whether each eligible item returned. |
| On a test Mac already near its low-storage threshold, enable the storage alert and allow macOS notifications. | Whether the alert arrived, whether its estimate matched Cleanup, and whether its review action opened a relevant result. |
| Open the desktop widget gallery after launching the installed app. Search for Nuke Sweep and add Storage. | Whether small and medium previews render, whether the placed widget shows a reading, and whether clicking it opens Files. |
| Run both Nuke Sweep actions from Shortcuts and try their Siri phrases. Navigate Personal Files by keyboard and VoiceOver. | Whether the actions run, whether the estimate states when it was measured, and where keyboard focus or spoken labels made the workflow hard to follow. |

For any failure, record the last action, what appeared, and whether retrying worked. Share screenshots of the test account and inspect any diagnostics before sending them so paths or filenames can be removed.

## Verification so far

On November 16, 2026, macOS registered the Developer ID signed 0.9.2 widget extension after the notarized app launched. WidgetKit identified build 13, then logged a descriptor cache purge and a reload database constraint error. Gallery visibility, rendering, and click navigation still need to be checked with 0.9.2 installed in Applications.

The installed Xcode listed 61 simulator devices, including 15 unavailable devices, and five runtime images. Its outdated-runtime dry run identified one image. This was a read-only command check. The Devices and Runtimes tabs still need a live visual check.
