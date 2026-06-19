# ADR 010: Semantic Retrieval First

## Decision

Code context is retrieved through semantic search (cocoindex) before worker engagement. The retrieval broker serves as the gateway for all code context, providing meaning-based search rather than simple text matching.

## Reason

Improves code relevance by understanding meaning, not just text. Reduces token consumption by providing focused context. Enables natural language queries for code search. Better alignment between retrieved context and actual code structure.

## Tradeoffs

- **Latency**: Semantic indexing adds startup overhead
- **Complexity**: Requires understanding embedding models
- **Coverage**: May miss edge cases in semantic matching

## Affected Modules

- `integration/retrieval_broker/` - retrieval orchestration
- `third_party/cocoindex-code/` - semantic code indexing

## Evidence

- [oracle_build_v5_analysis.md:40-48](../oracle_build_v5_analysis.md) - cocoindex responsibilities
- [build_blueprint.md:57-58](../../../docs/build_blueprint.md) - retrieval in flow

## Source

Oracle Build v5, improving context retrieval
