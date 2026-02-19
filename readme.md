# Timer Tool

A robust timer scheduling library for Motoko projects on the Internet Computer. Schedule timer events with arguments that automatically recover after upgrades.

## Features

- Schedule timer events with custom parameters
- Synchronous and asynchronous action support
- Automatic timer reconstitution after upgrades
- Safety timers for trap recovery
- ICRC-85 OVS cycle sharing integration
- Automatic initialization via ClassPlus

## Installation

```bash
mops install timer-tool
```

## Quick Start

Timer Tool uses a **mixin pattern** for easy integration. Include the mixin in your actor and it handles all state management and initialization automatically.

```motoko
import TT "mo:timer-tool";
import TTMixin "mo:timer-tool/TimerToolMixin";
import ClassPlus "mo:class-plus";
import Principal "mo:base/Principal";
import Star "mo:star/star";

shared ({ caller = _owner }) persistent actor class MyCanister() = this {

  transient let canisterId = Principal.fromActor(this);
  transient let classPlus = ClassPlus.ClassPlusInitializationManager<system>(_owner, canisterId, true);

  // Include the TimerTool mixin
  include TTMixin({
    config = {
      org_icdevs_class_plus_manager = classPlus;
      args = null;
      pullEnvironment = ?(func() : TT.Environment {
        {
          advanced = null;
          syncUnsafe = null;
          reportExecution = null;
          reportError = null;
          reportBatch = null;
        };
      });
      onInitialize = ?(func(tt: TT.TimerTool) : async* () {
        // Register your handlers here
        tt.registerExecutionListenerSync(?"myTask", handleMyTask);
      });
    };
    caller = _owner;
    canisterId = canisterId;
  });

  // Your handler
  private func handleMyTask<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    // Decode params and process
    let ?data : ?Nat = from_candid(action.params) else return id;
    // Do work...
    id;
  };

  // Schedule a task
  public shared func scheduleTask(executeAt: Nat, data: Nat) : async Nat {
    let actionId = org_icdevs_timer_tool.setActionSync<system>(executeAt, {
      actionType = "myTask";
      params = to_candid(data);
    });
    actionId.id;
  };
};
```

That's it! The mixin:
- Manages stable state automatically
- Initializes timers on deploy/upgrade
- Exposes `org_icdevs_timer_tool` for scheduling actions

## Core Concepts

### Actions

An action is a scheduled task with:
- **time**: When to execute (nanoseconds UTC)
- **actionType**: Namespace string for routing to handlers
- **params**: Candid-encoded blob of custom data

### Sync vs Async Actions

**Sync actions** execute immediately and can't call other canisters:
```motoko
org_icdevs_timer_tool.setActionSync<system>(time, { actionType = "sync"; params = ... });
```

**Async actions** can await inter-canister calls but need a timeout:
```motoko
org_icdevs_timer_tool.setActionASync<system>(time, { actionType = "async"; params = ... }, timeout);
```

### Handlers

Register handlers to process actions by type:

```motoko
// Sync handler
tt.registerExecutionListenerSync(?"myTask", func<system>(id, action) : TT.ActionId {
  // Process and return id
  id;
});

// Async handler  
tt.registerExecutionListenerAsync(?"myAsyncTask", func<system>(id, action) : async* Star.Star<TT.ActionId, TT.Error> {
  let result = await someCanister.call();
  #awaited(id);
});

// Default handler (null namespace catches unmatched types)
tt.registerExecutionListenerSync(null, defaultHandler);
```

## API Reference

### Scheduling

```motoko
// Schedule sync action
setActionSync<system>(time: Nat, action: ActionRequest) : ActionId

// Schedule async action with timeout
setActionASync<system>(time: Nat, action: ActionRequest, timeout: Nat) : ActionId

// Cancel a scheduled action
cancelAction<system>(actionId: Nat) : ?Nat
```

### Types

```motoko
type ActionId = { time: Nat; id: Nat };
type ActionRequest = { actionType: Text; params: Blob };
type Action = { actionType: Text; params: Blob; aSync: ?Nat; retries: Nat };

type ExecutionHandler = <system>(ActionId, Action) -> ActionId;
type ExecutionAsyncHandler = <system>(ActionId, Action) -> async* Star.Star<ActionId, Error>;
```

### Environment Callbacks

Configure callbacks via `pullEnvironment`:

```motoko
type Environment = {
  advanced: ?{ icrc85: ?ICRC85Config };  // OVS cycle sharing config
  syncUnsafe: ?Bool;                      // Skip safety timer (dangerous)
  reportExecution: ?((ExecutionReport) -> Bool);  // Called after success
  reportError: ?((ErrorReport) -> ?Nat);          // Return new time to retry
  reportBatch: ?(([(ActionId, Action)]) -> async* ());
};
```

### Stats

```motoko
let stats = org_icdevs_timer_tool.getStats();
// stats.timers - pending action count
// stats.nextActionId - next ID to assign
// stats.maxExecutions - batch limit (default: 10)
// stats.cycles - canister balance
```

## Error Handling

Timer Tool uses safety timers to recover from traps:

1. Before each execution, a safety timer is scheduled
2. If the handler traps, the safety timer fires
3. `reportError` is called (if configured)
4. Return a new time to reschedule, or `null` to cancel

```motoko
reportError = ?(func(report: TT.ErrorReport) : ?Nat {
  if (report.action.1.retries < 3) {
    // Retry in 1 minute
    ?(Int.abs(Time.now()) + 60_000_000_000);
  } else {
    null; // Give up
  };
});
```

## Recurring Timers

Use `reportExecution` to reschedule:

```motoko
reportExecution = ?(func(report: TT.ExecutionReport) : Bool {
  if (report.action.1.actionType == "recurring") {
    ignore org_icdevs_timer_tool.setActionSync<system>(
      Int.abs(Time.now()) + 3600_000_000_000,  // 1 hour
      { actionType = "recurring"; params = report.action.1.params }
    );
  };
  false;
});
```

## Batch Execution

When multiple actions are past-due, they execute in batches limited by `maxExecutions` (default: 10). To change:

```motoko
org_icdevs_timer_tool.getState().maxExecutions := 20;
```

## ICRC-85 Open Value Sharing

This library implements [ICRC-85 Open Value Sharing](https://github.com/icdevsorg/ovs-ledger/blob/main/icrc85.md) to support sustainable open-source development on the Internet Computer.

### Default Behavior

By default, Timer Tool donates a small portion of cycles to ICDevs.org to fund continued development. This donation is voluntary:

| Parameter | Value |
|-----------|-------|
| **Base Amount** | 1 XDR (~1T cycles) per month |
| **Activity Bonus** | +1 XDR per 100,000 timer actions |
| **Maximum** | 10 XDR per sharing period |
| **Grace Period** | 7 days after initial deploy |
| **Share Period** | Every 30 days |
| **Collector** | `q26le-iqaaa-aaaam-actsa-cai` (ICDevs OVS Ledger) |
| **Namespace** | `org.icdevs.supertimer` |


### Why OVS?

- **Sustainable Development**: Fund ongoing maintenance and improvements
- **Fair Distribution**: Libraries report usage, cycles are shared proportionally
- **Voluntary**: Full control to disable or redirect contributions
- **Transparent**: All transactions logged on the OVS Ledger (ICRC-3 compliant)

For more information, see the [ICRC-85 specification](https://github.com/icdevsorg/ovs-ledger/blob/main/icrc85.md).

## Testing

See `src/examples/MixinCanister.mo` for a complete example with tests.

```bash
cd pic && npm install
npx vitest run timerTool/mixin.test.ts
```

## Advanced: Direct Init Pattern

For advanced use cases requiring more control, you can use `TT.Init()` directly instead of the mixin. However, **the mixin is strongly recommended** as there should only be one TimerTool instance per canister:

```motoko
var timerState = TT.initialState();

transient let timerTool = TT.Init({
  org_icdevs_class_plus_manager = classPlus;
  initialState = timerState;
  args = null;
  pullEnvironment = ?(...);
  onInitialize = ?(...);
  onStorageChange = func(state: TT.State) { timerState := state; };
})();
```

Note: `TT.Init()` automatically calls `initialize<system>()` via ClassPlus - no manual initialization required.
