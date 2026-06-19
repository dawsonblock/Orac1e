import React from 'react';

export function RunDetail(props: {
  run?: { id: string; status: string; task: string; repoPath: string };
}) {
  const { run } = props;
  if (!run) return <div>No run selected.</div>;

  return (
    <div>
      <h3>Run Detail</h3>
      <div><strong>ID:</strong> {run.id}</div>
      <div><strong>Status:</strong> {run.status}</div>
      <div><strong>Repo:</strong> {run.repoPath}</div>
      <pre>{run.task}</pre>
    </div>
  );
}
