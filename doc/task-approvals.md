← [README](../README.md) · [Partner guide](https://docs.mobilerun.ai/partners)

# Task approvals

The backend owns approval state and permissions. Your app provides callbacks
to your own authenticated backend; the SDK never handles an account API key.
**An API key must never ship in a Flutter app**, including build-time defines.
Your backend checks task ownership before fetching or deciding an approval.

```dart
final approvals = TaskApprovalController(
  taskId: taskId,
  fetchApproval: (id) => backend.fetchApproval(id),
  decide: (request) => backend.decideApproval(
    request.taskId,
    request.approvalId,
    request.decision.name, // "approve" or "deny"
  ),
  // Optional: change events are hints to fetch again, never authoritative data.
  // subscribe: (id, onChange) => backend.subscribe(id, onChange),
);

ListenableBuilder(
  listenable: approvals,
  builder: (context, _) {
    final state = approvals.state;
    return TaskApprovalCard(
      approval: state.approval,
      onDecide: approvals.decide,
      isPending: state.isDeciding,
      decision: state.decision,
      error: state.error?.toString(), // Or map the raw error to localized text.
      labels: const TaskApprovalLabels(approve: 'Allow', deny: 'Decline'),
      // device: yourDeviceWidget,
    );
  },
);

// Changing tasks invalidates every old fetch and decision result.
approvals.update(taskId: nextTaskId); // null disables fetching.
// An omitted enabled argument preserves the previous enabled state.
// Detach the push subscription and cancel polling when the owner goes away.
approvals.dispose();
```

The controller fetches immediately, then three seconds after each completed
fetch when no subscription is supplied or subscribing fails. A subscription
failure is reported through the controller error output. With a working subscription it fetches on
change hints, explicit `refetch()`, and after decisions. Newer overlapping
fetches win; task changes, disabling and disposal invalidate older results.
Both decision buttons are disabled only while deciding. The backend decides
whether an approval has expired; the isolated countdown is display-only and
stops ticking at expiry. Any decision failure (including HTTP 404/409 and an
integrator timeout/cancellation) shows an error and refetches. A successful
fetch clears fetch errors; a decision error remains until the next decision or
task change. Subscription and error-observer exceptions are guarded.

`PendingApproval` accepts unknown kinds. Valid `payment_card` details display
`label` (falling back to `credentialName`), `targetPackage`, and optional
`targetHost`. Other kinds and invalid details show the generic waiting title
with the same buttons. A null approval renders nothing. An optional `device`
slot stays mounted across the Details/Device switch and the 768-pixel wide
breakpoint. The app owns any surrounding sheet or dialog.

`actionsBuilder` receives one `ApprovalActionsState` with labels, deciding
state, and `onDecide`. Its default is `defaultApprovalActions`; a custom builder
can call that function to retain or wrap the defaults.
