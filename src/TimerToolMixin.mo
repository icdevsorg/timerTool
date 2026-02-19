/////////
// TimerTool Mixin - Super Timer
//
// This mixin provides advanced, resumable timer initialization that can be shared with other classes for a single timer queue management system
// It wraps the OVS ClassPlus implementation.
//
// Usage:
// ```motoko
// import TimerToolMixin "mo:timer-tool/TimerToolMixin";
// 
// actor Token {
//
//   // Define your OVS configuration
//   let timerToolConfig : OVS.InitArgs = { ... };
//   
//
//   include TimerToolMixin(
//      ovsConfig,
//      ovsEnvironment, // or null
//      Principal.fromActor(this),
//      Principal.fromActor(this)
//   );
//
//   public shared func transfer(...) : async ... {
//     ovs.trackAction();  // Track the action
//   };
// };
// ```
/////////

import TT "lib";
import Principal "mo:core/Principal";
import ClassPlus "mo:class-plus";

mixin(
  args: {
    config: TT.MixinConfigArgs;
    caller: Principal;
    canisterId: Principal;
  }
) {

  /// TT Mixin - include this in your actor for timer tools
  var org_icdevs_timer_tool_state = TT.initialState();

  transient var org_icdevs_timer_tool = TT.Init({
    org_icdevs_class_plus_manager = args.config.org_icdevs_class_plus_manager;
    initialState = org_icdevs_timer_tool_state;
    args = args.config.args;
    pullEnvironment = args.config.pullEnvironment;
    onInitialize = args.config.onInitialize;
    onStorageChange = func(state: TT.State) : (){
      org_icdevs_timer_tool_state := state;
    }
  })();
};
