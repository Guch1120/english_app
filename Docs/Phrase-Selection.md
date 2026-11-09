# Listening phrase selection

When the English passage is visible, tap the first and last words to select an inclusive range for review. The original text between them, including punctuation and whitespace, is retained; selecting in reverse order works as well. A single tap selects one word. After a range is complete, the next tap starts a new selection. The text field remains editable, and an empty field registers the whole passage. Editing the passage resets any selection so a stale range cannot be saved against the revised text.

The selection operation is in LearningCore and does not depend on UI or inference. Docker tests cover source preservation, reverse order, single words and invalid bounds. A Simulator UI test exercises selection and review registration; iOS CI and physical-device accessibility remain separate evidence.
