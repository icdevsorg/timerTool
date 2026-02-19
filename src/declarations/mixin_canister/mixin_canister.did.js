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
  const MixinCanister = IDL.Service({
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
    'getLastExecuted' : IDL.Func([], [IDL.Text, IDL.Vec(IDL.Nat8)], ['query']),
    'getStats' : IDL.Func([], [Stats], ['query']),
    'getTime' : IDL.Func([], [IDL.Nat], ['query']),
    'initialize' : IDL.Func([], [], []),
    'resetTestState' : IDL.Func([], [], []),
    'setCounter' : IDL.Func([IDL.Nat], [], []),
  });
  return MixinCanister;
};
export const init = ({ IDL }) => { return []; };
