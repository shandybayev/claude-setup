# A write path that replaces stored rows must guard against an empty upstream response

**Rule:** Any write path shaped as "fetch from upstream, then replace what is stored with the result" must treat an empty or error response from upstream as "do nothing," never as "the new truth is empty." Without that guard, a transient upstream failure (a timeout, a rate limit, an empty page) erases previously good data instead of leaving it alone.

**Why:** A replace-style write that trusts every response as authoritative will happily overwrite a full table with zero rows the moment the upstream call comes back empty for any reason, destroying real data that an append-only or merge-style write would have left intact.

**How to apply:** Before replacing stored rows with a fetched result, check for a plausible non-empty response, or a success signal distinct from "the call returned without throwing." When a real empty state is possible and expected, make that case explicit and distinguishable from an upstream failure, instead of treating all empty responses alike.
