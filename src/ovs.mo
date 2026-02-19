/// Minimal OVS (Open Value Sharing) implementation for timer-tool
/// This module breaks the circular dependency between timer-tool and ovs-fixed
/// by inlining the core shareCycles functionality.
///
/// For full OVS features (scheduling, tracking, etc.), use the ovs-fixed library
/// and override via environment.customShareCycles

import Array "mo:core/Array";
import List "mo:core/List";
import Cycles "mo:core/Cycles";
import Error "mo:core/Error";
import Debug "mo:core/Debug";
import Principal "mo:core/Principal";
import Blob "mo:core/Blob";

module {

  let debug_channel = {
    announce = false;
    cycles = false;
  };

  public let OneDay = 86_400_000_000_000;
  public let OneXDR = 1_000_000_000_000;  // ~1 XDR in cycles
  let MAX_CYCLES = 1_000_000_000_000_000;
  let COLLECTOR = "q26le-iqaaa-aaaam-actsa-cai";

  public type Map = [(Text, Value)];

  public type Value = {
    #Int : Int;
    #Map : Map;
    #Nat : Nat;
    #Blob : Blob;
    #Text : Text;
    #Array : [Value];
  };

  /// Environment configuration for ICRC-85 compliant cycle sharing
  public type ICRC85Environment = ?{
    kill_switch: ?Bool;
    handler: ?(([(Text, Map)]) -> ());
    period: ?Nat;
    asset: ?Text;
    platform: ?Text;
    tree: ?[Text];
    collector: ?Principal;
  };

  /// Share cycles with the OVS collector
  /// This is a minimal implementation that handles the core cycle sharing logic.
  /// For advanced features like automatic scheduling and tracking, use ovs-fixed.
  public func shareCycles<system>(request: {
    environment: ICRC85Environment;
    cycles: Nat;
    actions: Nat;
    namespace: Text;
    schedule: <system>(Nat) -> async* ();
  }) : async* () {
    debug if (debug_channel.announce) Debug.print("sharing cycles");

    let period : Nat = switch(do?{request.environment!.period!}){
      case(?val) val;
      case(null) (OneDay * 30);
    };

    let local_collector : Text = switch(do?{request.environment!.collector!}){
      case(?val) Principal.toText(val);
      case(null) COLLECTOR;
    };

    let asset : Text = switch(do?{request.environment!.asset!}){
      case(?val) val;
      case(null) "cycles";
    };

    let platform : Text = switch(do?{request.environment!.platform!}){
      case(?val) val;
      case(null) "icp";
    };

    let tree : ?Value = switch(do?{request.environment!.tree!}){
      case(?val){
        ?#Array(Array.map<Text, Value>(val, func(x: Text) : Value {#Text(x)}));
      };
      case(null) null;
    };

    await* request.schedule<system>(period);

    switch(do?{request.environment!.kill_switch!}){
      case(?val){
        if(val == true) return;
      };
      case(_){};
    };

    switch(do?{request.environment!.handler!}){
      case(?val){
        let map = List.empty<(Text,Value)>();
        List.add(map, ("report_period", #Nat(period)));
        switch(tree){
          case(?treeVal) List.add(map, ("tree", treeVal));
          case(null) {};
        };
        List.add(map, ("principal", #Text(local_collector)));
        List.add(map, ("asset", #Text(asset)));
        List.add(map, ("platform", #Text(platform)));
        List.add(map, ("units", #Nat(request.actions)));

        val([("icrc85:ovs:shareaction", List.toArray(map))]);
      };
      case(null){

        debug if (debug_channel.cycles) Debug.print("about to share cycles");

        let shareCyclesService : actor{
          icrc85_deposit_cycles_notify : ([(Text,Nat)]) -> ();
        } = actor(local_collector);

        let currentBalance = Cycles.balance();
        var cyclesToShare = request.cycles;

        debug if (debug_channel.cycles) Debug.print("cycle balance" # debug_show(currentBalance));

        //make sure we don't drain someone's cycles
        if(cyclesToShare * 2 > currentBalance ) cyclesToShare := currentBalance / 2;

        if(cyclesToShare > MAX_CYCLES) cyclesToShare := MAX_CYCLES;

        try{
          (with cycles = cyclesToShare) shareCyclesService.icrc85_deposit_cycles_notify([(request.namespace, request.actions)]);

          debug if (debug_channel.cycles) Debug.print("cycle shared");
          
        } catch(e){
          debug if (debug_channel.cycles) Debug.print("error sharing cycles" # Error.message(e));
        };
      };
    };
  };
};
