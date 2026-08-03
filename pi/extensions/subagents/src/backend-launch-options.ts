import type { Options as ClaudeQueryOptions } from "@anthropic-ai/claude-agent-sdk";
import type { ReasoningEffort, SpawnTask } from "./domain.ts";
import { resolveSubagentProfile } from "./safety-profile.ts";

const CLAUDE_THINKING_BUDGETS = {
  off: 0,
  minimal: 1_024,
  low: 4_096,
  medium: 10_000,
  high: 16_000,
  xhigh: 32_000,
  max: 63_999,
} satisfies Record<ReasoningEffort, number>;

export function buildClaudeQueryOptions(
  task: SpawnTask,
  abortController: AbortController,
  claudeBinary?: string,
): ClaudeQueryOptions {
  const thinkingBudget = task.reasoningEffort
    ? CLAUDE_THINKING_BUDGETS[task.reasoningEffort]
    : undefined;
  return {
    cwd: task.cwd,
    ...resolveSubagentProfile("claude"),
    disallowedTools: ["Agent", "Task"],
    ...(task.parent.projectTrusted ? {} : { settingSources: ["user"] }),
    includePartialMessages: true,
    abortController,
    ...(claudeBinary ? { pathToClaudeCodeExecutable: claudeBinary } : {}),
    ...(task.model ? { model: task.model } : {}),
    ...(thinkingBudget !== undefined
      ? { maxThinkingTokens: thinkingBudget }
      : {}),
  };
}

export function buildCodexThreadStartParams(task: SpawnTask) {
  return {
    cwd: task.cwd,
    ...resolveSubagentProfile("codex"),
    ephemeral: false,
    ...(task.model ? { model: task.model } : {}),
  };
}
