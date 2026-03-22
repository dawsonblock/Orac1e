# GitHub App permissions

Recommended minimum permissions for the bounded code agent:

- metadata: read
- contents: read/write
- pull requests: read/write
- issues: read/write
- checks: write

The runtime now also reads branch information to summarize branch protection before opening a draft PR.
It still does not merge, approve, or bypass branch protection.
