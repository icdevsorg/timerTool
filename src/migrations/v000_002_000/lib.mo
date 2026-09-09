import MigrationTypes "../types";
import v0_1_0 "../v000_001_000/types";
import v0_2_0 "types";
import Map "mo:core/Map";
import Nat "mo:core/Nat";
import BTree "mo:stableheapbtreemap/BTree";
import OldMap "mo:map/Map";

module {

  /// 0.1.x layout (stableheapbtreemap TimeTree, mo:map actionIdIndex) -> mo:core Map for both.
  /// Every scalar is carried over untouched; only the containers are rebuilt.
  public func upgrade(prevmigration_state: MigrationTypes.State, _args: MigrationTypes.Args, _caller: Principal, _canister : Principal): MigrationTypes.State {
    let #v0_1_0(#data(old)) = prevmigration_state else return prevmigration_state;

    let timeTree = Map.empty<v0_2_0.ActionId, v0_2_0.Action>();
    for ((id, action) in BTree.entries<v0_1_0.ActionId, v0_1_0.Action>(old.timeTree)) {
      Map.add(timeTree, v0_2_0.ActionIdCompare, id, action);
    };
    let actionIdIndex = Map.empty<Nat, v0_2_0.Time>();
    for ((id, time) in OldMap.entries<Nat, v0_1_0.Time>(old.actionIdIndex)) {
      Map.add(actionIdIndex, Nat.compare, id, time);
    };

    let state : v0_2_0.State = {
      timeTree;
      actionIdIndex;
      var nextTimer = old.nextTimer;
      var lastExecutionTime = old.lastExecutionTime;
      var expectedExecutionTime = old.expectedExecutionTime;
      var maxExecutions = old.maxExecutions;
      var timerLock = old.timerLock;
      var nextActionId = old.nextActionId;
      var maxExecutionDelay = old.maxExecutionDelay;
      var lastActionIdReported = old.lastActionIdReported;
      var lastCycleReport = old.lastCycleReport;
      var nextCycleActionId = old.nextCycleActionId;
    };
    #v0_2_0(#data(state));
  };
};
