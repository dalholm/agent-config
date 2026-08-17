import assert from "node:assert/strict";
import { test } from "node:test";
import { applyRecommendedSampling } from "./model-sampling.ts";

test("applies the recommended sampler for each retained local model", () => {
  assert.deepEqual(applyRecommendedSampling({ model: "qwen3.8-27b" }), {
    model: "qwen3.8-27b",
    temperature: 0.6,
    top_p: 0.95,
    top_k: 20,
  });
  assert.deepEqual(applyRecommendedSampling({ model: "meta/muse-glimmer" }), {
    model: "meta/muse-glimmer",
    temperature: 1,
    top_p: 0.95,
    top_k: 64,
  });
  assert.deepEqual(applyRecommendedSampling({ model: "deepseek-v4-flash" }), {
    model: "deepseek-v4-flash",
    temperature: 1,
    top_p: 1,
  });
});

test("leaves unrelated or malformed provider payloads unchanged", () => {
  const unrelated = { model: "openrouter/other", temperature: 0.2 };
  assert.equal(applyRecommendedSampling(unrelated), unrelated);
  assert.equal(applyRecommendedSampling(null), null);
});
