import { describe, expect, it } from "vitest";
import { logTicks } from "./Plots";

describe("logarithmic frequency axis", () => {
  it("uses the expected 1-2-5 ticks across the BioMess range", () => {
    expect(logTicks(4_000, 200_000)).toEqual([5_000, 10_000, 20_000, 50_000, 100_000, 200_000]);
  });
});
