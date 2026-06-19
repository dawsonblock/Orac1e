import React from 'react';

export function WorkerTrace(props: { worker: string; warnings: string[]; commands: string[] }) {
  return (
    <div>
      <h3>Worker Trace</h3>
      <div><strong>Worker:</strong> {props.worker}</div>
      <div>
        <strong>Warnings</strong>
        <ul>{props.warnings.map((item, index) => <li key={index}>{item}</li>)}</ul>
      </div>
      <div>
        <strong>Commands requested</strong>
        <ul>{props.commands.map((item, index) => <li key={index}>{item}</li>)}</ul>
      </div>
    </div>
  );
}
