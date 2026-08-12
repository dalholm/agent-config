type SamplingPreset = {
  temperature: number;
  top_p: number;
  top_k?: number;
};

const RECOMMENDED_SAMPLING: Readonly<Record<string, SamplingPreset>> = {
  "qwen3.6-35b-a3b-dflash": {
    temperature: 0.6,
    top_p: 0.95,
    top_k: 20,
  },
  "meta/muse-glimmer": {
    temperature: 1,
    top_p: 0.95,
    top_k: 64,
  },
  "deepseek-v4-flash": {
    temperature: 1,
    top_p: 1,
  },
};

export function applyRecommendedSampling(payload: unknown): unknown {
  if (
    typeof payload !== "object" ||
    payload === null ||
    Array.isArray(payload)
  ) {
    return payload;
  }

  const request = payload as Record<string, unknown>;
  const model = typeof request.model === "string" ? request.model : "";
  const preset = RECOMMENDED_SAMPLING[model];
  return preset ? { ...request, ...preset } : payload;
}
