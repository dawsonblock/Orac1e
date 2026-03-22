# Validation policy

Oracle validates every proposal after it returns from a worker.

Stages:
1. diff structure and policy checks
2. repo-local formatter and linter
3. targeted tests
4. optional broader build/test commands

Workers may perform advisory validation, but Oracle remains the final gate.
