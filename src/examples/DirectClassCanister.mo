/// DirectClassCanister - Example canister using direct TT.Init() pattern
///
/// This canister demonstrates direct usage of TimerTool without mixin,
/// following the same pattern as the main test canister.

import TT "../lib";
import Principal "mo:core/Principal";
import Int "mo:core/Int";
import Runtime "mo:core/Runtime";
import Time "mo:core/Time";
import D "mo:core/Debug";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
import Star "mo:star/star";
import ClassPlus "mo:class-plus";

shared (deployer) persistent actor class DirectClassCanister() = this {

  // ============ State ============
  
  var executedActions : Nat = 0;
  var errorCount : Nat = 0;
  var lastExecutedNamespace : Text = "";
  var lastExecutedParams : Blob = Blob.fromArray([]);
  var executionHistory : [(Nat, Text, Nat)] = []; // (timestamp, namespace, count)
  
  // Counter for testing - incremented by "inc" actions
  var counter : Nat = 0;

  // ============ TimerTool State ============
  
  var tt_migration_state : TT.State = TT.Migration.migration.initialState;

  // ============ ClassPlus Setup ============
  
  transient let canisterId = Principal.fromActor(this);
  transient let initManager = ClassPlus.ClassPlusInitializationManager<system>(deployer.caller, canisterId, true);

  // ============ Handlers ============

  /// Sync handler: increment counter
  private func handleIncSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("DirectClassCanister: handleIncSync " # debug_show(action));
    let amt : ?Nat = from_candid(action.params);
    switch(amt) {
      case(?val) { counter += val; };
      case(null) { counter += 1; };
    };
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  /// Sync handler: intentionally trap for testing recovery
  private func handleTrapSync<system>(_id: TT.ActionId, _action: TT.Action) : TT.ActionId {
    D.print("DirectClassCanister: handleTrapSync - about to trap!");
    Runtime.trap("Intentional trap for testing");
  };

  /// Sync handler: do nothing (for testing scheduling)
  private func handleNoopSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("DirectClassCanister: handleNoopSync");
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  /// Default sync handler for unknown namespaces
  private func handleDefaultSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("DirectClassCanister: handleDefaultSync for " # action.actionType);
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  /// Async handler: increment counter
  private func handleIncAsync<system>(id: TT.ActionId, action: TT.Action) : async* Star.Star<TT.ActionId, TT.Error> {
    D.print("DirectClassCanister: handleIncAsync " # debug_show(action));
    let amt : ?Nat = from_candid(action.params);
    switch(amt) {
      case(?val) { counter += val; };
      case(null) { counter += 1; };
    };
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    #awaited(id);
  };

  /// Async handler: intentionally trap
  private func handleTrapAsync<system>(_id: TT.ActionId, _action: TT.Action) : async* Star.Star<TT.ActionId, TT.Error> {
    D.print("DirectClassCanister: handleTrapAsync - about to trap!");
    Runtime.trap("Intentional async trap for testing");
  };

  /// Async handler: delay and return (for testing async flow)
  private func handleDelayAsync<system>(id: TT.ActionId, action: TT.Action) : async* Star.Star<TT.ActionId, TT.Error> {
    D.print("DirectClassCanister: handleDelayAsync");
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    #awaited(id);
  };

  // ============ Environment Callbacks ============

  private func reportExecution(execInfo: TT.ExecutionReport) : Bool {
    D.print("DirectClassCanister: reportExecution " # debug_show(execInfo.action.1.actionType));
    executedActions += 1;
    executionHistory := Array.concat(executionHistory, [(Int.abs(Time.now()), execInfo.action.1.actionType, executedActions)]);
    false; // Don't stop processing
  };

  private func reportError(errInfo: TT.ErrorReport) : ?Nat {
    D.print("DirectClassCanister: reportError " # debug_show(errInfo));
    errorCount += 1;
    
    // For "delay_retry" actions, reschedule 1 minute later
    if (errInfo.action.1.actionType == "delay_retry") {
      return ?(Int.abs(Time.now()) + 60_000_000_000);
    };
    
    null;
  };

  private func reportBatch(actions: [(TT.ActionId, TT.Action)]) : async* () {
    D.print("DirectClassCanister: reportBatch with " # Nat.toText(actions.size()) # " actions");
  };

  // ============ TimerTool Direct Init ============

  D.print("DirectClassCanister: about to call init");
  
  transient let timerTool = TT.Init({
    org_icdevs_class_plus_manager = initManager;
    initialState = tt_migration_state;
    args = null;
    pullEnvironment = ?(func() : TT.Environment {
      D.print("DirectClassCanister: pulling environment");
      {      
        advanced = null;
        reportExecution = ?reportExecution;
        reportError = ?reportError;
        syncUnsafe = null;
        reportBatch = ?reportBatch;
      };
    });
    onInitialize = ?(func(tt: TT.TimerTool) : async* () {
      D.print("DirectClassCanister: TimerTool initialized");
      tt.initialize<system>();
      // Register our handlers
      tt.registerExecutionListenerSync(?"inc", handleIncSync);
      tt.registerExecutionListenerSync(?"trap", handleTrapSync);
      tt.registerExecutionListenerSync(?"noop", handleNoopSync);
      tt.registerExecutionListenerAsync(?"inc_async", handleIncAsync);
      tt.registerExecutionListenerAsync(?"trap_async", handleTrapAsync);
      tt.registerExecutionListenerAsync(?"delay_async", handleDelayAsync);
      // Default handler for unknown namespaces
      tt.registerExecutionListenerSync(null, handleDefaultSync);
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

  /// Set counter value (for testing)
  public shared func setCounter(val: Nat) : async () {
    counter := val;
  };

  /// Get executed action count
  public shared query func getExecutedCount() : async Nat {
    executedActions;
  };

  /// Get error count
  public shared query func getErrorCount() : async Nat {
    errorCount;
  };

  /// Get last executed namespace
  public shared query func getLastExecuted() : async (Text, Blob) {
    (lastExecutedNamespace, lastExecutedParams);
  };

  /// Get execution history
  public shared query func getExecutionHistory() : async [(Nat, Text, Nat)] {
    executionHistory;
  };

  /// Reset test state
  public shared func resetTestState() : async () {
    executedActions := 0;
    errorCount := 0;
    lastExecutedNamespace := "";
    lastExecutedParams := Blob.fromArray([]);
    executionHistory := [];
    counter := 0;
  };

  /// Force initialization (for testing)
  public shared func initialize() : async () {
    timerTool().initialize<system>();
  };

  /// Get current time in nanoseconds
  public shared query func getTime() : async Nat {
    Int.abs(Time.now());
  };

  D.print("DirectClassCanister: Actor initialized");
};
