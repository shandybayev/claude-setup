# A shared database session must be rolled back after a timeout or error, before reuse

**Rule:** After a query times out or errors on a database session or connection that is shared or reused (pooled connections, a long-lived session object), roll the session back explicitly before using it again. A session left in a failed transaction state will reject every subsequent query with the same underlying error, even unrelated ones, until it is rolled back.

**Why:** Many database client libraries leave a session in an aborted-transaction state after an error, and will refuse all further statements on that session with a generic "current transaction is aborted" style error until a rollback happens. This can look like a cascading or intermittent outage when it is really one unhandled error poisoning every later query on the same session.

**How to apply:** Wrap database calls that use a shared or pooled session in error handling that explicitly rolls back the session on any failure (timeout included) before returning it to a pool or reusing it, and confirm this behavior with a test that forces an error and then issues an unrelated query on the same session afterward.
