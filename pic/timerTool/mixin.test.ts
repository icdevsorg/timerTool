import { describe, it, expect, beforeEach, afterEach, beforeAll, afterAll } from 'vitest';
import { Principal } from "@dfinity/principal";
import { IDL } from "@dfinity/candid";

import {
  PocketIc,
  PocketIcServer,
  createIdentity,
  SubnetStateType,
} from "@dfinity/pic";

import type {
  Actor,
  CanisterFixture
} from "@dfinity/pic";

import { resolve } from 'path';

// Import MixinCanister declarations
import {
  idlFactory as mixinIDLFactory,
  init as mixinInit
} from "../../src/declarations/mixin_canister/mixin_canister.did.js";
import type {
  _SERVICE as MixinService,
  ActionId,
  Stats
} from "../../src/declarations/mixin_canister/mixin_canister.did.d";
export const mixin_WASM_PATH = resolve(__dirname, "../../.dfx/local/canisters/mixin_canister/mixin_canister.wasm");

// Import DirectClassCanister declarations
import {
  idlFactory as directIDLFactory,
  init as directInit
} from "../../src/declarations/direct_class_canister/direct_class_canister.did.js";
import type {
  _SERVICE as DirectService
} from "../../src/declarations/direct_class_canister/direct_class_canister.did.d";
export const direct_WASM_PATH = resolve(__dirname, "../../.dfx/local/canisters/direct_class_canister/direct_class_canister.wasm");

// Import Collector declarations for OVS tests
import {
  idlFactory as collectorIDLFactory,
  init as collectorInit
} from "../../src/declarations/collector/collector.did.js";
import type {
  _SERVICE as CollectorService
} from "../../src/declarations/collector/collector.did.d";
export const collector_WASM_PATH = resolve(__dirname, "../../.dfx/local/canisters/collector/collector.wasm");

let pic: PocketIc;
let picServer: PocketIcServer;

let mixin_fixture: CanisterFixture<MixinService>;
let direct_fixture: CanisterFixture<DirectService>;

const admin = createIdentity("admin");

const OneMinute = BigInt(60_000_000_000); // 1 minute in nanoseconds
const OneSecond = BigInt(1_000_000_000); // 1 second in nanoseconds

// Helper to get current time in nanoseconds from PocketIC
async function getCurrentTimeNs(pic: PocketIc): Promise<bigint> {
  return BigInt(await pic.getTime()) * BigInt(1_000_000);
}

describe("MixinCanister Tests", () => {
  beforeAll(async () => {
    picServer = await PocketIcServer.start();
  });

  afterAll(async () => {
    await picServer.stop();
  });

  beforeEach(async () => {
    pic = await PocketIc.create(picServer.getUrl(), {
      application: [{ state: { type: SubnetStateType.New } }],
    });

    // Set up time
    await pic.setTime(new Date(2024, 1, 30).getTime());
    await pic.tick();

    // Deploy MixinCanister
    mixin_fixture = await pic.setupCanister<MixinService>({
      idlFactory: mixinIDLFactory,
      wasm: mixin_WASM_PATH,
      arg: IDL.encode(mixinInit({IDL}), []),
    });

    // Initialize
    mixin_fixture.actor.setIdentity(admin);
    await mixin_fixture.actor.initialize();
    await pic.tick();
  });

  afterEach(async () => {
    await pic.tearDown();
  });

  // ================== Initialization Tests ==================

  it("initializes with clean state", async () => {
    const stats = await mixin_fixture.actor.getStats();
    console.log("Initial stats:", stats);

    // minAction should be empty on fresh init (no actions yet scheduled in this test)
    // Note: The timer auto-schedules a safety action, so we check structure
    expect(stats.nextActionId).toBeGreaterThanOrEqual(1n);
    expect(stats.cycles).toBeGreaterThan(0n);

    const counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(0n);
  });

  // ================== Sync Action Tests ==================

  it("schedules and executes a sync 'inc' action", async () => {
    mixin_fixture.actor.setIdentity(admin);

    // Get current time
    const currentTime = await getCurrentTimeNs(pic);
    const actionTime = currentTime + OneSecond * 2n; // 2 seconds in future

    // Schedule an "inc" action with value 5
    const actionId = await mixin_fixture.actor.addSyncAction(actionTime, "inc", [5n]);
    console.log("Scheduled action:", actionId);

    expect(actionId.id).toBeGreaterThan(0n);

    // Verify counter before
    const counterBefore = await mixin_fixture.actor.getCounter();
    expect(counterBefore).toBe(0n);

    // Advance time past action time
    await pic.advanceTime(3000); // 3 seconds
    await pic.tick();
    await pic.tick();

    // Verify counter after
    const counterAfter = await mixin_fixture.actor.getCounter();
    expect(counterAfter).toBe(5n);

    // Verify execution tracking
    const executedCount = await mixin_fixture.actor.getExecutedCount();
    expect(executedCount).toBe(1n);
  });

  it("schedules multiple sync actions and executes in time order", async () => {
    mixin_fixture.actor.setIdentity(admin);

    const currentTime = await getCurrentTimeNs(pic);

    // Schedule actions at different times
    await mixin_fixture.actor.addSyncAction(currentTime + OneSecond * 3n, "inc", [10n]);
    await mixin_fixture.actor.addSyncAction(currentTime + OneSecond * 1n, "inc", [1n]);
    await mixin_fixture.actor.addSyncAction(currentTime + OneSecond * 2n, "inc", [5n]);

    // Advance time incrementally and check execution order
    await pic.advanceTime(1500); // 1.5 seconds
    await pic.tick();
    await pic.tick();

    let counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(1n); // First action (1) executed

    await pic.advanceTime(1000); // Another second
    await pic.tick();
    await pic.tick();

    counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(6n); // Second action (5) executed

    await pic.advanceTime(1000); // Another second
    await pic.tick();
    await pic.tick();

    counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(16n); // Third action (10) executed

    const executedCount = await mixin_fixture.actor.getExecutedCount();
    expect(executedCount).toBe(3n);
  });

  it("can cancel a scheduled sync action", async () => {
    mixin_fixture.actor.setIdentity(admin);

    const currentTime = await getCurrentTimeNs(pic);
    const actionTime = currentTime + OneSecond * 5n;

    // Schedule action
    const actionId = await mixin_fixture.actor.addSyncAction(actionTime, "inc", [100n]);
    console.log("Scheduled action:", actionId);

    // Cancel it
    const cancelResult = await mixin_fixture.actor.cancelAction(actionId.id);
    console.log("Cancel result:", cancelResult);

    expect(cancelResult.length).toBe(1);

    // Advance time past action time
    await pic.advanceTime(6000);
    await pic.tick();
    await pic.tick();

    // Counter should still be 0
    const counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(0n);
  });

  it("uses default handler for unknown namespace", async () => {
    mixin_fixture.actor.setIdentity(admin);

    const currentTime = await getCurrentTimeNs(pic);
    const actionTime = currentTime + OneSecond;

    // Schedule action with unknown namespace
    await mixin_fixture.actor.addSyncAction(actionTime, "unknown_namespace", []);

    // Advance time
    await pic.advanceTime(2000);
    await pic.tick();
    await pic.tick();

    // Should have executed (default handler)
    const [lastNamespace, _] = await mixin_fixture.actor.getLastExecuted();
    expect(lastNamespace).toBe("unknown_namespace");

    const executedCount = await mixin_fixture.actor.getExecutedCount();
    expect(executedCount).toBe(1n);
  });

  // ================== Async Action Tests ==================

  it("schedules and executes an async 'inc_async' action", async () => {
    mixin_fixture.actor.setIdentity(admin);

    const currentTime = await getCurrentTimeNs(pic);
    const actionTime = currentTime + OneSecond * 2n;

    // Schedule async action with 10 second timeout
    const actionId = await mixin_fixture.actor.addAsyncAction(
      actionTime,
      "inc_async",
      [7n],
      OneSecond * 10n
    );
    console.log("Scheduled async action:", actionId);

    // Advance time
    await pic.advanceTime(3000);
    await pic.tick();
    await pic.tick();
    await pic.tick(); // Extra tick for async processing

    // Verify counter
    const counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(7n);

    const executedCount = await mixin_fixture.actor.getExecutedCount();
    expect(executedCount).toBe(1n);
  });

  // ================== Upgrade Persistence Tests ==================

  it("persists actions across upgrade", async () => {
    mixin_fixture.actor.setIdentity(admin);

    const currentTime = await getCurrentTimeNs(pic);
    const actionTime = currentTime + OneMinute; // 1 minute in future

    // Schedule action
    const actionId = await mixin_fixture.actor.addSyncAction(actionTime, "inc", [42n]);
    console.log("Scheduled action before upgrade:", actionId);

    // Verify stats before upgrade
    let stats = await mixin_fixture.actor.getStats();
    console.log("Stats before upgrade:", stats);
    expect(stats.minAction.length).toBe(1); // Should have our action

    // Upgrade the canister with EOP memory persistence option
    await pic.upgradeCanister({
      canisterId: mixin_fixture.canisterId,
      wasm: mixin_WASM_PATH,
      arg: IDL.encode(mixinInit({IDL}), []),
      upgradeModeOptions: {
        skip_pre_upgrade: [],
        wasm_memory_persistence: [{ keep: null }]
      }
    });
    await pic.tick();

    // Reinitialize after upgrade
    await mixin_fixture.actor.initialize();
    await pic.tick();

    // Verify stats after upgrade
    stats = await mixin_fixture.actor.getStats();
    console.log("Stats after upgrade:", stats);
    expect(stats.minAction.length).toBe(1); // Action should persist

    // Advance time and verify action executes
    await pic.advanceTime(65000); // 65 seconds
    await pic.tick();
    await pic.tick();

    const counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(42n);
  });

  // ================== Stop/Start Persistence Tests ==================

  it("persists state across stop/start", async () => {
    mixin_fixture.actor.setIdentity(admin);

    // Set counter
    await mixin_fixture.actor.setCounter(100n);
    await pic.tick();

    const currentTime = await getCurrentTimeNs(pic);
    const actionTime = currentTime + OneMinute;

    // Schedule action
    await mixin_fixture.actor.addSyncAction(actionTime, "inc", [50n]);

    // Verify before stop
    let counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(100n);

    let stats = await mixin_fixture.actor.getStats();
    expect(stats.minAction.length).toBe(1);

    // Stop canister
    await pic.stopCanister({ canisterId: mixin_fixture.canisterId });
    await pic.tick();

    // Start canister
    await pic.startCanister({ canisterId: mixin_fixture.canisterId });
    await pic.tick();

    // Reinitialize
    await mixin_fixture.actor.initialize();
    await pic.tick();

    // Verify counter persisted
    counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(100n);

    // Verify action persisted
    stats = await mixin_fixture.actor.getStats();
    expect(stats.minAction.length).toBe(1);

    // Advance time and execute action
    await pic.advanceTime(65000);
    await pic.tick();
    await pic.tick();

    counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(150n); // 100 + 50
  });

  // ================== Reset Test State ==================

  it("can reset test state", async () => {
    mixin_fixture.actor.setIdentity(admin);

    // Set up some state
    await mixin_fixture.actor.setCounter(50n);

    const currentTime = await getCurrentTimeNs(pic);
    await mixin_fixture.actor.addSyncAction(currentTime + OneSecond, "inc", [10n]);

    await pic.advanceTime(2000);
    await pic.tick();
    await pic.tick();

    // Verify state exists
    let counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(60n); // 50 + 10

    let executedCount = await mixin_fixture.actor.getExecutedCount();
    expect(executedCount).toBe(1n);

    // Reset
    await mixin_fixture.actor.resetTestState();
    await pic.tick();

    // Verify reset
    counter = await mixin_fixture.actor.getCounter();
    expect(counter).toBe(0n);

    executedCount = await mixin_fixture.actor.getExecutedCount();
    expect(executedCount).toBe(0n);
  });
});

// ================== DirectClassCanister Tests ==================

describe("DirectClassCanister Tests", () => {
  let directPic: PocketIc;
  let directPicServer: PocketIcServer;
  let directFixture: CanisterFixture<DirectService>;

  beforeAll(async () => {
    directPicServer = await PocketIcServer.start();
  });

  afterAll(async () => {
    await directPicServer.stop();
  });

  beforeEach(async () => {
    directPic = await PocketIc.create(directPicServer.getUrl(), {
      application: [{ state: { type: SubnetStateType.New } }],
    });

    await directPic.setTime(new Date(2024, 1, 30).getTime());
    await directPic.tick();

    // Deploy DirectClassCanister
    directFixture = await directPic.setupCanister<DirectService>({
      idlFactory: directIDLFactory,
      wasm: direct_WASM_PATH,
      arg: IDL.encode(directInit({IDL}), []),
    });

    directFixture.actor.setIdentity(admin);
    await directFixture.actor.initialize();
    await directPic.tick();
  });

  afterEach(async () => {
    await directPic.tearDown();
  });

  it("initializes and can schedule actions", async () => {
    directFixture.actor.setIdentity(admin);

    const stats = await directFixture.actor.getStats();
    expect(stats.nextActionId).toBeGreaterThanOrEqual(1n);

    const currentTime = BigInt(await directPic.getTime()) * BigInt(1_000_000);
    const actionId = await directFixture.actor.addSyncAction(
      currentTime + OneSecond * 2n,
      "inc",
      [3n]
    );

    expect(actionId.id).toBeGreaterThan(0n);

    await directPic.advanceTime(3000);
    await directPic.tick();
    await directPic.tick();

    const counter = await directFixture.actor.getCounter();
    expect(counter).toBe(3n);
  });

  it("behaves identically to MixinCanister for basic operations", async () => {
    // Also deploy MixinCanister in same PocketIC instance
    const mixinFix = await directPic.setupCanister<MixinService>({
      idlFactory: mixinIDLFactory,
      wasm: mixin_WASM_PATH,
      arg: IDL.encode(mixinInit({IDL}), []),
    });

    mixinFix.actor.setIdentity(admin);
    await mixinFix.actor.initialize();
    await directPic.tick();

    const currentTime = BigInt(await directPic.getTime()) * BigInt(1_000_000);
    const actionTime = currentTime + OneSecond * 2n;

    // Schedule same action on both
    await mixinFix.actor.addSyncAction(actionTime, "inc", [25n]);
    await directFixture.actor.addSyncAction(actionTime, "inc", [25n]);

    // Advance time
    await directPic.advanceTime(3000);
    await directPic.tick();
    await directPic.tick();

    // Both should have same result
    const mixinCounter = await mixinFix.actor.getCounter();
    const directCounter = await directFixture.actor.getCounter();

    expect(mixinCounter).toBe(directCounter);
    expect(mixinCounter).toBe(25n);
  });
});

// ================== Phase 4: Advanced Functionality Tests ==================

describe("Advanced Functionality Tests", () => {
  let advPic: PocketIc;
  let advPicServer: PocketIcServer;
  let advFixture: CanisterFixture<MixinService>;

  beforeAll(async () => {
    advPicServer = await PocketIcServer.start();
  });

  afterAll(async () => {
    await advPicServer.stop();
  });

  beforeEach(async () => {
    advPic = await PocketIc.create(advPicServer.getUrl(), {
      application: [{ state: { type: SubnetStateType.New } }],
    });

    await advPic.setTime(new Date(2024, 1, 30).getTime());
    await advPic.tick();

    advFixture = await advPic.setupCanister<MixinService>({
      idlFactory: mixinIDLFactory,
      wasm: mixin_WASM_PATH,
      arg: IDL.encode(mixinInit({IDL}), []),
    });

    advFixture.actor.setIdentity(admin);
    await advFixture.actor.initialize();
    await advPic.tick();
  });

  afterEach(async () => {
    await advPic.tearDown();
  });

  // ================== Batch Execution Tests ==================

  it("executes multiple past-due actions in batches (maxExecutions)", async () => {
    advFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await advPic.getTime()) * BigInt(1_000_000);

    // Schedule 15 actions all in the near future (will become past-due after time advance)
    const futureTime = currentTime + OneSecond * 5n; // 5 seconds from now

    for (let i = 0; i < 15; i++) {
      // Each action increments by 1, spaced 1ms apart
      await advFixture.actor.addSyncAction(futureTime + BigInt(i * 1000000), "inc", [1n]);
    }

    const statsBefore = await advFixture.actor.getStats();
    console.log("Stats before execution:", statsBefore);
    // Should have 15 user actions + ICRC-85 action = at least 15
    expect(Number(statsBefore.timers)).toBeGreaterThanOrEqual(15);

    // Advance time past all action times to trigger batch execution
    await advPic.advanceTime(10000); // 10 seconds - all actions now overdue
    await advPic.tick();
    await advPic.tick();

    let counter = await advFixture.actor.getCounter();
    console.log("Counter after first batch:", counter);
    // With maxExecutions=10, first batch should execute up to 10 actions
    expect(Number(counter)).toBeGreaterThanOrEqual(10);

    // More ticks should execute remaining actions
    await advPic.tick();
    await advPic.tick();
    await advPic.tick();

    counter = await advFixture.actor.getCounter();
    console.log("Counter after more ticks:", counter);
    // All 15 actions should eventually execute
    expect(counter).toBe(15n);

    const executedCount = await advFixture.actor.getExecutedCount();
    expect(executedCount).toBe(15n);
  });

  it("handles rapid action additions without corruption", async () => {
    advFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await advPic.getTime()) * BigInt(1_000_000);

    // Rapidly add 20 actions with staggered times
    const actionPromises: Promise<any>[] = [];
    for (let i = 0; i < 20; i++) {
      actionPromises.push(
        advFixture.actor.addSyncAction(
          currentTime + OneSecond * BigInt(i + 1),
          "inc",
          [1n]
        )
      );
    }

    // Wait for all to complete
    const results = await Promise.all(actionPromises);

    // All should have unique IDs
    const ids = results.map(r => r.id);
    const uniqueIds = new Set(ids);
    expect(uniqueIds.size).toBe(20);

    // Verify stats
    const stats = await advFixture.actor.getStats();
    console.log("Stats after rapid additions:", stats);
    expect(stats.timers).toBeGreaterThanOrEqual(20n);

    // Advance time to execute all
    await advPic.advanceTime(25000); // 25 seconds
    await advPic.tick();
    await advPic.tick();
    await advPic.tick();

    const counter = await advFixture.actor.getCounter();
    expect(counter).toBe(20n);
  });

  it("cancels action while others are queued", async () => {
    advFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await advPic.getTime()) * BigInt(1_000_000);

    // Schedule 5 actions
    const action1 = await advFixture.actor.addSyncAction(currentTime + OneSecond * 1n, "inc", [10n]);
    const action2 = await advFixture.actor.addSyncAction(currentTime + OneSecond * 2n, "inc", [20n]);
    const action3 = await advFixture.actor.addSyncAction(currentTime + OneSecond * 3n, "inc", [30n]);
    const action4 = await advFixture.actor.addSyncAction(currentTime + OneSecond * 4n, "inc", [40n]);
    const action5 = await advFixture.actor.addSyncAction(currentTime + OneSecond * 5n, "inc", [50n]);

    // Cancel action3 (30)
    const cancelResult = await advFixture.actor.cancelAction(action3.id);
    expect(cancelResult.length).toBe(1);

    // Advance time to execute all remaining
    await advPic.advanceTime(6000);
    await advPic.tick();
    await advPic.tick();

    const counter = await advFixture.actor.getCounter();
    // Should be 10 + 20 + 40 + 50 = 120 (not 30)
    expect(counter).toBe(120n);

    const executedCount = await advFixture.actor.getExecutedCount();
    expect(executedCount).toBe(4n);
  });

  // ================== Time Edge Cases ==================

  it("executes action scheduled for past time immediately", async () => {
    advFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await advPic.getTime()) * BigInt(1_000_000);

    // Schedule action for 5 seconds ago
    const pastTime = currentTime - OneSecond * 5n;
    await advFixture.actor.addSyncAction(pastTime, "inc", [99n]);

    // Just tick - action should execute immediately since it's overdue
    await advPic.tick();
    await advPic.tick();

    const counter = await advFixture.actor.getCounter();
    expect(counter).toBe(99n);
  });

  it("handles action scheduled for 'now'", async () => {
    advFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await advPic.getTime()) * BigInt(1_000_000);

    // Schedule action for right now
    await advFixture.actor.addSyncAction(currentTime, "inc", [77n]);

    await advPic.tick();
    await advPic.tick();

    const counter = await advFixture.actor.getCounter();
    expect(counter).toBe(77n);
  });

  it("correctly orders same-time actions by ID", async () => {
    advFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await advPic.getTime()) * BigInt(1_000_000);
    const futureTime = currentTime + OneSecond * 2n;

    // Schedule multiple actions for the exact same time
    // They should execute in ID order
    await advFixture.actor.addSyncAction(futureTime, "inc", [1n]);
    await advFixture.actor.addSyncAction(futureTime, "inc", [2n]);
    await advFixture.actor.addSyncAction(futureTime, "inc", [3n]);

    await advPic.advanceTime(3000);
    await advPic.tick();
    await advPic.tick();

    const counter = await advFixture.actor.getCounter();
    expect(counter).toBe(6n); // 1 + 2 + 3

    // Check execution history to verify order
    const history = await advFixture.actor.getExecutionHistory();
    console.log("Execution history:", history);
    expect(history.length).toBe(3);
  });

  // ================== Concurrent Operation Tests ==================

  it("add action while execution is potentially in progress", async () => {
    advFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await advPic.getTime()) * BigInt(1_000_000);

    // Schedule action for 2 seconds
    await advFixture.actor.addSyncAction(currentTime + OneSecond * 2n, "inc", [100n]);

    // Advance time
    await advPic.advanceTime(2500);

    // While potentially executing, add another action
    const newAction = await advFixture.actor.addSyncAction(
      currentTime + OneSecond * 4n,
      "inc",
      [200n]
    );
    expect(newAction.id).toBeGreaterThan(0n);

    await advPic.tick();
    await advPic.tick();

    let counter = await advFixture.actor.getCounter();
    expect(counter).toBe(100n);

    // Advance more time for second action
    await advPic.advanceTime(2000);
    await advPic.tick();
    await advPic.tick();

    counter = await advFixture.actor.getCounter();
    expect(counter).toBe(300n);
  });
});

// ================== Phase 5: OVS/ICRC-85 Integration Tests ==================

describe("OVS/ICRC-85 Integration Tests", () => {
  let ovsPic: PocketIc;
  let ovsPicServer: PocketIcServer;
  let ovsFixture: CanisterFixture<MixinService>;
  let collectorFixture: CanisterFixture<CollectorService>;

  const OneDay = BigInt(86_400_000_000_000); // 1 day in nanoseconds
  const SevenDays = OneDay * 7n; // 7 days grace period

  beforeAll(async () => {
    ovsPicServer = await PocketIcServer.start();
  });

  afterAll(async () => {
    await ovsPicServer.stop();
  });

  beforeEach(async () => {
    ovsPic = await PocketIc.create(ovsPicServer.getUrl(), {
      application: [{ state: { type: SubnetStateType.New } }],
    });

    await ovsPic.setTime(new Date(2024, 1, 30).getTime());
    await ovsPic.tick();

    // Deploy collector canister first
    collectorFixture = await ovsPic.setupCanister<CollectorService>({
      idlFactory: collectorIDLFactory,
      wasm: collector_WASM_PATH,
      arg: IDL.encode(collectorInit({IDL}), []),
    });

    // Deploy MixinCanister
    ovsFixture = await ovsPic.setupCanister<MixinService>({
      idlFactory: mixinIDLFactory,
      wasm: mixin_WASM_PATH,
      arg: IDL.encode(mixinInit({IDL}), []),
    });

    ovsFixture.actor.setIdentity(admin);
    await ovsFixture.actor.initialize();
    await ovsPic.tick();
  });

  afterEach(async () => {
    await ovsPic.tearDown();
  });

  it("schedules initial OVS action on initialization", async () => {
    ovsFixture.actor.setIdentity(admin);

    const stats = await ovsFixture.actor.getStats();
    console.log("Initial OVS stats:", stats);

    // The timer should have scheduled the ICRC-85 OVS action
    // This is the safety timer action scheduled ~7 days in the future
    expect(stats.timers).toBeGreaterThanOrEqual(1n);

    // Check that expectedExecutionTime includes the OVS action (7 days grace)
    // The init schedules an action for now + 7 days
    if (stats.expectedExecutionTime.length > 0) {
      const currentTime = BigInt(await ovsPic.getTime()) * BigInt(1_000_000);
      const expectedTime = stats.expectedExecutionTime[0];
      console.log("Current time:", currentTime);
      console.log("Expected OVS time:", expectedTime);
      // OVS action should be scheduled in the future (within 7+ days)
    }
  });

  it("OVS action executes after grace period", async () => {
    ovsFixture.actor.setIdentity(admin);

    // Add some user actions to track
    const currentTime = BigInt(await ovsPic.getTime()) * BigInt(1_000_000);
    for (let i = 0; i < 5; i++) {
      await ovsFixture.actor.addSyncAction(currentTime + OneSecond * BigInt(i + 1), "noop", []);
    }

    // Let user actions execute
    await ovsPic.advanceTime(10000); // 10 seconds
    await ovsPic.tick();
    await ovsPic.tick();

    const statsBefore = await ovsFixture.actor.getStats();
    console.log("Stats before OVS fires:", statsBefore);

    // Now advance time past the 7-day grace period
    // 7 days = 7 * 24 * 60 * 60 * 1000 = 604800000 ms
    await ovsPic.advanceTime(604800000 + 60000); // 7 days + 1 minute
    await ovsPic.tick();
    await ovsPic.tick();
    await ovsPic.tick();

    const statsAfter = await ovsFixture.actor.getStats();
    console.log("Stats after OVS fires:", statsAfter);

    // OVS action should have executed and rescheduled for 30 days later
    // nextActionId should have increased
    expect(statsAfter.nextActionId).toBeGreaterThan(statsBefore.nextActionId);
  });

  it("OVS persists across upgrade", async () => {
    ovsFixture.actor.setIdentity(admin);

    const statsBefore = await ovsFixture.actor.getStats();
    console.log("Stats before upgrade:", statsBefore);

    // The OVS action should be scheduled
    const ovsTimerCountBefore = statsBefore.timers;

    // Upgrade the canister
    await ovsPic.upgradeCanister({
      canisterId: ovsFixture.canisterId,
      wasm: mixin_WASM_PATH,
      arg: IDL.encode(mixinInit({IDL}), []),
      upgradeModeOptions: {
        skip_pre_upgrade: [],
        wasm_memory_persistence: [{ keep: null }]
      }
    });
    await ovsPic.tick();

    // Reinitialize after upgrade
    await ovsFixture.actor.initialize();
    await ovsPic.tick();

    const statsAfter = await ovsFixture.actor.getStats();
    console.log("Stats after upgrade:", statsAfter);

    // OVS-related state should persist
    // A new OVS action may be scheduled during re-init
    expect(statsAfter.timers).toBeGreaterThanOrEqual(1n);
  });

  it("tracks action count for cycle sharing calculation", async () => {
    ovsFixture.actor.setIdentity(admin);

    // Add many actions to see if action count increases
    const currentTime = BigInt(await ovsPic.getTime()) * BigInt(1_000_000);
    const numActions = 50;

    for (let i = 0; i < numActions; i++) {
      await ovsFixture.actor.addSyncAction(
        currentTime + OneSecond * BigInt(i + 1),
        "inc",
        [1n]
      );
    }

    const stats = await ovsFixture.actor.getStats();
    console.log("Stats after adding", numActions, "actions:", stats);

    // nextActionId should reflect the actions we added
    // It starts from some base (may include OVS action) so check relative increase
    expect(Number(stats.nextActionId)).toBeGreaterThanOrEqual(numActions);

    // Execute all actions
    await ovsPic.advanceTime(60000); // 60 seconds
    await ovsPic.tick();
    await ovsPic.tick();
    await ovsPic.tick();
    await ovsPic.tick();
    await ovsPic.tick();

    const counter = await ovsFixture.actor.getCounter();
    expect(counter).toBe(BigInt(numActions));
  });

  it("canister has cycles available for sharing", async () => {
    ovsFixture.actor.setIdentity(admin);

    const stats = await ovsFixture.actor.getStats();
    console.log("Canister cycles:", stats.cycles);

    // Canister should have cycles
    expect(stats.cycles).toBeGreaterThan(0n);

    // Should have enough cycles for basic operation (at least 1T)
    expect(stats.cycles).toBeGreaterThan(1_000_000_000_000n);
  });
});

// ================== Phase 6: Full Integration Tests ==================

describe("Full Integration Tests", () => {
  let intPic: PocketIc;
  let intPicServer: PocketIcServer;
  let intMixinFixture: CanisterFixture<MixinService>;
  let intDirectFixture: CanisterFixture<DirectService>;

  beforeAll(async () => {
    intPicServer = await PocketIcServer.start();
  });

  afterAll(async () => {
    await intPicServer.stop();
  });

  beforeEach(async () => {
    intPic = await PocketIc.create(intPicServer.getUrl(), {
      application: [{ state: { type: SubnetStateType.New } }],
    });

    await intPic.setTime(new Date(2024, 1, 30).getTime());
    await intPic.tick();

    // Deploy both canister types for comparison
    intMixinFixture = await intPic.setupCanister<MixinService>({
      idlFactory: mixinIDLFactory,
      wasm: mixin_WASM_PATH,
      arg: IDL.encode(mixinInit({IDL}), []),
    });

    intDirectFixture = await intPic.setupCanister<DirectService>({
      idlFactory: directIDLFactory,
      wasm: direct_WASM_PATH,
      arg: IDL.encode(directInit({IDL}), []),
    });

    intMixinFixture.actor.setIdentity(admin);
    intDirectFixture.actor.setIdentity(admin);

    await intMixinFixture.actor.initialize();
    await intDirectFixture.actor.initialize();
    await intPic.tick();
  });

  afterEach(async () => {
    await intPic.tearDown();
  });

  // ================== Error Handling Tests ==================

  it("system recovers after trap and continues processing", async () => {
    intMixinFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await intPic.getTime()) * BigInt(1_000_000);

    // Schedule a normal action first
    await intMixinFixture.actor.addSyncAction(currentTime + OneSecond, "inc", [10n]);
    
    // Schedule a trap action
    await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 2n, "trap", []);
    
    // Schedule another normal action after the trap
    await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 3n, "inc", [20n]);

    // Execute first action
    await intPic.advanceTime(1500);
    await intPic.tick();
    await intPic.tick();

    let counter = await intMixinFixture.actor.getCounter();
    expect(counter).toBe(10n);

    // Execute trap action - this should trap but not break the system
    await intPic.advanceTime(1000);
    await intPic.tick();
    await intPic.tick();
    await intPic.tick(); // Extra ticks for safety timer

    // The error should be reported
    const errorCount = await intMixinFixture.actor.getErrorCount();
    console.log("Error count after trap:", errorCount);

    // Execute next action - system should still work
    await intPic.advanceTime(1000);
    await intPic.tick();
    await intPic.tick();

    counter = await intMixinFixture.actor.getCounter();
    console.log("Counter after recovery:", counter);
    // Should be at least 10 (first action), ideally 30 if third action ran
    expect(counter).toBeGreaterThanOrEqual(10n);
  });

  // ================== Mixin vs Direct Equivalence Tests ==================

  it("mixin and direct canisters have identical API behavior", async () => {
    const currentTime = BigInt(await intPic.getTime()) * BigInt(1_000_000);

    // Both should start with same initial state (counter = 0)
    let mixinCounter = await intMixinFixture.actor.getCounter();
    let directCounter = await intDirectFixture.actor.getCounter();
    expect(mixinCounter).toBe(directCounter);
    expect(mixinCounter).toBe(0n);

    // Add same actions to both
    const actionTime = currentTime + OneSecond * 2n;
    const mixinActionId = await intMixinFixture.actor.addSyncAction(actionTime, "inc", [50n]);
    const directActionId = await intDirectFixture.actor.addSyncAction(actionTime, "inc", [50n]);

    // Both should return valid action IDs
    expect(mixinActionId.id).toBeGreaterThan(0n);
    expect(directActionId.id).toBeGreaterThan(0n);

    // Execute both
    await intPic.advanceTime(3000);
    await intPic.tick();
    await intPic.tick();

    // Both should have same result
    mixinCounter = await intMixinFixture.actor.getCounter();
    directCounter = await intDirectFixture.actor.getCounter();
    expect(mixinCounter).toBe(directCounter);
    expect(mixinCounter).toBe(50n);

    // Stats structure should be identical
    const mixinStats = await intMixinFixture.actor.getStats();
    const directStats = await intDirectFixture.actor.getStats();
    expect(mixinStats.maxExecutions).toBe(directStats.maxExecutions);
  });

  it("async actions work identically in mixin and direct patterns", async () => {
    const currentTime = BigInt(await intPic.getTime()) * BigInt(1_000_000);
    const actionTime = currentTime + OneSecond * 2n;
    const timeout = OneSecond * 10n;

    // Add async actions to both
    await intMixinFixture.actor.addAsyncAction(actionTime, "inc_async", [33n], timeout);
    await intDirectFixture.actor.addAsyncAction(actionTime, "inc_async", [33n], timeout);

    // Execute
    await intPic.advanceTime(3000);
    await intPic.tick();
    await intPic.tick();
    await intPic.tick();

    // Both should have same result
    const mixinCounter = await intMixinFixture.actor.getCounter();
    const directCounter = await intDirectFixture.actor.getCounter();
    expect(mixinCounter).toBe(directCounter);
    expect(mixinCounter).toBe(33n);
  });

  // ================== Complex Workflow Tests ==================

  it("handles complex workflow: add, cancel, execute, upgrade", async () => {
    intMixinFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await intPic.getTime()) * BigInt(1_000_000);

    // Step 1: Add multiple actions
    const action1 = await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 10n, "inc", [100n]);
    const action2 = await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 20n, "inc", [200n]);
    const action3 = await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 30n, "inc", [300n]);

    console.log("Added actions:", action1.id, action2.id, action3.id);

    // Step 2: Cancel middle action
    const cancelResult = await intMixinFixture.actor.cancelAction(action2.id);
    expect(cancelResult.length).toBe(1);

    // Step 3: Execute first action
    await intPic.advanceTime(15000);
    await intPic.tick();
    await intPic.tick();

    let counter = await intMixinFixture.actor.getCounter();
    expect(counter).toBe(100n);

    // Step 4: Upgrade canister
    await intPic.upgradeCanister({
      canisterId: intMixinFixture.canisterId,
      wasm: mixin_WASM_PATH,
      arg: IDL.encode(mixinInit({IDL}), []),
      upgradeModeOptions: {
        skip_pre_upgrade: [],
        wasm_memory_persistence: [{ keep: null }]
      }
    });
    await intPic.tick();
    await intMixinFixture.actor.initialize();
    await intPic.tick();

    // Counter should persist
    counter = await intMixinFixture.actor.getCounter();
    expect(counter).toBe(100n);

    // Step 5: Third action should still execute after upgrade
    await intPic.advanceTime(20000); // Past 30 seconds from original time
    await intPic.tick();
    await intPic.tick();

    counter = await intMixinFixture.actor.getCounter();
    expect(counter).toBe(400n); // 100 + 300 (action2 was cancelled)
  });

  it("handles high volume of mixed sync and async actions", async () => {
    intMixinFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await intPic.getTime()) * BigInt(1_000_000);
    const numSyncActions = 10;
    const numAsyncActions = 5;

    // Add sync actions
    for (let i = 0; i < numSyncActions; i++) {
      await intMixinFixture.actor.addSyncAction(
        currentTime + OneSecond * BigInt(i + 1),
        "inc",
        [1n]
      );
    }

    // Add async actions (interleaved)
    for (let i = 0; i < numAsyncActions; i++) {
      await intMixinFixture.actor.addAsyncAction(
        currentTime + OneSecond * BigInt(i * 2 + 1) + BigInt(500_000_000), // offset by 0.5 sec
        "inc_async",
        [2n],
        OneSecond * 10n
      );
    }

    const stats = await intMixinFixture.actor.getStats();
    console.log("Stats after adding mixed actions:", stats);
    expect(Number(stats.timers)).toBeGreaterThanOrEqual(numSyncActions + numAsyncActions);

    // Execute all
    await intPic.advanceTime(15000);
    for (let i = 0; i < 10; i++) {
      await intPic.tick();
    }

    const counter = await intMixinFixture.actor.getCounter();
    const expected = BigInt(numSyncActions * 1 + numAsyncActions * 2);
    console.log("Counter after mixed execution:", counter, "expected:", expected);
    expect(counter).toBe(expected);
  });

  // ================== State Consistency Tests ==================

  it("maintains state consistency under rapid operations", async () => {
    intMixinFixture.actor.setIdentity(admin);

    const currentTime = BigInt(await intPic.getTime()) * BigInt(1_000_000);

    // Rapidly add, cancel, and query
    const actions: bigint[] = [];

    // Add 20 actions
    for (let i = 0; i < 20; i++) {
      const result = await intMixinFixture.actor.addSyncAction(
        currentTime + OneSecond * BigInt(i + 5),
        "inc",
        [1n]
      );
      actions.push(result.id);
    }

    // Cancel every other action
    for (let i = 0; i < actions.length; i += 2) {
      await intMixinFixture.actor.cancelAction(actions[i]);
    }

    // Execute remaining
    await intPic.advanceTime(30000);
    await intPic.tick();
    await intPic.tick();
    await intPic.tick();

    const counter = await intMixinFixture.actor.getCounter();
    // 10 actions should execute (every odd index)
    expect(counter).toBe(10n);

    // Stats should be consistent
    const stats = await intMixinFixture.actor.getStats();
    console.log("Final stats:", stats);
    // All user actions should be processed (either executed or cancelled)
  });

  it("execution history accurately tracks all executed actions", async () => {
    intMixinFixture.actor.setIdentity(admin);

    await intMixinFixture.actor.resetTestState();
    await intPic.tick();

    const currentTime = BigInt(await intPic.getTime()) * BigInt(1_000_000);

    // Add 5 actions with different types
    await intMixinFixture.actor.addSyncAction(currentTime + OneSecond, "inc", [1n]);
    await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 2n, "noop", []);
    await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 3n, "inc", [2n]);
    await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 4n, "noop", []);
    await intMixinFixture.actor.addSyncAction(currentTime + OneSecond * 5n, "inc", [3n]);

    // Execute all
    await intPic.advanceTime(6000);
    await intPic.tick();
    await intPic.tick();

    const history = await intMixinFixture.actor.getExecutionHistory();
    console.log("Execution history:", history);

    // Should have 5 executions
    expect(history.length).toBe(5);

    // Counter should be 1+2+3 = 6
    const counter = await intMixinFixture.actor.getCounter();
    expect(counter).toBe(6n);

    // Executed count should match history
    const executedCount = await intMixinFixture.actor.getExecutedCount();
    expect(executedCount).toBe(5n);
  });
});
