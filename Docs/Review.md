# Phase 4 review and learning history

Weak points registered from listening or speaking retain their source lesson, text, reason, registration date, latest review date, review totals, success/failure totals, interval, and next due date. Duplicate registrations of the same text, source lesson, and reason are ignored.

Review answers use the replaceable `ReviewScheduling` contract in LearningCore. `Again` schedules the item after ten minutes; `Hard`, `Good`, and `Easy` use progressively longer intervals. Each answer and its next due date are written transactionally to SQLite. The current history screen reports total answers, active calendar days, the current consecutive-day practice streak, and items with at least three answers and 80% or better success ratio. Listening and speaking practice events also count toward active days and are stored with the source lesson when available. Mastery is a progress estimate from review answers, not a language proficiency score.

From a saved item, learners can play its short text, open the source lesson for the original listening and speaking practice, or delete the weak point. Deleting it cascades to its review history. The history screen lists review events and listening/speaking activity newest first. Deleting all learning data removes lessons, weak points, review events, and activity events.

Existing database payloads without a registration timestamp remain readable; the available `updatedAt` value is used as the best estimate of registration date. Review events continue in the existing `review_history` table. Version 2 adds the `study_history` table and date index without changing existing learning data.

## Verification

Docker package tests cover review and activity history round trips, weak-point filtering, deletion, replaceable scheduling, legacy payload decoding, mastery threshold, active-day count, and streak calculation. The iOS screen layout and interaction still require Simulator/device checks; Linux package tests do not validate SwiftUI behavior.
