from integration.tool_sdk.harness import run_harness
import json

if __name__ == "__main__":
    print(json.dumps(run_harness("integration/tools"), indent=2))
