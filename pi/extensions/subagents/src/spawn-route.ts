import { bindModelRoute } from "../../shared/model-routing.ts";
import type { BackendName, BoundSpawnTask, SpawnTask } from "./domain.ts";

export function bindSpawnTask(
  harness: BackendName,
  task: SpawnTask,
): BoundSpawnTask {
  const route = bindModelRoute({
    harness,
    role: task.role,
    tier: task.tier,
    ...(task.model === undefined ? {} : { model: task.model }),
    ...(task.reasoningEffort === undefined
      ? {}
      : { reasoningEffort: task.reasoningEffort }),
  });
  return {
    ...task,
    ...(route.model === undefined ? {} : { model: route.model }),
    ...(route.reasoningEffort === undefined
      ? {}
      : { reasoningEffort: route.reasoningEffort }),
    route,
  };
}
