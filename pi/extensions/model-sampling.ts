import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { applyRecommendedSampling } from "./shared/model-sampling.ts";

export default function (pi: ExtensionAPI): void {
  pi.on("before_provider_request", (event) =>
    applyRecommendedSampling(event.payload),
  );
}
