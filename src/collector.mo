import Cycles "mo:core/Cycles";
import D "mo:core/Debug";
import Principal "mo:core/Principal";

shared (deployer) persistent actor class Collector<system>()  = this {

  public type DepositArgs = { to : Account; memo : ?Blob };
  public type DepositResult = { balance : Nat; block_index : BlockIndex };
  public type Account = { owner : Principal; subaccount : ?Blob };
  public type BlockIndex = Nat;

  public type Service = actor {
    deposit : shared DepositArgs -> async DepositResult;
  };

  public type ShareArgs = [
    {
      namespace: Text;
      share: Nat;
    }
  ];

  public type ShareCycleError = {
    #NotEnoughCycles: (Nat, Nat);
    #CustomError: {
      code: Nat;
      message: Text;
    };
  };

  // Track received cycles for testing
  var totalCyclesReceived : Nat = 0;
  var depositCount : Nat = 0;
  var lastDepositAmount : Nat = 0;
  var lastDepositNamespace : Text = "";

  // Query methods for testing
  public query func getTotalCyclesReceived() : async Nat {
    totalCyclesReceived;
  };

  public query func getDepositCount() : async Nat {
    depositCount;
  };

  public query func getLastDeposit() : async { amount: Nat; namespace: Text } {
    { amount = lastDepositAmount; namespace = lastDepositNamespace };
  };

  public query func getCyclesBalance() : async Nat {
    Cycles.balance();
  };

  /**
    * Lets the NFT accept cycles.
    * @returns {Nat} - The amount of cycles accepted.
    */
  public func icrc85_deposit_cycles<system>(request: ShareArgs) : async {#Ok: Nat; #Err: ShareCycleError} {
    D.print("recived cycles");
    let amount = Cycles.available();
    let accepted = amount;
    ignore Cycles.accept<system>(accepted);
    
    // Track for testing
    totalCyclesReceived += accepted;
    depositCount += 1;
    lastDepositAmount := accepted;
    if (request.size() > 0) {
      lastDepositNamespace := request[0].namespace;
    };
    
    D.print("recived cycles" # debug_show(accepted));
    #Ok(accepted);
  };

  /**
    * Lets the NFT accept cycles.
    * @returns {Nat} - The amount of cycles accepted.
    */
  public func icrc85_deposit_cycles_notify<system>(request: [(Text, Nat)]) : () {
    D.print("recived cycles notify");
    let amount = Cycles.available();
    let accepted = amount;
    ignore Cycles.accept<system>(accepted);
    
    // Track for testing
    totalCyclesReceived += accepted;
    depositCount += 1;
    lastDepositAmount := accepted;
    if (request.size() > 0) {
      lastDepositNamespace := request[0].0;
    };
    
    D.print("recived cycles" # debug_show(accepted));
  };

  public shared(msg) func wallet_withdraw<system>(amount: Nat, owner: ?Principal) : async DepositResult {
    assert(Principal.isController(msg.caller));
    let service : Service = actor("um5iw-rqaaa-aaaaq-qaaba-cai");
    await (with cycles = amount) service.deposit({ to = { owner = switch(owner){
      case(?val) val;
      case(null) msg.caller;
    }; subaccount = null }; memo = null });

  };

};