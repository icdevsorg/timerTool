export const idlFactory = ({ IDL }) => {
  const Time = IDL.Nat;
  const ActionId = IDL.Record({ 'id' : IDL.Nat, 'time' : Time });
  const Action = IDL.Record({
    'aSync' : IDL.Opt(IDL.Nat),
    'actionType' : IDL.Text,
    'params' : IDL.Vec(IDL.Nat8),
    'retries' : IDL.Nat,
  });
  const ActionDetail = IDL.Tuple(ActionId, Action);
  const TimerId = IDL.Nat;
  const Stats = IDL.Record({
    'timers' : IDL.Nat,
    'maxExecutions' : IDL.Nat,
    'minAction' : IDL.Opt(ActionDetail),
    'cycles' : IDL.Nat,
    'nextActionId' : IDL.Nat,
    'nextTimer' : IDL.Opt(TimerId),
    'expectedExecutionTime' : IDL.Opt(Time),
    'lastExecutionTime' : Time,
  });
  const OVSTestCanisterV2 = IDL.Service({
    'addAsyncAction' : IDL.Func(
        [IDL.Nat, IDL.Text, IDL.Opt(IDL.Nat), IDL.Nat],
        [ActionId],
        [],
      ),
    'addSyncAction' : IDL.Func(
        [IDL.Nat, IDL.Text, IDL.Opt(IDL.Nat)],
        [ActionId],
        [],
      ),
    'cancelAction' : IDL.Func([IDL.Nat], [IDL.Opt(IDL.Nat)], []),
    'getCounter' : IDL.Func([], [IDL.Nat], ['query']),
    'getErrorCount' : IDL.Func([], [IDL.Nat], ['query']),
    'getExecutedCount' : IDL.Func([], [IDL.Nat], ['query']),
    'getExecutionHistory' : IDL.Func(
        [],
        [IDL.Vec(IDL.Tuple(IDL.Nat, IDL.Text, IDL.Nat))],
        ['query'],
      ),
    'getOVSStats' : IDL.Func(
        [],
        [
          IDL.Record({
            'nextCycleActionId' : IDL.Opt(IDL.Nat),
            'lastCycleShareTime' : IDL.Nat,
            'lastActionIdReported' : IDL.Opt(IDL.Nat),
            'cycleShareCount' : IDL.Nat,
            'lastCycleReport' : IDL.Opt(IDL.Nat),
            'cyclesBalance' : IDL.Nat,
          }),
        ],
        ['query'],
      ),
    'getStats' : IDL.Func([], [Stats], ['query']),
    'getTime' : IDL.Func([], [IDL.Nat], ['query']),
    'getTimerState' : IDL.Func(
        [],
        [
          IDL.Record({
            'nextCycleActionId' : IDL.Opt(IDL.Nat),
            'nextActionId' : IDL.Nat,
            'lastActionIdReported' : IDL.Opt(IDL.Nat),
            'lastCycleReport' : IDL.Opt(IDL.Nat),
          }),
        ],
        ['query'],
      ),
    'getUpgradeCount' : IDL.Func([], [IDL.Nat], ['query']),
    'incrementUpgradeCount' : IDL.Func([], [], []),
    'initialize' : IDL.Func([], [], []),
    'resetTestState' : IDL.Func([], [], []),
    'updateCollector' : IDL.Func([IDL.Opt(IDL.Principal)], [], []),
    'updateOVSPeriod' : IDL.Func([IDL.Nat], [], []),
    'version' : IDL.Func([], [IDL.Text], ['query']),
  });
  return OVSTestCanisterV2;
};
export const init = ({ IDL }) => {
  return [
    IDL.Opt(
      IDL.Record({
        'period' : IDL.Opt(IDL.Nat),
        'collector' : IDL.Opt(IDL.Principal),
      })
    ),
  ];
};
