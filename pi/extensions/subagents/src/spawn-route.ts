import {
  assertIndependentReviewRoute,
  bindModelRoute,
  providerFamilyForProvider,
} from "../../shared/model-routing.ts";
import type { BackendName, BoundSpawnTask, SpawnTask } from "./domain.ts";

export function bindSpawnTask(
  harness: BackendName,
  task: SpawnTask,
): BoundSpawnTask {
  assertIndependentReviewRoute({
    harness,
    role: task.role,
    tier: task.tier,
    ...(task.reviewOfHarness === undefined
      ? {}
      : { reviewOfHarness: task.reviewOfHarness }),
    ...(task.reviewOfProviderFamily === undefined
      ? {}
      : { reviewOfProviderFamily: task.reviewOfProviderFamily }),
  });
  if (
    task.role === "reviewer" &&
    (task.model !== undefined || task.reasoningEffort !== undefined)
  ) {
    throw new Error(
      "reviewer routes do not allow model or reasoning overrides",
    );
  }
  const route = bindModelRoute({
    harness,
    role: task.role,
    tier: task.tier,
    ...(task.model === undefined ? {} : { model: task.model }),
    ...(task.reasoningEffort === undefined
      ? {}
      : { reasoningEffort: task.reasoningEffort }),
  });
  const providerFamily =
    route.providerFamily === "dynamic"
      ? providerFamilyForProvider(task.parent.inheritedModel?.provider)
      : route.providerFamily;
  return {
    ...task,
    ...(route.model === undefined ? {} : { model: route.model }),
    ...(route.reasoningEffort === undefined
      ? {}
      : { reasoningEffort: route.reasoningEffort }),
    route: {
      ...route,
      providerFamily,
      ...(task.reviewOfHarness === undefined
        ? {}
        : { reviewOfHarness: task.reviewOfHarness }),
      ...(task.reviewOfProviderFamily === undefined
        ? {}
        : { reviewOfProviderFamily: task.reviewOfProviderFamily }),
    },
  };
}
