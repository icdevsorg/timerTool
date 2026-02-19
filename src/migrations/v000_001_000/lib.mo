import MigrationTypes "../types";
import Array "mo:core/Array";
import v0_1_0 "types";
import Nat "mo:core/Nat";
import Debug "mo:core/Debug";
import Map "mo:core/Map";
import Iter "mo:core/Iter";

module {

  public func upgrade(_prevmigration_state: MigrationTypes.State, args: MigrationTypes.Args, _caller: Principal, _canister : Principal): MigrationTypes.State {

    Debug.print("in upgrade " # debug_show(args));

    let (
      timeTree : v0_1_0.TimeTree,
      actionIdIndex,
      lastExecutionTime : v0_1_0.Time,
      expectedExecutionTime : v0_1_0.Time,
      nextActionId : Nat,
      lastActionIdReported: ?Nat,
      nextCycleActionId: ?Nat,
      lastCycleReport: ?Nat,
      maxExecutions: Nat
    ) = switch(args){
      case(null){
        (
          Map.empty<v0_1_0.ActionId, v0_1_0.Action>(), 
          Map.empty<Nat, Nat>(),
          0, 
          0,
          0,
          null,
          null,
          null,
          10);
      };
      case(?val){
        (
          Map.fromIter<v0_1_0.ActionId, v0_1_0.Action>(val.initialTimers.vals(), v0_1_0.ActionIdCompare),
          Map.fromIter<Nat, Nat>(Array.map<(v0_1_0.ActionId, v0_1_0.Action), (Nat, Nat)>(val.initialTimers, func(x: (v0_1_0.ActionId, v0_1_0.Action)) : (Nat, Nat){(x.0.id, x.0.time)}).vals(), Nat.compare),
          val.lastExecutionTime,
          val.expectedExecutionTime,
          val.nextActionId,
          val.lastActionIdReported,
          val.nextCycleActionId,
          val.lastCycleReport,
          switch(val.maxExecutions){
            case(?maxExecutions) maxExecutions;
            case(null) 10;
          }
        )
      };
    };


    let state : v0_1_0.State = {
      timeTree : v0_1_0.TimeTree = timeTree;
      actionIdIndex = actionIdIndex;
      var nextTimer = null;
      var lastExecutionTime = lastExecutionTime;
      var expectedExecutionTime = ?expectedExecutionTime;
      var maxExecutions = maxExecutions;
      var timerLock = null;
      var nextActionId = nextActionId;
      var maxExecutionDelay = 5 * 60 * 1_000_000_000; //5 minutes
      var lastActionIdReported = lastActionIdReported;
      var lastCycleReport = lastCycleReport;
      var nextCycleActionId = nextCycleActionId;
    };

    return #v0_1_0(#data(state));
  };

};