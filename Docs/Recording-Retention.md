# Recording retention

Settings defaults to retaining the latest recording across app restarts, preserving existing behavior and previously saved data. If the user turns the setting off, the latest recording remains available for replay and re-recognition during the current app session and is removed at the next app launch. New recordings continue to replace the previous one. The user can also explicitly delete the current recording in the speaking screen. Turning retention off does not delete immediately or guarantee deletion before the next launch; the UI states this timing.

The launch cleanup targets only the app's latest recording; it clears its lesson association after successful cleanup. An error during cleanup is surfaced as a storage preparation error rather than claiming deletion. RE-USE's derived temporary recording is handled separately by the existing startup cleanup. Both remain in protected, backup-excluded app storage.

Docker tests cover retaining, removing, repeat cleanup and leaving unrelated files intact. Simulator UI tests cover preference persistence and restore the default; real-device behavior and storage protection still need verification.
