import React from 'react';

export function ApprovalPanel(props: {
  onApprove: () => void;
  onReject: () => void;
  disabled?: boolean;
}) {
  return (
    <div>
      <h3>Approval</h3>
      <button onClick={props.onApprove} disabled={props.disabled}>Approve</button>
      <button onClick={props.onReject} disabled={props.disabled}>Reject</button>
    </div>
  );
}
