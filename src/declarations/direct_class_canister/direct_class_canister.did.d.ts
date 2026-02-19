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
export interface DirectClassCanister {
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
   * / Get last executed namespace
   */
  'getLastExecuted' : ActorMethod<[], [string, Uint8Array | number[]]>,
  /**
   * / Get timer stats
   */
  'getStats' : ActorMethod<[], Stats>,
  /**
   * / Get current time in nanoseconds
   */
  'getTime' : ActorMethod<[], bigint>,
  /**
   * / Force initialization (for testing)
   */
  'initialize' : ActorMethod<[], undefined>,
  /**
   * / Reset test state
   */
  'resetTestState' : ActorMethod<[], undefined>,
  /**
   * / Set counter value (for testing)
   */
  'setCounter' : ActorMethod<[bigint], undefined>,
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
 * / DirectClassCanister - Example canister using direct TT.Init() pattern
 * /
 * / This canister demonstrates direct usage of TimerTool without mixin,
 * / following the same pattern as the main test canister.
 */
export interface _SERVICE extends DirectClassCanister {}
export declare const idlFactory: IDL.InterfaceFactory;
export declare const init: (args: { IDL: typeof IDL }) => IDL.Type[];
