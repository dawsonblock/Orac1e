# Retrieval contracts

The retrieval broker accepts a normalized search request and returns ranked code results.

Request fields:
- `repo_name`
- `query`
- `top_k`
- optional `run_id`

Response fields:
- `status`
- `results[]` with `path`, `score`, `snippet`
- optional `error`
