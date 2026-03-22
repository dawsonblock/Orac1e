import React from 'react';

export function DiffReview(props: { diff?: string }) {
  return (
    <div>
      <h3>Diff Review</h3>
      <pre style={{ whiteSpace: 'pre-wrap', overflowX: 'auto' }}>{props.diff || 'No diff.'}</pre>
    </div>
  );
}
