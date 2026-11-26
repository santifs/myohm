import {
  MAX_SWEEP_FREQUENCY_HZ,
  validateConfig,
  type MeasurementPoint,
  type MeasurementRun,
  type SweepConfig,
} from "../core";

export const UUIDS = Object.freeze({
  controlService: "0000af00-0000-1000-8000-00805f9b34fb",
  configService: "0000af01-0000-1000-8000-00805f9b34fb",
  environmentService: "0000af03-0000-1000-8000-00805f9b34fb",
  command: "0000c000-0000-1000-8000-00805f9b34fb",
  serial: "0000c001-0000-1000-8000-00805f9b34fb",
  sweepEnable: "0000c012-0000-1000-8000-00805f9b34fb",
  sweepStart: "0000c013-0000-1000-8000-00805f9b34fb",
  sweepStop: "0000c014-0000-1000-8000-00805f9b34fb",
  sweepPoints: "0000c015-0000-1000-8000-00805f9b34fb",
  repetitions: "0000c017-0000-1000-8000-00805f9b34fb",
  battery: "0000c202-0000-1000-8000-00805f9b34fb",
});

const MEASUREMENT_TIMEOUT_MS = 30_000;
const NOTIFICATION_CLEANUP_TIMEOUT_MS = 3_000;
const COMMAND_MEASUREMENT = 0x01;
const COMMAND_BATTERY_MANUAL = 0x02;
const COMMAND_STOP_AUTO = 0x06;

type ConnectedCharacteristics = {
  command: BluetoothRemoteGATTCharacteristic;
  serial: BluetoothRemoteGATTCharacteristic;
  enable: BluetoothRemoteGATTCharacteristic;
  start: BluetoothRemoteGATTCharacteristic;
  stop: BluetoothRemoteGATTCharacteristic;
  points: BluetoothRemoteGATTCharacteristic;
  repetitions: BluetoothRemoteGATTCharacteristic;
  battery: BluetoothRemoteGATTCharacteristic | null;
};

function copyBytes(view: DataView): Uint8Array {
  return new Uint8Array(
    view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength),
  );
}

function float32(value: number): Uint8Array {
  const buffer = new ArrayBuffer(4);
  new DataView(buffer).setFloat32(0, value, true);
  return new Uint8Array(buffer);
}

function uint32(value: number): Uint8Array {
  const buffer = new ArrayBuffer(4);
  new DataView(buffer).setUint32(0, value, true);
  return new Uint8Array(buffer);
}

async function write(
  characteristic: BluetoothRemoteGATTCharacteristic,
  value: Uint8Array,
): Promise<void> {
  await characteristic.writeValueWithResponse(new Uint8Array(value).buffer);
}

async function withTimeout<T>(
  operation: Promise<T>,
  timeoutMs: number,
  action: string,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`${action} timed out after ${timeoutMs} ms`)),
      timeoutMs,
    );
  });
  try {
    return await Promise.race([operation, timeout]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}

function runId(): string {
  return globalThis.crypto?.randomUUID?.() ?? `ble-${Date.now()}`;
}

export class BioMessClient {
  private device: BluetoothDevice | null = null;
  private characteristics: ConnectedCharacteristics | null = null;
  private measuring = false;
  private connectedSerial: string | undefined;
  private rejectMeasurement: ((reason: Error) => void) | null = null;
  private explicitDisconnect = false;
  private connecting = false;

  constructor(private readonly onDisconnected?: () => void) {}

  private readonly handleDisconnect = (): void => {
    const wasExplicit = this.explicitDisconnect;
    this.characteristics = null;
    this.connectedSerial = undefined;
    this.measuring = false;
    this.rejectMeasurement?.(
      new Error(
        "BioMess disconnected during measurement; reconnect before retrying",
      ),
    );
    this.rejectMeasurement = null;
    if (!wasExplicit) this.onDisconnected?.();
  };

  async connect(): Promise<{
    serial: string;
    batteryPercent: number | null;
    batteryMv: number | null;
  }> {
    if (this.connecting)
      throw new Error("A BioMess connection attempt is already active");
    if (this.measuring)
      throw new Error("Cannot connect while a measurement is active");
    this.connecting = true;
    try {
      return await this.connectImpl();
    } finally {
      this.connecting = false;
    }
  }

  private async connectImpl(): Promise<{
    serial: string;
    batteryPercent: number | null;
    batteryMv: number | null;
  }> {
    this.disconnect();
    this.explicitDisconnect = false;

    const bluetooth = navigator.bluetooth;
    if (!bluetooth)
      throw new Error("Web Bluetooth is unavailable in this browser");

    const device = await bluetooth.requestDevice({
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
    this.device = device;
    device.addEventListener("gattserverdisconnected", this.handleDisconnect);

    try {
      const server = await device.gatt?.connect();
      if (!server)
        throw new Error("Selected BioMess device has no GATT server");
      const control = await server.getPrimaryService(UUIDS.controlService);
      const config = await server.getPrimaryService(UUIDS.configService);
      let environment: BluetoothRemoteGATTService | null = null;
      try {
        environment = await server.getPrimaryService(UUIDS.environmentService);
      } catch {
        // Battery is informative and must not prevent measurement.
      }

      const characteristics: ConnectedCharacteristics = {
        command: await control.getCharacteristic(UUIDS.command),
        serial: await control.getCharacteristic(UUIDS.serial),
        enable: await config.getCharacteristic(UUIDS.sweepEnable),
        start: await config.getCharacteristic(UUIDS.sweepStart),
        stop: await config.getCharacteristic(UUIDS.sweepStop),
        points: await config.getCharacteristic(UUIDS.sweepPoints),
        repetitions: await config.getCharacteristic(UUIDS.repetitions),
        battery: environment
          ? await environment.getCharacteristic(UUIDS.battery).catch(() => null)
          : null,
      };
      this.characteristics = characteristics;

      // A previous central may have enabled periodic sweeps. Stop them before any app command.
      await write(characteristics.command, new Uint8Array([COMMAND_STOP_AUTO]));
      const serialValue = await characteristics.serial.readValue();
      const serial = new TextDecoder()
        .decode(copyBytes(serialValue))
        .replace(/\0+$/, "");
      this.connectedSerial = serial;

      let batteryMv: number | null = null;
      let batteryPercent: number | null = null;
      if (characteristics.battery) {
        try {
          const battery = await characteristics.battery.readValue();
          if (battery.byteLength >= 4) {
            batteryMv = battery.getUint16(0, true);
            batteryPercent = battery.getUint16(2, true);
          }
          if (batteryMv === 0) {
            const updated = await this.requestBatteryUpdate(
              characteristics.command,
              characteristics.battery,
            );
            batteryMv = updated?.batteryMv ?? null;
            batteryPercent = updated?.batteryPercent ?? null;
          }
        } catch {
          // Keep the connection usable if the optional battery read fails.
        }
      }
      return { serial, batteryPercent, batteryMv };
    } catch (error) {
      this.cleanupConnection();
      throw error;
    }
  }

  private async requestBatteryUpdate(
    command: BluetoothRemoteGATTCharacteristic,
    battery: BluetoothRemoteGATTCharacteristic,
  ): Promise<{ batteryMv: number; batteryPercent: number } | null> {
    let listener: ((event: Event) => void) | null = null;
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      await battery.startNotifications();
      const notification = new Promise<{ batteryMv: number; batteryPercent: number } | null>(
        (resolve) => {
          listener = (event: Event) => {
            const value = (event.target as BluetoothRemoteGATTCharacteristic).value;
            if (!value || value.byteLength < 4) return;
            const batteryMv = value.getUint16(0, true);
            resolve(batteryMv > 0 ? {
              batteryMv,
              batteryPercent: value.getUint16(2, true),
            } : null);
          };
          battery.addEventListener("characteristicvaluechanged", listener);
          timer = setTimeout(() => resolve(null), 1_500);
        },
      );
      await write(command, new Uint8Array([COMMAND_BATTERY_MANUAL]));
      return await notification;
    } catch {
      return null;
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      if (listener) battery.removeEventListener("characteristicvaluechanged", listener);
      try { await battery.stopNotifications(); } catch { /* optional telemetry */ }
    }
  }

  disconnect(): void {
    this.explicitDisconnect = true;
    this.rejectMeasurement?.(new Error("Measurement cancelled by disconnect"));
    this.rejectMeasurement = null;
    this.measuring = false;
    this.cleanupConnection();
  }

  private cleanupConnection(): void {
    const device = this.device;
    device?.removeEventListener(
      "gattserverdisconnected",
      this.handleDisconnect,
    );
    if (device?.gatt?.connected) device.gatt.disconnect();
    this.device = null;
    this.characteristics = null;
    this.connectedSerial = undefined;
  }

  async measure(
    config: SweepConfig,
    onProgress?: (
      points: MeasurementPoint[],
      receivedBytes: number,
      expectedBytes: number,
    ) => void,
  ): Promise<MeasurementRun> {
    validateConfig(config);
    if (config.endHz > MAX_SWEEP_FREQUENCY_HZ) {
      throw new RangeError("La frecuencia final del barrido BLE debe ser de 198 000 Hz o menos.");
    }
    if (this.measuring)
      throw new Error("A BioMess measurement is already active");
    const chars = this.characteristics;
    if (!chars || !this.device?.gatt?.connected)
      throw new Error("Connect to a BioMess device before measuring");
    this.measuring = true;
    const startedAt = new Date().toISOString();
    const totalStart = performance.now();

    let listener: ((event: Event) => void) | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;
    try {
      await withTimeout(
        write(chars.enable, new Uint8Array([1])),
        MEASUREMENT_TIMEOUT_MS,
        "Sweep enable write",
      );
      await withTimeout(
        write(chars.start, float32(config.startHz)),
        MEASUREMENT_TIMEOUT_MS,
        "Sweep start write",
      );
      await withTimeout(
        write(chars.stop, float32(config.endHz)),
        MEASUREMENT_TIMEOUT_MS,
        "Sweep stop write",
      );
      await withTimeout(
        write(chars.points, uint32(config.points)),
        MEASUREMENT_TIMEOUT_MS,
        "Sweep points write",
      );
      await withTimeout(
        write(chars.repetitions, new Uint8Array([config.repetitions])),
        MEASUREMENT_TIMEOUT_MS,
        "Repetitions write",
      );

      // The firmware may clamp values; the stream length must use its effective config.
      const startView = await withTimeout(
        chars.start.readValue(),
        MEASUREMENT_TIMEOUT_MS,
        "Sweep start readback",
      );
      const stopView = await withTimeout(
        chars.stop.readValue(),
        MEASUREMENT_TIMEOUT_MS,
        "Sweep stop readback",
      );
      const pointsView = await withTimeout(
        chars.points.readValue(),
        MEASUREMENT_TIMEOUT_MS,
        "Sweep points readback",
      );
      const repetitionsView = await withTimeout(
        chars.repetitions.readValue(),
        MEASUREMENT_TIMEOUT_MS,
        "Repetitions readback",
      );
      const effective: SweepConfig = {
        startHz: startView.getFloat32(0, true),
        endHz: stopView.getFloat32(0, true),
        points: pointsView.getUint32(0, true),
        repetitions: repetitionsView.getUint8(0),
      };
      validateConfig(effective);
      if (effective.endHz > MAX_SWEEP_FREQUENCY_HZ) {
        throw new RangeError("La frecuencia final informada por el dispositivo supera los 198 000 Hz.");
      }
      const configuredAt = performance.now();
      const expectedBytes = effective.points * effective.repetitions * 12;
      const timeoutMs = Math.max(
        MEASUREMENT_TIMEOUT_MS,
        effective.points * effective.repetitions * 150,
      );
      const bytes = new Uint8Array(expectedBytes);
      const rawChunks: number[][] = [];
      const parsed: MeasurementPoint[] = [];
      let receivedBytes = 0;
      let parsedBytes = 0;
      let firstDataAt: number | null = null;

      const completion = new Promise<MeasurementRun>((resolve, reject) => {
        this.rejectMeasurement = reject;
        listener = (event: Event): void => {
          const value = (event.target as BluetoothRemoteGATTCharacteristic)
            .value;
          if (!value) return;
          const chunk = copyBytes(value);
          if (firstDataAt === null) firstDataAt = performance.now();
          rawChunks.push(Array.from(chunk));
          if (receivedBytes + chunk.byteLength > expectedBytes) {
            reject(
              new Error(
                `Measurement stream exceeded expected ${expectedBytes} bytes`,
              ),
            );
            return;
          }
          bytes.set(chunk, receivedBytes);
          receivedBytes += chunk.byteLength;

          while (receivedBytes - parsedBytes >= 12) {
            const view = new DataView(bytes.buffer, parsedBytes, 12);
            const frequency = view.getFloat32(0, true);
            const magnitude = view.getFloat32(4, true);
            const phase = view.getFloat32(8, true);
            const valid =
              Number.isFinite(frequency) &&
              frequency > 0 &&
              Number.isFinite(magnitude) &&
              magnitude >= 0 &&
              Number.isFinite(phase);
            const linearIndex = parsed.length;
            const repetition = Math.floor(linearIndex / effective.points);
            const index = linearIndex % effective.points;
            const phaseRadians = (phase * Math.PI) / 180;
            parsed.push({
              frequency,
              magnitude,
              phase,
              resistance: valid
                ? magnitude * Math.cos(phaseRadians)
                : Number.NaN,
              reactance: valid
                ? magnitude * Math.sin(phaseRadians)
                : Number.NaN,
              repetition,
              index,
              valid,
            });
            parsedBytes += 12;
          }
          onProgress?.([...parsed], receivedBytes, expectedBytes);
          if (receivedBytes === expectedBytes) {
            const completedAt = performance.now();
            resolve({
              id: runId(),
              startedAt,
              source: "ble",
              config: effective,
              points: parsed,
              serial: this.connectedSerial,
              rawChunks,
              timing: {
                configMs: configuredAt - totalStart,
                firstDataMs: firstDataAt === null ? undefined : firstDataAt - totalStart,
                receiveMs: firstDataAt === null ? undefined : completedAt - firstDataAt,
                totalMs: completedAt - totalStart,
              },
            });
          }
        };
        chars.command.addEventListener("characteristicvaluechanged", listener);
      });
      // Mark the receive promise handled while notification setup and the opcode write are in flight.
      void completion.catch(() => undefined);

      await withTimeout(
        chars.command.startNotifications(),
        timeoutMs,
        "Notification subscription",
      );
      timer = setTimeout(
        () =>
          this.rejectMeasurement?.(
            new Error(`Measurement timed out after ${timeoutMs} ms`),
          ),
        timeoutMs,
      );
      await withTimeout(
        write(chars.command, new Uint8Array([COMMAND_MEASUREMENT])),
        timeoutMs,
        "Measurement command",
      );
      return await completion;
    } catch (error) {
      // The protocol is unframed, so a partial/failed stream cannot be resumed safely.
      this.rejectMeasurement?.(
        error instanceof Error ? error : new Error(String(error)),
      );
      const shouldNotifyDisconnect = this.characteristics !== null;
      this.cleanupConnection();
      if (shouldNotifyDisconnect) this.onDisconnected?.();
      throw error;
    } finally {
      if (timer !== null) clearTimeout(timer);
      if (listener)
        chars.command.removeEventListener(
          "characteristicvaluechanged",
          listener,
        );
      try {
        await withTimeout(
          chars.command.stopNotifications(),
          NOTIFICATION_CLEANUP_TIMEOUT_MS,
          "Notification cleanup",
        );
      } catch {
        // It may already be disconnected.
      }
      this.rejectMeasurement = null;
      this.measuring = false;
    }
  }
}
