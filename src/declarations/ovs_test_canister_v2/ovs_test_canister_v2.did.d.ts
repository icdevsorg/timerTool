import type { Principal } from '@dfinity/principal';
import type { ActorMethod } from '@dfinity/agent';
import type { IDL } from '@dfinity/candid';

export interface Action {
  'aSync' : [] | [bigint],
  'actionType' : string,
  'params' : Uint8Array | number[],
  'retries' : bigint,
}
export type ActionDetail = [ActionId, Action];
export interface ActionId { 'id' : bigint, 'time' : Time }
export interface OVSTestCanisterV2 {
  /**
   * / Add an async action
   */
  'addAsyncAction' : ActorMethod<
    [bigint, string, [] | [bigint], bigint],
    ActionId
  >,
  /**
   * / Add a sync action
   */
  'addSyncAction' : ActorMethod<[bigint, string, [] | [bigint]], ActionId>,
  /**
   * / Cancel an action
   */
  'cancelAction' : ActorMethod<[bigint], [] | [bigint]>,
  /**
   * / Get counter value
   */
  'getCounter' : ActorMethod<[], bigint>,
  /**
   * / Get error count
   */
  'getErrorCount' : ActorMethod<[], bigint>,
  /**
   * / Get executed action count
   */
  'getExecutedCount' : ActorMethod<[], bigint>,
  /**
   * / Get execution history
   */
  'getExecutionHistory' : ActorMethod<[], Array<[bigint, string, bigint]>>,
  /**
   * / Get OVS-specific stats
   */
  'getOVSStats' : ActorMethod<
    [],
    {
      'nextCycleActionId' : [] | [bigint],
      'lastCycleShareTime' : bigint,
      'lastActionIdReported' : [] | [bigint],
      'cycleShareCount' : bigint,
      'lastCycleReport' : [] | [bigint],
      'cyclesBalance' : bigint,
    }
  >,
  /**
   * / Get timer stats
   */
  'getStats' : ActorMethod<[], Stats>,
  /**
   * / Get current time in nanoseconds
   */
  'getTime' : ActorMethod<[], bigint>,
  /**
   * / Get raw timer state for debugging
   */
  'getTimerState' : ActorMethod<
    [],
    {
      'nextCycleActionId' : [] | [bigint],
      'nextActionId' : bigint,
      'lastActionIdReported' : [] | [bigint],
      'lastCycleReport' : [] | [bigint],
    }
  >,
  'getUpgradeCount' : ActorMethod<[], bigint>,
  'incrementUpgradeCount' : ActorMethod<[], undefined>,
  /**
   * / Force re-initialization (for testing)
   */
  'initialize' : ActorMethod<[], undefined>,
  /**
   * / Reset test state
   */
  'resetTestState' : ActorMethod<[], undefined>,
  /**
   * / Update collector
   */
  'updateCollector' : ActorMethod<[[] | [Principal]], undefined>,
  /**
   * / Update OVS period (for testing shorter cycles)
   */
  'updateOVSPeriod' : ActorMethod<[bigint], undefined>,
  'version' : ActorMethod<[], string>,
}
export interface Stats {
  'timers' : bigint,
  'maxExecutions' : bigint,
  'minAction' : [] | [ActionDetail],
  'cycles' : bigint,
  'nextActionId' : bigint,
  'nextTimer' : [] | [TimerId],
  'expectedExecutionTime' : [] | [Time],
  'lastExecutionTime' : Time,
}
export type Time = bigint;
export type TimerId = bigint;
/**
 * / OVSTestCanisterV2 - Test canister V2 with OVS enabled for upgrade testing
 * /
 * / This canister is a second version to test upgrade scenarios:
 * / - Same functionality as V1 plus additional features
 * / - Used to verify upgrades don't cause duplicate timers or OVS allocations
 */
export interface _SERVICE extends OVSTestCanisterV2 {}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
