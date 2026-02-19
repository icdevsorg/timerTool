/// OVSTestCanisterV2 - Test canister V2 with OVS enabled for upgrade testing
///
/// This canister is a second version to test upgrade scenarios:
/// - Same functionality as V1 plus additional features
/// - Used to verify upgrades don't cause duplicate timers or OVS allocations

import TT "../lib";
import Principal "mo:core/Principal";
import Int "mo:core/Int";
import Time "mo:core/Time";
import D "mo:core/Debug";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
import Star "mo:star/star";
import ClassPlus "mo:class-plus";
import Cycles "mo:core/Cycles";

shared ({ caller = _owner }) persistent actor class OVSTestCanisterV2(_args: ?{
  collector: ?Principal;
  period: ?Nat;
}) = this {

  // Local type alias for ICRC-85 Map (same as TT's internal Map type)
  type ICRC85Map = [(Text, TT.Value)];

  // ============ Version Marker ============
  public query func version() : async Text {
    "v2"  // Changed from v1
  };

  // ============ V2 Specific Feature ============
  var upgradeCount : Nat = 0;

  public query func getUpgradeCount() : async Nat {
    upgradeCount;
  };

  public func incrementUpgradeCount() : async () {
    upgradeCount += 1;
  };

  // ============ State ============
  
  var executedActions : Nat = 0;
  var errorCount : Nat = 0;
  var lastExecutedNamespace : Text = "";
  var lastExecutedParams : Blob = Blob.fromArray([]);
  var executionHistory : [(Nat, Text, Nat)] = []; // (timestamp, namespace, params as nat)
  var cycleShareCount : Nat = 0;
  var lastCycleShareTime : Nat = 0;
  
  // Counter for testing - incremented by "inc" actions
  var counter : Nat = 0;

  // Collector principal - can be updated
  var collectorPrincipal : ?Principal = switch(_args) {
    case(?args) args.collector;
    case(null) null;
  };

  // OVS period override
  var ovsPeriod : Nat = switch(_args) {
    case(?args) {
      switch(args.period) {
        case(?p) p;
        case(null) 60_000_000_000;
      };
    };
    case(null) 60_000_000_000;
  };

  // ============ ClassPlus Setup ============
  
  transient let canisterId = Principal.fromActor(this);
  transient let org_icdevs_class_plus_manager = ClassPlus.ClassPlusInitializationManager<system>(_owner, canisterId, true);

  // ============ Handler Functions (defined BEFORE TT.Init) ============

  // ICRC85 Handler
  private func handleICRC85Share(events: [(Text, ICRC85Map)]) : () {
    D.print("OVSTestCanisterV2: handleICRC85Share called with " # debug_show(events));
    cycleShareCount += 1;
    lastCycleShareTime := Int.abs(Time.now());
    
    for ((namespace, _map) in events.vals()) {
      D.print("OVSTestCanisterV2: ICRC85 share for namespace: " # namespace);
    };
  };

  // Sync handler: increment counter
  private func handleIncSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("OVSTestCanisterV2: handleIncSync " # debug_show(action));
    let amt : ?Nat = from_candid(action.params);
    switch(amt) {
      case(?val) { counter += val; };
      case(null) { counter += 1; };
    };
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  // V2 New Feature: double sync handler (doubles the value)
  private func handleDoubleSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("OVSTestCanisterV2: handleDoubleSync " # debug_show(action));
    let amt : ?Nat = from_candid(action.params);
    switch(amt) {
      case(?val) { counter += val * 2; };
      case(null) { counter += 2; };
    };
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  // Sync handler: do nothing
  private func handleNoopSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("OVSTestCanisterV2: handleNoopSync");
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  // Default sync handler
  private func handleDefaultSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("OVSTestCanisterV2: handleDefaultSync for " # action.actionType);
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  // Async handler: increment counter
  private func handleIncAsync<system>(id: TT.ActionId, action: TT.Action) : async* Star.Star<TT.ActionId, TT.Error> {
    D.print("OVSTestCanisterV2: handleIncAsync " # debug_show(action));
    let amt : ?Nat = from_candid(action.params);
    switch(amt) {
      case(?val) { counter += val; };
      case(null) { counter += 1; };
    };
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    #awaited(id);
  };

  // Environment callback: report execution
  private func reportExecution(execInfo: TT.ExecutionReport) : Bool {
    D.print("OVSTestCanisterV2: reportExecution " # debug_show(execInfo.action.1.actionType));
    executedActions += 1;
    executionHistory := Array.concat(executionHistory, [(Int.abs(Time.now()), execInfo.action.1.actionType, executedActions)]);
    false;
  };

  // Environment callback: report error
  private func reportError(errInfo: TT.ErrorReport) : ?Nat {
    D.print("OVSTestCanisterV2: reportError " # debug_show(errInfo));
    errorCount += 1;
    null;
  };

  // ============ TimerTool Initialization (AFTER handler functions) ============

  var tt_migration_state : TT.State = TT.Migration.migration.initialState;

  transient let timerTool = TT.Init({
    org_icdevs_class_plus_manager = org_icdevs_class_plus_manager;
    initialState = tt_migration_state;
    args = null;
    pullEnvironment = ?(func() : TT.Environment {
      D.print("OVSTestCanisterV2: pulling environment");
      {      
        advanced = ?{
          icrc85 = ?{
            kill_switch = ?false;  // OVS ENABLED for testing
            handler = null;  // null handler = actual cycle transfer to collector
            period = ?ovsPeriod;
            initialWait = ?ovsPeriod;  // Use same as period for testing (short wait)
            asset = ?"cycles";
            platform = ?"icp";
            tree = null;
            collector = collectorPrincipal;
          };
        };
        reportExecution = ?reportExecution;
        reportError = ?reportError;
        syncUnsafe = null;
        reportBatch = null;
      };
    });
    onInitialize = ?(func(tt: TT.TimerTool) : async* () {
      D.print("OVSTestCanisterV2: TimerTool initialized");
      tt.registerExecutionListenerSync(?"inc", handleIncSync);
      tt.registerExecutionListenerSync(?"double", handleDoubleSync);  // V2 new handler
      tt.registerExecutionListenerSync(?"noop", handleNoopSync);
      tt.registerExecutionListenerSync(null, handleDefaultSync);
      tt.registerExecutionListenerAsync(?"inc_async", handleIncAsync);
    });
    onStorageChange = func(state: TT.State) {
      tt_migration_state := state;
    }
  });

  // ============ Public API ============

  /// Add a sync action
  public shared func addSyncAction(time: Nat, actionType: Text, paramsNat: ?Nat) : async TT.ActionId {
    let params = switch(paramsNat) {
      case(?val) to_candid(val);
      case(null) Blob.fromArray([]);
    };
    timerTool().setActionSync<system>(time, { actionType; params });
  };

  /// Add an async action
  public shared func addAsyncAction(time: Nat, actionType: Text, paramsNat: ?Nat, timeout: Nat) : async TT.ActionId {
    let params = switch(paramsNat) {
      case(?val) to_candid(val);
      case(null) Blob.fromArray([]);
    };
    timerTool().setActionASync<system>(time, { actionType; params }, timeout);
  };

  /// Cancel an action
  public shared func cancelAction(actionId: Nat) : async ?Nat {
    timerTool().cancelAction<system>(actionId);
  };

  /// Get timer stats
  public shared query func getStats() : async TT.Stats {
    timerTool().getStats();
  };

  /// Get counter value
  public shared query func getCounter() : async Nat {
    counter;
  };

  /// Get executed action count
  public shared query func getExecutedCount() : async Nat {
    executedActions;
  };

  /// Get error count
  public shared query func getErrorCount() : async Nat {
    errorCount;
  };

  /// Get execution history
  public shared query func getExecutionHistory() : async [(Nat, Text, Nat)] {
    executionHistory;
  };

  /// Get OVS-specific stats
  public shared query func getOVSStats() : async {
    cycleShareCount: Nat;
    lastCycleShareTime: Nat;
    nextCycleActionId: ?Nat;
    lastActionIdReported: ?Nat;
    lastCycleReport: ?Nat;
    cyclesBalance: Nat;
  } {
    let state = timerTool().getState();
    {
      cycleShareCount = cycleShareCount;
      lastCycleShareTime = lastCycleShareTime;
      nextCycleActionId = state.nextCycleActionId;
      lastActionIdReported = state.lastActionIdReported;
      lastCycleReport = state.lastCycleReport;
      cyclesBalance = Cycles.balance();
    };
  };

  /// Update collector
  public shared func updateCollector(collector: ?Principal) : async () {
    collectorPrincipal := collector;
  };

  /// Update OVS period (for testing shorter cycles)
  public shared func updateOVSPeriod(period: Nat) : async () {
    ovsPeriod := period;
  };

  /// Reset test state
  public shared func resetTestState() : async () {
    executedActions := 0;
    errorCount := 0;
    lastExecutedNamespace := "";
    lastExecutedParams := Blob.fromArray([]);
    executionHistory := [];
    counter := 0;
    cycleShareCount := 0;
    lastCycleShareTime := 0;
  };

  /// Force re-initialization (for testing)
  public shared func initialize() : async () {
    timerTool().initialize<system>();
  };

  /// Get current time in nanoseconds
  public shared query func getTime() : async Nat {
    Int.abs(Time.now());
  };

  /// Get raw timer state for debugging
  public shared query func getTimerState() : async {
    nextCycleActionId: ?Nat;
    lastCycleReport: ?Nat;
    lastActionIdReported: ?Nat;
    nextActionId: Nat;
  } {
    let state = timerTool().getState();
    {
      nextCycleActionId = state.nextCycleActionId;
      lastCycleReport = state.lastCycleReport;
      lastActionIdReported = state.lastActionIdReported;
      nextActionId = state.nextActionId;
    };
  };

  D.print("OVSTestCanisterV2: Actor initialized");
};
