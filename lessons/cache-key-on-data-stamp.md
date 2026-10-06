# Key a cache on a data stamp, not on time alone

**Rule:** A cache that invalidates purely on a wall-clock schedule (for example, "refresh once per day at a fixed time") goes stale whenever the underlying data arrives later than that schedule assumes. Key the cache instead on a stamp that reflects the actual freshness of the source data (a last-updated timestamp, a data version, a row count checksum), so a late-arriving batch is detected and the cache is invalidated when the data changes, not only when the clock ticks.

**Why:** A time-only cache silently serves stale results whenever an upstream job runs late, with no error or signal that anything is wrong; the cache believes it is fresh because its timer says so, regardless of what the underlying data actually looks like.

**How to apply:** When adding or reviewing a cache, identify what field or signal actually marks the source data as changed, and key invalidation on that, falling back to a time-based check only as a secondary, coarser bound.
