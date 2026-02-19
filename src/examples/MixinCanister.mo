/// MixinCanister - Example canister using TimerToolMixin pattern
///
/// This canister demonstrates the mixin-based usage of timer-tool
/// and provides test endpoints for comprehensive verification.

import TT "../lib";
import TTMixin "../TimerToolMixin";
import Runtime "mo:core/Runtime";
import Principal "mo:core/Principal";
import Int "mo:core/Int";
import Time "mo:core/Time";
import D "mo:core/Debug";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Array "mo:core/Array";
import Star "mo:star/star";
import ClassPlus "mo:class-plus";

shared ({ caller = _owner }) persistent actor class MixinCanister() = this {

  // ============ State ============
  
  var executedActions : Nat = 0;
  var errorCount : Nat = 0;
  var lastExecutedNamespace : Text = "";
  var lastExecutedParams : Blob = Blob.fromArray([]);
  var executionHistory : [(Nat, Text, Nat)] = []; // (timestamp, namespace, params as nat)
  
  // Counter for testing - incremented by "inc" actions
  var counter : Nat = 0;

  // ============ ClassPlus Setup ============
  
  transient let canisterId = Principal.fromActor(this);
  transient let org_icdevs_class_plus_manager = ClassPlus.ClassPlusInitializationManager<system>(_owner, canisterId, true);

  // ============ TimerTool Mixin ============

  include TTMixin({
    config = {
      org_icdevs_class_plus_manager = org_icdevs_class_plus_manager;
      args = null;
      pullEnvironment = ?(func() : TT.Environment {
        D.print("MixinCanister: pulling environment");
        {      
          advanced = null;
          reportExecution = ?reportExecution;
          reportError = ?reportError;
          syncUnsafe = null;
          reportBatch = ?reportBatch;
        };
      });
      onInitialize = ?(func(tt: TT.TimerTool) : async* () {
        D.print("MixinCanister: TimerTool initialized");
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
    };
    caller = _owner;
    canisterId = canisterId;
  });

  // ============ Handlers ============

  /// Sync handler: increment counter
  private func handleIncSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("MixinCanister: handleIncSync " # debug_show(action));
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
    D.print("MixinCanister: handleTrapSync - about to trap!");
    Runtime.trap("Intentional trap for testing");
  };

  /// Sync handler: do nothing (for testing scheduling)
  private func handleNoopSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("MixinCanister: handleNoopSync");
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  /// Default sync handler for unknown namespaces
  private func handleDefaultSync<system>(id: TT.ActionId, action: TT.Action) : TT.ActionId {
    D.print("MixinCanister: handleDefaultSync for " # action.actionType);
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    id;
  };

  /// Async handler: increment counter
  private func handleIncAsync<system>(id: TT.ActionId, action: TT.Action) : async* Star.Star<TT.ActionId, TT.Error> {
    D.print("MixinCanister: handleIncAsync " # debug_show(action));
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
    D.print("MixinCanister: handleTrapAsync - about to trap!");
    Runtime.trap("Intentional async trap for testing");
  };

  /// Async handler: delay and return (for testing async flow)
  private func handleDelayAsync<system>(id: TT.ActionId, action: TT.Action) : async* Star.Star<TT.ActionId, TT.Error> {
    D.print("MixinCanister: handleDelayAsync");
    lastExecutedNamespace := action.actionType;
    lastExecutedParams := action.params;
    // This returns #awaited to indicate we did async work
    #awaited(id);
  };

  // ============ Environment Callbacks ============

  private func reportExecution(execInfo: TT.ExecutionReport) : Bool {
    D.print("MixinCanister: reportExecution " # debug_show(execInfo.action.1.actionType));
    executedActions += 1;
    executionHistory := Array.concat(executionHistory, [(Int.abs(Time.now()), execInfo.action.1.actionType, executedActions)]);
    false; // Don't stop processing
  };

  private func reportError(errInfo: TT.ErrorReport) : ?Nat {
    D.print("MixinCanister: reportError " # debug_show(errInfo));
    errorCount += 1;
    
    // For "delay_retry" actions, reschedule 1 minute later
    if (errInfo.action.1.actionType == "delay_retry") {
      return ?(Int.abs(Time.now()) + 60_000_000_000);
    };
    
    // For other errors, don't reschedule
    null;
  };

  private func reportBatch(actions: [(TT.ActionId, TT.Action)]) : async* () {
    D.print("MixinCanister: reportBatch with " # Nat.toText(actions.size()) # " actions");
  };

  // ============ Public API ============

  /// Add a sync action
  public shared func addSyncAction(time: Nat, actionType: Text, paramsNat: ?Nat) : async TT.ActionId {
    let params = switch(paramsNat) {
      case(?val) to_candid(val);
      case(null) Blob.fromArray([]);
    };
    org_icdevs_timer_tool.setActionSync<system>(time, { actionType; params });
  };

  /// Add an async action
  public shared func addAsyncAction(time: Nat, actionType: Text, paramsNat: ?Nat, timeout: Nat) : async TT.ActionId {
    let params = switch(paramsNat) {
      case(?val) to_candid(val);
      case(null) Blob.fromArray([]);
    };
    org_icdevs_timer_tool.setActionASync<system>(time, { actionType; params }, timeout);
  };

  /// Cancel an action
  public shared func cancelAction(actionId: Nat) : async ?Nat {
    org_icdevs_timer_tool.cancelAction<system>(actionId);
  };

  /// Get timer stats
  public shared query func getStats() : async TT.Stats {
    org_icdevs_timer_tool.getStats();
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

  /// Force re-initialization (for testing - normally automatic via ClassPlus)
  public shared func initialize() : async () {
    org_icdevs_timer_tool.initialize<system>();
  };

  /// Get current time in nanoseconds
  public shared query func getTime() : async Nat {
    Int.abs(Time.now());
  };

  D.print("MixinCanister: Actor initialized");
};
