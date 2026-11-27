import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { BioMessClient, UUIDS } from "./index";
import type { SweepConfig } from "../core";

const CONFIG: SweepConfig = {
  startHz: 1_000,
  endHz: 4_000,
  points: 3,
  repetitions: 1,
};

function view(bytes: Uint8Array): DataView {
  return new DataView(new Uint8Array(bytes).buffer);
}

function f32(value: number): Uint8Array {
  const bytes = new Uint8Array(4);
  new DataView(bytes.buffer).setFloat32(0, value, true);
  return bytes;
}

function u32(value: number): Uint8Array {
  const bytes = new Uint8Array(4);
  new DataView(bytes.buffer).setUint32(0, value, true);
  return bytes;
}

function payload(rows: Array<[number, number, number]>): Uint8Array {
  const bytes = new Uint8Array(rows.length * 12);
  const data = new DataView(bytes.buffer);
  rows.forEach(([frequency, magnitude, phase], index) => {
    data.setFloat32(index * 12, frequency, true);
    data.setFloat32(index * 12 + 4, magnitude, true);
    data.setFloat32(index * 12 + 8, phase, true);
  });
  return bytes;
}

class FakeCharacteristic extends EventTarget {
  value: DataView | null = null;
  read: Uint8Array<ArrayBufferLike> = new Uint8Array();
  onWrite?: (value: Uint8Array) => void;
  readValue = vi.fn(async () => view(this.read));
  writeValueWithResponse = vi.fn(async (input: BufferSource) => {
    const bytes =
      input instanceof ArrayBuffer
        ? new Uint8Array(input)
        : new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
    this.onWrite?.(new Uint8Array(bytes));
  });
  startNotifications = vi.fn(async () => this);
  stopNotifications = vi.fn(async () => this);

  notify(bytes: Uint8Array): void {
    this.value = view(bytes);
    this.dispatchEvent(new Event("characteristicvaluechanged"));
  }
}

type Harness = ReturnType<typeof makeHarness>;

function makeHarness(
  rows: Array<[number, number, number]> = [
    [1_000, 10, 0],
    [2_000, 20, -90],
    [4_000, 30, 180],
  ],
) {
  const chars = {
    command: new FakeCharacteristic(),
    serial: new FakeCharacteristic(),
    enable: new FakeCharacteristic(),
    start: new FakeCharacteristic(),
    stop: new FakeCharacteristic(),
    points: new FakeCharacteristic(),
    repetitions: new FakeCharacteristic(),
    battery: new FakeCharacteristic(),
  };
  chars.serial.read = new TextEncoder().encode("BM-42\0");
  chars.start.read = f32(CONFIG.startHz);
  chars.stop.read = f32(CONFIG.endHz);
  chars.points.read = u32(CONFIG.points);
  chars.repetitions.read = new Uint8Array([CONFIG.repetitions]);
  chars.battery.read = new Uint8Array([0x74, 0x0e, 87, 0]);

  const control = {
    getCharacteristic: vi.fn(async (uuid: string) =>
      uuid === UUIDS.command ? chars.command : chars.serial,
    ),
  };
  const config = {
    getCharacteristic: vi.fn(
      async (uuid: string) =>
        ({
          [UUIDS.sweepStart]: chars.start,
          [UUIDS.sweepEnable]: chars.enable,
          [UUIDS.sweepStop]: chars.stop,
          [UUIDS.sweepPoints]: chars.points,
          [UUIDS.repetitions]: chars.repetitions,
        })[uuid]!,
    ),
  };
  const environment = { getCharacteristic: vi.fn(async () => chars.battery) };
  const server = {
    connected: true,
    getPrimaryService: vi.fn(async (uuid: string) => {
      if (uuid === UUIDS.controlService) return control;
      if (uuid === UUIDS.configService) return config;
      return environment;
    }),
  };
  const device = new EventTarget() as EventTarget & {
    gatt: typeof server & {
      connect: ReturnType<typeof vi.fn>;
      disconnect: ReturnType<typeof vi.fn>;
    };
  };
  device.gatt = Object.assign(server, {
    connect: vi.fn(async () => server),
    disconnect: vi.fn(() => {
      server.connected = false;
    }),
  });
  const requestDevice = vi.fn(async () => device);
  Object.defineProperty(globalThis.navigator, "bluetooth", {
    configurable: true,
    value: { requestDevice },
  });
  return { chars, device, server, requestDevice, stream: payload(rows) };
}

async function connectedClient(
  harness: Harness,
  onDisconnected?: () => void,
): Promise<BioMessClient> {
  const client = new BioMessClient(onDisconnected);
  await client.connect();
  return client;
}

describe("BioMessClient", () => {
  beforeEach(() => {
    Object.defineProperty(globalThis, "navigator", {
      configurable: true,
      value: {},
    });
  });

  afterEach(() => vi.useRealTimers());

  it("discovers a Messi-06 advertisement with no service UUID", async () => {
    const harness = makeHarness();
    harness.requestDevice.mockImplementation(async (...args: unknown[]) => {
      const options = args[0] as RequestDeviceOptions;
      const visible = "filters" in options && options.filters?.some(filter =>
        filter.namePrefix !== undefined && "Messi-06".startsWith(filter.namePrefix)
      );
      if (!visible) throw new Error("No matching advertisement");
      return harness.device;
    });
    await expect(new BioMessClient().connect()).resolves.toMatchObject({ serial: "BM-42" });
  });

  it("uses full UUID discovery, stops auto mode first, and reads identity/battery", async () => {
    const harness = makeHarness();
    const client = new BioMessClient();
    await expect(client.connect()).resolves.toEqual({
      serial: "BM-42",
      batteryMv: 3700,
      batteryPercent: 87,
    });
    expect(harness.requestDevice).toHaveBeenCalledWith({
      filters: [
        { services: [UUIDS.controlService] },
        { namePrefix: "BioMess" },
        { namePrefix: "Messi-" },
      ],
      optionalServices: [
        UUIDS.controlService,
        UUIDS.configService,
        UUIDS.environmentService,
      ],
    });
    const stopWrite = harness.chars.command.writeValueWithResponse.mock
      .calls[0][0] as ArrayBuffer;
    expect(Array.from(new Uint8Array(stopWrite))).toEqual([0x06]);
  });

  it("treats an initial 0 mV battery as unavailable and requests one manual update", async () => {
    const harness = makeHarness();
    harness.chars.battery.read = new Uint8Array([0, 0, 0, 0]);
    harness.chars.command.onWrite = (command) => {
      if (command[0] === 0x02)
        queueMicrotask(() => harness.chars.battery.notify(new Uint8Array([0x74, 0x0e, 87, 0])));
    };
    await expect(new BioMessClient().connect()).resolves.toMatchObject({ batteryMv: 3700, batteryPercent: 87 });
    expect(harness.chars.battery.startNotifications).toHaveBeenCalledOnce();
    const commands = harness.chars.command.writeValueWithResponse.mock.calls.map((call) => Array.from(new Uint8Array(call[0] as ArrayBuffer)));
    expect(commands).toEqual([[0x06], [0x02]]);
  });

  it("rejects 200 kHz before sending any configuration writes", async () => {
    const harness = makeHarness();
    const client = await connectedClient(harness);
    await expect(client.measure({
      startHz: 4_000, endHz: 200_000, points: 2, repetitions: 1,
    })).rejects.toThrow("198 000 Hz");
    expect(harness.chars.enable.writeValueWithResponse).not.toHaveBeenCalled();
  });

  it("reassembles a point stream split at every possible byte offset", async () => {
    for (let offset = 1; offset < 36; offset += 1) {
      const harness = makeHarness();
      harness.chars.command.onWrite = (command) => {
        if (command[0] === 0x01)
          queueMicrotask(() => {
            harness.chars.command.notify(harness.stream.slice(0, offset));
            harness.chars.command.notify(harness.stream.slice(offset));
          });
      };
      const client = await connectedClient(harness);
      const progress = vi.fn();
      const run = await client.measure(CONFIG, progress);
      expect(run.points).toHaveLength(3);
      expect(run.points[1]).toMatchObject({
        repetition: 0,
        index: 1,
        phase: -90,
        resistance: expect.closeTo(0, 5),
        reactance: -20,
        valid: true,
      });
      expect(run.rawChunks.map((chunk) => chunk.length)).toEqual([
        offset,
        36 - offset,
      ]);
      expect(run.serial).toBe("BM-42");
      expect(run.timing).toMatchObject({
        configMs: expect.any(Number),
        firstDataMs: expect.any(Number),
        receiveMs: expect.any(Number),
        totalMs: expect.any(Number),
      });
      expect(progress).toHaveBeenLastCalledWith(run.points, 36, 36);
    }
  });

  it("uses firmware readback and marks non-finite/negative point fields invalid", async () => {
    const harness = makeHarness([
      [1_000, Number.NaN, 0],
      [2_000, -1, 0],
    ]);
    harness.chars.points.read = u32(2);
    harness.chars.command.onWrite = (command) => {
      if (command[0] === 0x01)
        queueMicrotask(() => harness.chars.command.notify(harness.stream));
    };
    const client = await connectedClient(harness);
    const run = await client.measure({ ...CONFIG, repetitions: 2 });
    expect(run.config.points).toBe(2);
    expect(run.config.repetitions).toBe(1);
    expect(run.points.map((point) => point.valid)).toEqual([false, false]);
    expect(run.points.every((point) => Number.isNaN(point.resistance))).toBe(
      true,
    );
  });

  it("rejects overlap and disconnects after an oversized unrecoverable stream", async () => {
    const harness = makeHarness();
    harness.chars.command.onWrite = (command) => {
      if (command[0] === 0x01)
        queueMicrotask(() => harness.chars.command.notify(new Uint8Array(37)));
    };
    const client = await connectedClient(harness);
    const first = client.measure(CONFIG);
    const firstRejection = expect(first).rejects.toThrow("exceeded expected");
    await expect(client.measure(CONFIG)).rejects.toThrow("already active");
    await firstRejection;
    expect(harness.device.gatt.disconnect).toHaveBeenCalled();
  });

  it("rejects an active measurement on unexpected disconnection and invokes callback", async () => {
    const harness = makeHarness();
    const disconnected = vi.fn();
    const client = await connectedClient(harness, disconnected);
    const measurement = client.measure(CONFIG);
    await vi.waitFor(() =>
      expect(harness.chars.command.startNotifications).toHaveBeenCalled(),
    );
    harness.device.dispatchEvent(new Event("gattserverdisconnected"));
    await expect(measurement).rejects.toThrow(
      "disconnected during measurement",
    );
    expect(disconnected).toHaveBeenCalledOnce();
  });

  it("cleans up partial connect failures so a later connect can retry", async () => {
    const harness = makeHarness();
    harness.server.getPrimaryService.mockRejectedValueOnce(
      new Error("GATT discovery failed"),
    );
    const client = new BioMessClient();
    await expect(client.connect()).rejects.toThrow("GATT discovery failed");
    expect(harness.device.gatt.disconnect).toHaveBeenCalled();

    const retry = makeHarness();
    await expect(client.connect()).resolves.toMatchObject({ serial: "BM-42" });
    expect(retry.requestDevice).toHaveBeenCalledOnce();
  });

  it("times out and disconnects an incomplete unframed stream", async () => {
    vi.useFakeTimers();
    const harness = makeHarness();
    const client = await connectedClient(harness);
    const measurement = client.measure(CONFIG);
    const rejection = expect(measurement).rejects.toThrow(
      "timed out after 30000 ms",
    );
    await vi.advanceTimersByTimeAsync(30_000);
    await rejection;
    expect(harness.device.gatt.disconnect).toHaveBeenCalled();
  });

  it("times out a hung notification subscription without sending the measurement opcode", async () => {
    vi.useFakeTimers();
    const harness = makeHarness();
    harness.chars.command.startNotifications.mockImplementation(
      () => new Promise(() => {}),
    );
    const client = await connectedClient(harness);
    const measurement = client.measure(CONFIG);
    const rejection = measurement.then(
      () => {
        throw new Error("Expected measurement to reject");
      },
      (error: Error) =>
        expect(error.message).toBe(
          "Notification subscription timed out after 30000 ms",
        ),
    );
    for (
      let index = 0;
      index < 200 &&
      harness.chars.command.startNotifications.mock.calls.length === 0;
      index += 1
    ) {
      await Promise.resolve();
    }
    expect(harness.chars.command.startNotifications).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(30_000);
    await rejection;
    expect(harness.chars.command.writeValueWithResponse).toHaveBeenCalledOnce();
    expect(harness.device.gatt.disconnect).toHaveBeenCalled();
  });

  it("guards concurrent connection attempts", async () => {
    const harness = makeHarness();
    let finishRequest!: (device: typeof harness.device) => void;
    harness.requestDevice.mockImplementation(
      () =>
        new Promise((resolve) => {
          finishRequest = resolve;
        }),
    );
    const client = new BioMessClient();
    const first = client.connect();
    await expect(client.connect()).rejects.toThrow(
      "connection attempt is already active",
    );
    finishRequest(harness.device);
    await expect(first).resolves.toMatchObject({ serial: "BM-42" });
  });

  it("returns after bounded cleanup when stopNotifications hangs", async () => {
    vi.useFakeTimers();
    const harness = makeHarness();
    harness.chars.command.stopNotifications.mockImplementation(
      () => new Promise(() => {}),
    );
    harness.chars.command.onWrite = (command) => {
      if (command[0] === 0x01)
        queueMicrotask(() => harness.chars.command.notify(harness.stream));
    };
    const client = await connectedClient(harness);
    const measurement = client.measure(CONFIG);
    for (
      let index = 0;
      index < 200 &&
      harness.chars.command.stopNotifications.mock.calls.length === 0;
      index += 1
    ) {
      await Promise.resolve();
    }
    expect(harness.chars.command.stopNotifications).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(3_000);
    await expect(measurement).resolves.toMatchObject({
      source: "ble",
      serial: "BM-42",
    });
  });
});
