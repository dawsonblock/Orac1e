import logging
import concurrent.futures
import threading
from typing import List, Dict, Any
from integration.workers_planner import coding_planner_execute

logger = logging.getLogger(__name__)

class ParallelOrchestrator:
    """
    Build v7 Parallel Execution Engine.
    Orchestrates multiple coding planners with semaphore throttling.
    """
    def __init__(self, max_workers: int = 4, per_worker_semaphore: int = 2):
        self.max_workers = max_workers
        self.executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=max_workers
        )
        # Limit the number of truly concurrent heavy-weight LLM calls
        self.semaphore = threading.Semaphore(per_worker_semaphore)

    def _throttled_execute(self, task: str, repo_path: str) -> Dict[str, Any]:
        with self.semaphore:
            return coding_planner_execute(task, repo_path)

    def execute_batch(self, tasks: List[Dict[str, str]]) -> List[Dict[str, Any]]:
        """
        Executes a batch of coding tasks in parallel.
        """
        futures = []
        for t in tasks:
            futures.append(
                self.executor.submit(
                    self._throttled_execute, 
                    t["task"], 
                    t["repo_path"]
                )
            )
        
        results = []
        for future in concurrent.futures.as_completed(futures):
            try:
                # results is a list of standardized proposals
                res = future.result()
                results.append(res)
            except Exception as e:
                logger.error(f"Parallel task failed: {e}")
                results.append({"success": False, "error": str(e)})
        
        return results

def run_parallel_session(tasks: List[Dict[str, str]]):
    orchestrator = ParallelOrchestrator()
    results = orchestrator.execute_batch(tasks)
    for i, res in enumerate(results):
        status = "✅" if res.get("success") else "❌"
        print(f"Task {i+1}: {status} - {res.get('file', 'N/A')}")
    return results
