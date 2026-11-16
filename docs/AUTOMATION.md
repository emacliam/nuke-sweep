# Scheduled scans

Files → Schedules includes scheduled folder measurements.

- Choose a folder and a frequency: hourly, daily or weekly.
- Schedules run only while Nuke Sweep is open. They pause when the Mac sleeps and when the app quits; there is no background launch agent.
- A completed scan is added through the same Growth-history path as a manual scan. Partial or access-limited scans are reported but not saved as complete history.
- Scheduled scans never select, move or delete files. Cleanup still requires the normal review.
- Each schedule can be enabled, disabled, run now, changed or removed.
- Only one scheduled scan runs at a time; Cancel stops the current measurement.
- Optional quiet hours pause due schedules until the window ends; manual Run now remains available.
- Optional finish notifications use macOS permission and contain only the folder name and result summary.
- Quiet hours and notification preferences are stored locally with the schedules.

The scheduler stores only the folder path, frequency, timestamps and a short result summary. It does not use AI and sends nothing over the network.

Tested model/store behavior:

- frequency intervals and next-run calculation;
- Codable round-tripping;
- add/toggle/frequency/remove persistence;
- duplicate folder updates instead of creating a second schedule;
- quiet-window evaluation across midnight and during the day;
- quiet-hours persistence;
- an end-to-end run-now scan of a real temporary folder, including result handoff and schedule timestamps.

The timer/full UI path is exercised manually; it is not a headless unit test.
