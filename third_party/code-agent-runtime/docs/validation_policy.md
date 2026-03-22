# Validation policy

The code agent validates in this order:

1. patch preflight
2. Python syntax check on changed files
3. targeted pytest selection

Targeted pytest selection now broadens beyond explicit issue tests.
It adds nearest matching tests for changed files and falls back to the first small batch of repository tests when no direct target is found.
