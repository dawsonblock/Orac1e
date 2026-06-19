import React from 'react';

export type RunItem = {
  id: string;
  repoName: string;
  status: string;
  task: string;
};

export function RunList(props: {
  runs: RunItem[];
  selectedRunId?: string;
  onSelect: (runId: string) => void;
}) {
  const { runs, selectedRunId, onSelect } = props;
  return (
    <div>
      <h3>Runs</h3>
      <ul>
        {runs.map((run) => (
          <li key={run.id}>
            <button onClick={() => onSelect(run.id)} disabled={run.id === selectedRunId}>
              {run.status} · {run.repoName} · {run.task}
            </button>
          </li>
        ))}
      </ul>
    </div>
  );
}
