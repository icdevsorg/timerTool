import Int "mo:core/Int";
import Array "mo:core/Array";
import List "mo:core/List";
import Blob "mo:core/Blob";
import Cycles "mo:core/Cycles";
import Debug "mo:core/Debug";
import Runtime "mo:core/Runtime";
import Error "mo:core/Error";
import Iter "mo:core/Iter";
import Text "mo:core/Text";
import Time "mo:core/Time";
import Option "mo:core/Option";
import Timer "mo:core/Timer";
import Nat "mo:core/Nat";
import Principal "mo:core/Principal";
import MigrationLib "./migrations";
import MigrationTypesLib "./migrations/types";
import OVS "./ovs";
import ClassPlusLib "mo:class-plus";



import Map "mo:core/Map";
import Order "mo:core/Order";

module {
  // Helper for scanLimit
  private func scanLimit<K,V>(map: Map.Map<K,V>, compare: (K,K)->Order.Order, lower: K, upper: K, _dir: {#fwd; #bwd}, limit: Nat) : { results: { vals: () -> Iter.Iter<(K,V)> } } {
      // Note: directory (fwd/bwd) is ignored in this implementation, assume fwd
      let iter = Map.entriesFrom(map, compare, lower);
      let resultList = List.empty<(K,V)>();
      var count = 0;
      
      label searchLoop while (true) {
          if (count >= limit) break searchLoop;
          switch(iter.next()) {
              case(null) break searchLoop;
              case(?val) {
                  if (Order.isGreater(compare(val.0, upper))) break searchLoop; 
                  List.add(resultList, val);
                  count += 1;
              };
          };
      };
      
      let resultArray = List.toArray(resultList);
      
      {
          results = {
              vals = func() = Iter.fromArray(resultArray);
          };
      };
  };

  public let MigrationTypes = MigrationTypesLib;

  public type TimerId =               MigrationTypes.Current.TimerId;
  public type Time =                  MigrationTypes.Current.Time;
  public type Action =                MigrationTypes.Current.Action;
  public type ActionRequest =                MigrationTypes.Current.ActionRequest;
  public type ActionId =              MigrationTypes.Current.ActionId;
  public type Error =                 MigrationTypes.Current.Error;
  public type TimeTree =              MigrationTypes.Current.TimeTree;
  public type CurrentState =          MigrationTypes.Current.State;
  public type Stats =                 MigrationTypes.Current.Stats;
  public type Environment =           MigrationTypes.Current.Environment;
  public type ActionDetail =          MigrationTypes.Current.ActionDetail;
  public type ErrorReport =           MigrationTypes.Current.ErrorReport;
  public type ExecutionReport =       MigrationTypes.Current.ExecutionReport;
  public type ExecutionItem =        MigrationTypes.Current.ExecutionItem;
  public type ExecutionHandler =      MigrationTypes.Current.ExecutionHandler;
  public type ExecutionAsyncHandler = MigrationTypes.Current.ExecutionAsyncHandler;

  public let ActionIdCompare =        MigrationTypes.Current.ActionIdCompare;

  public type State =                 MigrationTypes.State;
  public type Args =                  MigrationTypes.Args;
  public type InitArgs =              MigrationTypes.Args;
  public type InitArgList =           MigrationTypes.ArgList;
  public func initialState() : State {#v0_0_0(#data)};
  public let currentStateVersion = #v0_1_0(#id);
  public let Migration = MigrationLib;

  public let init = Migration.migrate;

  let OneMinute = 60_000_000_000;
  let OneDay =  86_400_000_000_000;



  // public let Map = Map; // Alias for code compatibility with renamed functions below

  public type Value = {
    #Nat : Nat;
    #Int : Int;
    #Blob : Blob;
    #Text : Text;
    #Array : [Value];
    #Map: [(Text, Value)];
  };

  public type ClassPlus = ClassPlusLib.ClassPlus<
    TimerTool, 
    State,
    InitArgs,
    Environment>;

  public func ClassPlusGetter(item: ?ClassPlus) : () -> TimerTool {
    ClassPlusLib.ClassPlusGetter<TimerTool, State, InitArgs, Environment>(item);
  };

  public type InitFunctionArgs = {
      org_icdevs_class_plus_manager: ClassPlusLib.ClassPlusInitializationManager;
      initialState: State;
      args : ?InitArgList;
      pullEnvironment : ?(() -> Environment);
      onInitialize: ?(TimerTool -> async*());
      onStorageChange : ((State) ->())
    };

  public let DefaultEnvironment = {
    advanced = null;
    syncUnsafe = null;
    reportExecution = null;
    reportError = null;
    reportBatch = null;
  };

  public func PullDefaultEnvironmentFunction() : Environment {
    DefaultEnvironment
  };

  public let PullDefaultEnvironment = ?PullDefaultEnvironmentFunction;

  public type MixinConfigArgs = {
      org_icdevs_class_plus_manager: ClassPlusLib.ClassPlusInitializationManager;
      args : ?InitArgList;
      pullEnvironment : ?(() -> Environment);
      onInitialize: ?(TimerTool -> async*());
    };

  public func Init(config : InitFunctionArgs) : () -> TimerTool {

      Debug.print("TimerTool Init");
      switch(config.pullEnvironment){
        case(?_val) {
          Debug.print("pull environment has value");
        };
        case(null) {
          Debug.print("pull environment is null");
        };
      };

      // Wrap onInitialize to ensure automatic initialization
      let wrappedOnInitialize = func(instance: TimerTool) : async* () {
        Debug.print("Auto-initializing TimerTool");
        instance.initialize<system>();
        
        switch(config.onInitialize){
          case(?cb) await* cb(instance);
          case(null) {};
        };
      };

      ClassPlusLib.ClassPlus<
        TimerTool, 
        State,
        InitArgList,
        Environment>({config with 
          constructor = TimerTool;
          onInitialize = ?wrappedOnInitialize;
        }).get;
    };


  public class TimerTool(stored: ?State, caller: Principal, canister: Principal, args: ?InitArgList, _environment: ?Environment, storageChanged: (State) -> ()){

    public let debug_channel = {
      var announce = true;
      var cycles = true;
    };

    Debug.print("TimerTool created by " # Principal.toText(caller) # " for canister " # Principal.toText(canister) # " with args " # debug_show(args) # " and environment " # debug_show(switch(_environment){ case(null) "null"; case(?_val) "set";}));

    public let environment : Environment = switch(_environment){
      case(?val) val;
      case(null) PullDefaultEnvironmentFunction();
    };

      /// Initializes the ledger state with either a new state or a given state for migration. 
      /// This setup process involves internal data migration routines.
      var state : CurrentState = do {
        let #v0_1_0(#data(foundState)) = init(
          switch(stored){
            case(null) initialState();
            case(?val) val;
          }, currentStateVersion, args, caller, canister) else Runtime.trap("TimerTool Not in final state after migration - " # debug_show(currentStateVersion));
        foundState;
      };

      storageChanged(#v0_1_0(#data(state)));

      private let executionListeners = Map.empty<Text, ExecutionItem>();

      //q26le-iqaaa-aaaam-actsa-cai
      var collector : Text = "q26le-iqaaa-aaaam-actsa-cai";

      public func getState() : CurrentState {
       
        return state;
      };

      public func getEnvironment() : Environment {
        return environment;
      };

      public func setCollector(req: Text) : () {
        let _test = Principal.fromText(req);
        collector := req;
      };

      public func setActionSync<system>(time: Time, action: ActionRequest) : ActionId {
        ensureInit<system>();
        debug if (debug_channel.announce) Debug.print("setting action sync " # debug_show(action));
        let actionId = {time : Time = time; id = state.nextActionId} : ActionId;
        addAction(actionId, {action with 
          aSync = null;
          retries = 0;});
        scheduleNextTimer<system>();
        actionId;
      };


      public func setActionASync<system>(time: Time, action: ActionRequest, timeout: Nat) : ActionId {
        ensureInit<system>();
        debug if (debug_channel.announce) Debug.print("setting action async " # debug_show(action));
        let actionId = {time : Time = time; id = state.nextActionId} : ActionId;
        addAction(actionId, {action with 
          aSync = ?timeout;
          retries = 0;});
        scheduleNextTimer<system>();
        actionId;
      };

      private func addAction(actionId: ActionId, action : Action){
        Map.add(state.timeTree, ActionIdCompare, actionId , action);
        state.nextActionId := state.nextActionId + 1;
        Map.add(state.actionIdIndex, Nat.compare, actionId.id, actionId.time);
      };

      private func scheduleNextTimer<system>() {
        debug if (debug_channel.announce) Debug.print("TIMERTOOL  ----  scheduling next timer");
        let ?nextTime = Map.minEntry(state.timeTree) else{
          state.expectedExecutionTime := null;
          state.nextTimer := null;
          return;
        };

         debug if (debug_channel.announce) Debug.print("TIMERTOOL  ----  nextTime" # debug_show(nextTime));

        let now = get_time();
         
        let duration = if(nextTime.0.time > now){
          Nat.sub(nextTime.0.time,Int.abs(Time.now()));
        } else {
          0;
        };

        debug if (debug_channel.announce) Debug.print("TIMERTOOL  ----   duration " # debug_show(duration));

        switch(state.nextTimer){
          case(?timerId) {
            debug if (debug_channel.announce) Debug.print("TIMERTOOL  ----  cancelling timer" # debug_show(timerId));
            Timer.cancelTimer(timerId);
          };
          case(null) {};
        };
       
        state.nextTimer := ?Timer.setTimer<system>(#nanoseconds(duration), executeActions);
        state.expectedExecutionTime := ?(now + duration);

        debug if (debug_channel.announce) Debug.print("TIMERTOOL  ----   nextTimer " # debug_show(state.nextTimer));

        debug if (debug_channel.announce) Debug.print("TIMERTOOL  ----   scheduled next timer end " # debug_show(state.nextTimer));
          
      };

      public type ShareCycleError = {
        #NotEnoughCycles: (Nat, Nat);
        #CustomError: {
          code: Nat;
          message: Text;
        };
      };

      private func shareCycles2<system>() : async (){

        let lastReportId = switch(state.lastActionIdReported){
          case(?val) val;
          case(null) 0;
        };

        let actions = if(state.nextActionId > lastReportId){
          Nat.sub(state.nextActionId, lastReportId);
        } else {1;};

        var cyclesToShare = 1_000_000_000_000; //1 XDR

        if(actions > 0){
          let additional = Nat.div(actions, 100000);
          cyclesToShare := cyclesToShare + (additional * 1_000_000_000_000);
          if(cyclesToShare > 100_000_000_000_000) cyclesToShare := 100_000_000_000_000;
        };

        debug if (debug_channel.cycles) Debug.print("should share cycles" # debug_show(cyclesToShare));

        try{
          await* OVS.shareCycles<system>({
            environment = do?{environment.advanced!.icrc85!};
            namespace = "org.icdevs.icrc85.supertimer";
            actions = actions;
            schedule = func <system>(period: Nat) : async* (){
              debug if (debug_channel.cycles) Debug.print("scheduling cycle share from function");
              let result = setActionSync<system>(get_time() + period, {actionType = "icrc85:ovs:shareaction:timertool"; params = Blob.fromArray([]);});
              state.nextCycleActionId := ?result.id;
            };
            cycles = cyclesToShare;
          });
          debug if (debug_channel.cycles) Debug.print("done sharing cycles");
        } catch(e){
          debug if (debug_channel.cycles) Debug.print("error sharing cycles" # Error.message(e));
        };

        if(state.nextActionId > 0) {state.lastActionIdReported := ?(state.nextActionId - 1);
        } else {
          state.lastActionIdReported := ?0;
        };
      };

      

      public func get_time() : Nat {
         Int.abs(Time.now());
      };

      private func commitpoint() : async(){};

      private func safetyCheck() : async(){
        debug if (debug_channel.announce) Debug.print("safety check");
        //if the timer is locked, we had a trap and we need to report an error and potentially reschedule the timer
        let ?minAction = Map.minEntry(state.timeTree) else {
          //we are expecting there to be something here, so if we get here and it is missing we just need to do our best to recover
          state.timerLock := null;
          scheduleNextTimer<system>();
          return;
        };

        //if errors are not handled, the item will be removed;
        //todo: add cancle via error to the trx log.
        switch(environment.reportError){
          case(?val) {
            switch(val({action = minAction; awaited = false; error = {error_code = 2; message = "unknown trap " # debug_show(minAction)};})){
              case(?newTime){
                debug if (debug_channel.announce) Debug.print("safety resceduling action for handled error " # debug_show(minAction));
                removeAction(minAction.0);
                debug if (debug_channel.announce) Debug.print("safety adding a new action with " # debug_show( minAction.1.retries + 1));
                addAction({time = newTime; id= minAction.0.id}, {minAction.1 with retries = minAction.1.retries + 1});
              };
              case(null) {
                debug if (debug_channel.announce) Debug.print("safety removing action for unhandled error " # debug_show(minAction.0));
                removeAction(minAction.0);
              };
            };
          };
          case(null) {
            debug if (debug_channel.announce) Debug.print("removing action for unhandled error " # debug_show(minAction.0));
            removeAction(minAction.0);
          };
        };
        state.timerLock := null;
        scheduleNextTimer<system>();
      };

      private func executeActions<system>() : async () {

        if(state.timerLock != null){
          debug if (debug_channel.announce) Debug.print("TimerTool   --- timer locked");
          return;
        };

        debug if (debug_channel.announce) Debug.print("TimerTool   --- executing actions");
        let now = get_time();
        
        state.timerLock := ?now;

        let ?minAction = Map.minEntry(state.timeTree) else {
          debug if (debug_channel.announce) Debug.print("TimerTool   ---   minAction is null"); 
          //execute actions was run but there are no actions to execute
          state.expectedExecutionTime := null;
          state.lastExecutionTime := get_time();
          state.timerLock := null;
          state.nextTimer := null;
          return;
        };

        debug if (debug_channel.announce) Debug.print("TimerTool   ---   minAction" # debug_show(minAction));

        var actionsToExecute = scanLimit<ActionId,Action>(state.timeTree, ActionIdCompare, minAction.0, {
          time = now;
          id = state.nextActionId;
        },  #fwd, state.maxExecutions);

        debug if (debug_channel.announce) Debug.print("TimerTool   ---  actionsToExecute" # debug_show(Iter.toArray(actionsToExecute.results.vals())));

        let processed = List.empty<(ActionId,Action)>();

        label proc for(thisAction in actionsToExecute.results.vals()){
          debug if (debug_channel.announce) Debug.print("thisAction" # debug_show(thisAction));

          if(thisAction.1.actionType == "icrc85:ovs:shareaction:timertool"){
            ignore shareCycles2<system>();
            removeAction(thisAction.0);
            List.add(processed, thisAction);
            continue proc;
          };

          let executionHandler = switch(Map.get(executionListeners, Text.compare, thisAction.1.actionType)){
            case(?val) val;
            case(null){
              switch(Map.get(executionListeners, Text.compare, "")){//search for the default
                case(?val) val;
                case(null) continue proc;
              };
            };
          };

          debug if (debug_channel.announce) Debug.print("have execution handler" # debug_show(thisAction));

          

          switch(executionHandler){
            case(#Sync(handler)){

              debug if (debug_channel.announce) Debug.print("found a sync handler" # debug_show(thisAction));
              //this is a synchronous action
              //we will execute it and remove it from the tree
              let safetyTimer = if(environment.syncUnsafe == null or environment.syncUnsafe == ?false){
                let safetyTimerResult = Timer.setTimer<system>(#nanoseconds(0), safetyCheck);
                await commitpoint();
                ?safetyTimerResult;
              } else null;


              let result = handler<system>(thisAction.0, thisAction.1);
              debug if (debug_channel.announce) Debug.print("removing action" # debug_show(thisAction.0));
              removeAction(thisAction.0);

              debug if (debug_channel.announce) Debug.print("result from execution handler" # debug_show(result));

              state.lastExecutionTime := Int.abs(get_time());

              debug if (debug_channel.announce) Debug.print("done executing sync action");
              switch(safetyTimer){
                case(?val) {
                  Timer.cancelTimer(val);
                  await commitpoint();
                };
                case(null) {};
              };
              switch(environment.reportExecution){
                case(?val) {
                  ignore val({action = thisAction; awaited = false})
                };
                case(null) {};
              };
              List.add(processed, thisAction);
            };
            case(#Async(handler)){

              debug if (debug_channel.announce) Debug.print("found a async handler" # debug_show(thisAction));
              //asyncs can only be executed one a time, so the timerLock stays in place until released or delayed.
              let timeout = switch(thisAction.1.aSync){
                case(?val)val;
                case(null) OneMinute * 5; //default is 5 minutes
              };

              let safetyTimer = Timer.setTimer<system>(#nanoseconds(timeout), safetyCheck);

              
              await commitpoint();


              try{
                debug if (debug_channel.announce) Debug.print("calling the async handler" # debug_show(thisAction.0));
                let result = await* handler(thisAction.0, thisAction.1);

              debug if (debug_channel.announce) Debug.print("removing action" # debug_show(thisAction.0));

              removeAction(thisAction.0);
                switch(result){
                  case(#awaited(_val)){
                    //this function awaited so a state change has occured
                    state.lastExecutionTime := get_time();
                    debug if (debug_channel.announce) Debug.print("done executing async action");
                    Timer.cancelTimer(safetyTimer);

                    await commitpoint();
                    //report a execution
                    switch(environment.reportExecution){
                      case(?val) {
                        ignore val({action = thisAction; awaited = true})
                      };
                      case(null) {};
                    };
                  };
                  case(#trappable(_val)){
                    //this function did not await so no state change has occured
                    state.lastExecutionTime := get_time();
                    debug if (debug_channel.announce) Debug.print("done executing async action");
                    Timer.cancelTimer(safetyTimer);

                    await commitpoint();
                    switch(environment.reportExecution){
                      case(?val) {
                        ignore val({action = thisAction; awaited = false})
                      };
                      case(null) {};
                    };
                  };
                  case(#err(#awaited(err))){
                    //this function awaited so a state change has occured but we ran into an error
                    //errors are not refiled unless handled and a new time returned
                    debug if (debug_channel.announce) Debug.print("done executing async action");
                    Timer.cancelTimer(safetyTimer);

                    await commitpoint();
                    switch(environment.reportError){
                      case(?val) {
                        switch(val({action = thisAction; awaited = false; error = err})){
                          case(?newTime){
                            addAction({time = newTime; id= thisAction.0.id}, {thisAction.1 with retries = thisAction.1.retries + 1});
                          };
                          case(null) {};
                        };
                      };
                      case(null) {};
                    };
                  };
                  case(#err(#trappable(err))){
                    //this function did not await so no state change has occured but we ran into an error
                    //errors are not refiled unless handled and a new time returned
                    debug if (debug_channel.announce) Debug.print("done executing async action");
                    Timer.cancelTimer(safetyTimer);

                    await commitpoint();
                    switch(environment.reportError){
                      case(?val) {
                        switch(val({action = thisAction; awaited = false; error = err})){
                          case(?newTime){
                            addAction({time = newTime; id= thisAction.0.id}, {thisAction.1 with retries = thisAction.1.retries + 1});
                          };
                          case(null) {}
                        };
                      };
                      case(null) {};
                    };
                  };
                };
              } catch(e) {
                Debug.print("error in async action" # Error.message(e));
                debug if (debug_channel.announce) Debug.print("done executing async action and found a trap - cancling safety");
                Timer.cancelTimer(safetyTimer);
                //remove the action...we're going to try to add it back....maybe
                removeAction(thisAction.0);
                await commitpoint();
               

                 debug if (debug_channel.announce) Debug.print("checking errorreport" # debug_show(thisAction.0));
                switch(environment.reportError){
                  case(?val) {
                    debug if (debug_channel.announce) Debug.print("reported error error" # Error.message(e));
                    switch(val({action = thisAction; awaited = true; error = {error_code= 1; message = Error.message(e)}})){
                      case(?newTime){
                        debug if (debug_channel.announce) Debug.print("error resceduling action for handled error " # debug_show(thisAction.0));
                        debug if (debug_channel.announce) Debug.print("error adding a new action with " # debug_show( minAction.1.retries + 1));
                        addAction({time = newTime; id= thisAction.0.id}, {thisAction.1 with retries = thisAction.1.retries + 1});
            
                      };
                      case(null) {};
                    };
                  };
                  case(null) {};
                };
              };
              List.add(processed, thisAction);
            };
            
          };
        };

        debug if (debug_channel.announce) Debug.print("done executing actions");

        switch(environment.reportBatch){
          case(?val) {
            await* val(List.toArray(processed));
          };
          case(null) {};
        };

        state.lastExecutionTime := get_time();
        state.timerLock := null;
        scheduleNextTimer<system>();
      };

      private func removeAction(actionId: ActionId) {
        Map.remove(state.timeTree, ActionIdCompare,actionId);
        Map.remove(state.actionIdIndex, Nat.compare, actionId.id);
      };

      public func cancelAction<system>(actionId: Nat) : ?Nat {
        ensureInit<system>();
        switch(Map.get(state.actionIdIndex, Nat.compare, actionId)){
          case(?time) {
            removeAction({ time; id = actionId});
            scheduleNextTimer<system>();
            ?actionId;
          };
          case(null) {
            null;
          };
        };
      };

      public func registerExecutionListenerSync(namespace: ?Text, handler: ExecutionHandler) : () {
         let finalNamespace = switch(namespace){
          case(?val) val;
          case(null) "";
        };
        Map.add<Text,ExecutionItem>(executionListeners, Text.compare, finalNamespace, #Sync(handler) : ExecutionItem);
      };

      public func registerExecutionListenerAsync(namespace: ?Text, handler: ExecutionAsyncHandler) : () {
        let finalNamespace = switch(namespace){
          case(?val) val;
          case(null) "";
        };
        Map.add<Text,ExecutionItem>(executionListeners, Text.compare, finalNamespace, #Async(handler) :ExecutionItem);
      };

      public func removeExecutionListener(namespace: Text) : () {
        Map.remove<Text,ExecutionItem>(executionListeners, Text.compare, namespace);
      };

      //todd: add a way to upgrade types if necessary.
      public func upgradeArgs<system>(upgrades : [Text], handler: (ActionId, Action) -> ?Action){

        //loop through each item and report params

        let ?minAction = Map.minEntry(state.timeTree) else {
          return;
        };

        let ?maxAction = Map.maxEntry(state.timeTree) else {
          return;
        };

        var actionsToExecute = scanLimit<ActionId,Action>(state.timeTree, ActionIdCompare, minAction.0, maxAction.0,  #fwd, state.maxExecutions);

        label search for(thisAction in actionsToExecute.results.vals()){
          let found = Array.find<Text>(upgrades, func(item: Text) : Bool { item == thisAction.1.actionType });
          if(Option.isNull(found)) continue search;

          let ?result = handler(thisAction.0, thisAction.1) else continue search;

          removeAction(thisAction.0);
          addAction(thisAction.0, result);
        };
      };

      public func getStats() : Stats {
        {
          timers = Map.size(state.timeTree);
          nextTimer = state.nextTimer;
          lastExecutionTime = state.lastExecutionTime;
          expectedExecutionTime = state.expectedExecutionTime;
          nextActionId = state.nextActionId;
          minAction = Map.minEntry(state.timeTree);
          cycles = Cycles.balance();
          maxExecutions = state.maxExecutions;
        }
      };

      public func backUp() : Args {
        ?{
          initialTimers = Map.toArray(state.timeTree);
          lastExecutionTime = state.lastExecutionTime;
          expectedExecutionTime = switch(state.expectedExecutionTime){
            case(?val) val;
            case(null) 0;
          };
          nextActionId = state.nextActionId;
          lastActionIdReported = state.lastActionIdReported;
          nextCycleActionId = state.nextCycleActionId;
          lastCycleReport = state.lastCycleReport;
          maxExecutions = ?state.maxExecutions;
        }
      };

      debug if (debug_channel.announce) Debug.print("initializing timer tool with scheduleNextTimer");

      private var init_ = false;

      public func initialize<system>() : () {
        debug if (debug_channel.announce) Debug.print("initializing");
        ensureInit<system>();
      };

      private func ensureInit<system>() : () {
        
        if(init_ == false){
          init_ := true;
          debug if (debug_channel.announce) Debug.print("ensuring init becuse init_ is false");
          scheduleNextTimer<system>(); 
          
          // Check if OVS/ICRC-85 is disabled via kill_switch
          let ovsDisabled = switch(environment.advanced){
            case(?adv) switch(adv.icrc85){
              case(?icrc85) switch(icrc85.kill_switch){
                case(?true) true;
                case(_) false;
              };
              case(null) false;
            };
            case(null) false;
          };
          
          // Only schedule OVS action if:
          // 1. OVS is not disabled
          // 2. No OVS action is already scheduled (prevents duplicates on upgrade with EOP)
          if(not ovsDisabled and state.nextCycleActionId == null){
            // Schedule ICRC-85 cycle sharing as a TimerTool action instead of using raw Timer.
            // This ensures it works with time-mocking in tests (e.g., PocketIC) and survives upgrades.
            // The action will fire after the grace period then repeat every period.
            let gracePeriod = switch(environment.advanced){
              case(?adv) switch(adv.icrc85){
                case(?icrc85) switch(icrc85.initialWait){
                  case(?wait) wait;
                  case(null) OneDay * 7; // Default 7 day grace period
                };
                case(null) OneDay * 7;
              };
              case(null) OneDay * 7;
            };

            let result = setActionSync<system>(get_time() + gracePeriod, ({actionType = "icrc85:ovs:shareaction:timertool"; params = Blob.fromArray([]);}));
            state.nextCycleActionId := ?result.id;
          };
        };
      };

     
  };
};
