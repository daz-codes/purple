# Game state and content

`ShiftAttempt` concerns share the attempt's persisted attributes and append-only action log.
`Logged#acting_on` locks the attempt and checks whether a move is allowed. `Logged#record` writes
the action, reloads the attempt, and asks `Finishable` whether the inbox has cleared. New actions
must use these methods rather than writing the log or invalidating individual caches themselves.

| Concern | Depends on | Cached state cleared by `reload` |
| --- | --- | --- |
| Logged | Timed, Inbox, Finishable | `actions`, completed-action lookup |
| Inbox | Logged, Arrivals | arrivals and arrived messages |
| Reading | Logged, Inbox | current message |
| Notable | Logged, Flaggable | notes |
| Browsing | Logged, Inbox, Tab | current tab |
| Sharing | Identified, Notable, Browsing | Uses the concerns above |
| Finishable | Logged, Timed, Scorecard, ContentSnapshot | Builds each scorecard afresh |

Every `reload` override calls `super`, so all concern caches are cleared together. Secrets used
for message references and MFA are class caches; generated persona details are persisted and stay
fixed for the attempt. A new cache of mutable action state must participate in this reload chain.

Finished Blue attempts store their content in `result_content` in the completion transaction.
`ContentSnapshot` rebuilds a read-only graph of explicitly named model types for the scorecard and
debrief. Open attempts continue to use current content. The upgrade migration captures the content
available for existing finished attempts, preserving their recorded scores and XP; content already
overwritten before this migration cannot be reconstructed.

`Content::ShiftImport` owns the import transaction context: `@node`, `@shift`, `@messages`,
`@message_nodes`, `@story_links` and the technique catalogue. Its internal `PrivateDetails` and
`StoryLinks` modules group the sharing and narrative rules. They use the importer's field helpers
and error reporting, and run after the message records exist. `PrivateDetails` also uses
`StoryLinks#always_arrives_after?` to check when learned details become available. The importer's
existing tests cover these rules together and verify that invalid imports roll back.
