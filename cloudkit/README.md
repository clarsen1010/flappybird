# iCloud database layout

`schema.ckdb` is the Player record type of the container
`iCloud.com.clarsen1010.flappybird`, as deployed to Production on 2026-10-02
(copied from the CloudKit Console's deploy diff). Production only ever gains
fields; nothing here can be removed once deployed.

The game needs these indexes: `name` queryable (find a player by name),
`best` queryable + sortable (the EVERYONE list), `friends` queryable (who
added me), `___recordID` queryable (listing records in the Console). The
others were created automatically and are unused.

Permissions: anyone can read, a signed-in iCloud user can create, only the
creator can change or delete a record. Do not create a CloudKit web API
token for this container: without one, only builds signed by the team can
write.

## Waiting for the 5.3 deploy

5.3 adds seven fields that are **not in Production yet** (and so not in
`schema.ckdb`):

- `weekKey`, `monthKey` (STRING, queryable) and `weekBest`, `monthBest`
  (INT64, queryable + sortable): the WEEK and MONTH boards.
- `bestHard`, `bestInsane`, `bestImpossible` (INT64, queryable +
  sortable): each hard mode's all-time best and its board.

They must be deployed to Production before any 5.3 build talks to it
(TestFlight builds do). Without them a save that carries one fails whole
(no score is published, no name can be claimed), and the friends fetch
names the three hard fields. After the deploy, replace `schema.ckdb` with
the Console's text and fold this section into the one above.
