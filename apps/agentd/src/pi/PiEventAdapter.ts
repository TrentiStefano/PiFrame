import { ulid } from 'ulid';
import type { PiEvent } from './piCommands.js';
import type { PcpEvent, PcpEventType } from '@piframe/pcp-ts';

export interface SessionContext {
  sessionId: string;
  lastUsage?: { inputTokens?: number; outputTokens?: number; totalTokens?: number };
}

function checkUsage(rawEvent: PiEvent, ctx: SessionContext, results: Array<{ type: PcpEventType; payload: any }>) {
  const usage = rawEvent.usage || rawEvent.message?.usage;
  if (usage) {
    const inTokens = usage.input ?? usage.inputTokens;
    const outTokens = usage.output ?? usage.outputTokens;
    if (!ctx.lastUsage ||
        ctx.lastUsage.inputTokens !== inTokens ||
        ctx.lastUsage.outputTokens !== outTokens) {
      ctx.lastUsage = { inputTokens: inTokens, outputTokens: outTokens };
      results.push({
        type: 'usage.updated',
        payload: { usage }
      });
    }
  }
}

export function adaptPiEvent(rawEvent: PiEvent, ctx: SessionContext): Array<{ type: PcpEventType; payload: any }> {
  const results: Array<{ type: PcpEventType; payload: any }> = [];

  const type = rawEvent.type;

  switch (type) {
    case 'agent_start':
      results.push({ type: 'run.started', payload: {} });
      break;

    case 'agent_end': {
      const willRetry = !!rawEvent.willRetry;
      results.push({ type: 'run.ended', payload: { willRetry } });
      checkUsage(rawEvent, ctx, results);
      break;
    }

    case 'agent_settled':
      results.push({ type: 'run.settled', payload: {} });
      break;

    case 'turn_start':
      results.push({ type: 'turn.started', payload: {} });
      break;

    case 'turn_end':
      results.push({ type: 'turn.ended', payload: {} });
      checkUsage(rawEvent, ctx, results);
      break;

    case 'message_start':
      results.push({
        type: 'message.started',
        payload: {
          messageId: rawEvent.message?.id || rawEvent.id || `msg_${ulid()}`,
          role: rawEvent.message?.role || rawEvent.role || 'assistant'
        }
      });
      break;

    case 'message_update': {
      const sub = rawEvent.assistantMessageEvent;
      if (sub) {
        if (sub.type === 'text_delta') {
          results.push({
            type: 'text.delta',
            payload: {
              contentIndex: sub.contentIndex ?? 0,
              delta: sub.delta ?? ''
            }
          });
        } else if (sub.type === 'thinking_delta') {
          results.push({
            type: 'thinking.delta',
            payload: {
              contentIndex: sub.contentIndex ?? 0,
              delta: sub.delta ?? ''
            }
          });
        } else if (sub.type === 'toolcall_delta' || sub.type === 'tool_call_delta') {
          results.push({
            type: 'toolcall.argsDelta',
            payload: {
              contentIndex: sub.contentIndex ?? 0,
              toolCallId: sub.toolCallId,
              delta: sub.delta ?? ''
            }
          });
        }
      }

      // Check usage update
      checkUsage(rawEvent, ctx, results);
      break;
    }

    case 'message_end':
      checkUsage(rawEvent, ctx, results);
      results.push({
        type: 'message.completed',
        payload: { message: rawEvent.message ? {
          ...rawEvent.message,
          id: rawEvent.message.id || `msg_${rawEvent.message.timestamp ?? ulid()}`
        } : undefined }
      });
      break;

    case 'tool_execution_start':
      results.push({
        type: 'tool.started',
        payload: {
          toolCallId: rawEvent.toolCallId,
          toolName: rawEvent.toolName,
          args: rawEvent.args
        }
      });
      break;

    case 'tool_execution_update':
      results.push({
        type: 'tool.progress',
        payload: {
          toolCallId: rawEvent.toolCallId,
          toolName: rawEvent.toolName,
          partialResult: rawEvent.partialResult
        }
      });
      break;

    case 'tool_execution_end':
      results.push({
        type: 'tool.completed',
        payload: {
          toolCallId: rawEvent.toolCallId,
          toolName: rawEvent.toolName,
          result: rawEvent.result,
          isError: !!rawEvent.isError,
          durationMs: rawEvent.durationMs
        }
      });
      break;

    case 'queue_update':
      results.push({
        type: 'queue.changed',
        payload: {
          steering: rawEvent.steering || [],
          followUp: rawEvent.followUp || []
        }
      });
      break;

    case 'compaction_start':
      results.push({
        type: 'compaction.started',
        payload: { reason: rawEvent.reason }
      });
      break;

    case 'compaction_end':
      results.push({
        type: 'compaction.ended',
        payload: {
          result: rawEvent.result,
          aborted: !!rawEvent.aborted,
          willRetry: !!rawEvent.willRetry,
          errorMessage: rawEvent.errorMessage
        }
      });
      break;

    case 'auto_retry_start':
      results.push({
        type: 'retry.started',
        payload: {
          attempt: rawEvent.attempt,
          maxAttempts: rawEvent.maxAttempts,
          delayMs: rawEvent.delayMs,
          errorMessage: rawEvent.errorMessage
        }
      });
      break;

    case 'auto_retry_end':
      results.push({
        type: 'retry.ended',
        payload: {
          success: !!rawEvent.success,
          attempt: rawEvent.attempt,
          finalError: rawEvent.finalError
        }
      });
      break;

    case 'bash_execution_update':
      results.push({
        type: 'bash.output',
        payload: {
          commandId: rawEvent.id,
          delta: rawEvent.delta
        }
      });
      break;

    case 'extension_ui_request': {
      const method = rawEvent.method;
      if (method === 'notify') {
        results.push({
          type: 'ui.notify',
          payload: { level: rawEvent.notifyType ?? rawEvent.level ?? 'info', message: rawEvent.message ?? '' }
        });
      } else if (method === 'setStatus') {
        results.push({
          type: 'ui.status',
          payload: { statusKey: rawEvent.statusKey, statusText: rawEvent.statusText }
        });
      } else if (method === 'setWidget') {
        results.push({
          type: 'ui.widget',
          payload: { widgetKey: rawEvent.widgetKey, lines: rawEvent.widgetLines ?? rawEvent.lines, placement: rawEvent.widgetPlacement ?? rawEvent.placement }
        });
      } else if (method === 'set_editor_text') {
        results.push({
          type: 'ui.editorText',
          payload: { text: rawEvent.text ?? '' }
        });
      } else if (method === 'setTitle') {
        results.push({
          type: 'ui.title',
          payload: { title: rawEvent.title ?? '' }
        });
      } else {
        // Dialog requests requiring response
        const title = String(rawEvent.title ?? '');
        const localAuthRequest = title.startsWith('piframe-local:');
        const secretInput = rawEvent.method === 'input' && String(rawEvent.placeholder ?? '').startsWith('piframe-secret:');
        results.push({
          type: 'ui.request',
          payload: {
            requestId: rawEvent.requestId || rawEvent.id || `ui_${ulid()}`,
            method: rawEvent.method,
            title: localAuthRequest ? title.slice('piframe-local:'.length) : title,
            message: rawEvent.message,
            options: rawEvent.options,
            placeholder: rawEvent.placeholder,
            prefill: rawEvent.prefill,
            localOnly: localAuthRequest || secretInput,
            timeoutMs: rawEvent.timeout ?? rawEvent.timeoutMs,
            dialog: true,
            claimedBy: null
          }
        });
      }
      break;
    }

    case 'extension_error':
      results.push({
        type: 'extension.error',
        payload: {
          extensionPath: rawEvent.extensionPath,
          event: rawEvent.event,
          error: rawEvent.error
        }
      });
      break;

    case 'worker.diagnostic':
      results.push({
        type: 'worker.diagnostic',
        payload: {
          level: rawEvent.level || 'info',
          message: rawEvent.message || '',
          source: rawEvent.source || 'supervisor'
        }
      });
      break;

    default:
      // Unknown event: never drop silently
      results.push({
        type: 'worker.diagnostic',
        payload: {
          level: 'info',
          message: `Unknown Pi event type: ${type}`,
          source: 'supervisor',
          raw: rawEvent
        }
      });
      break;
  }

  return results;
}
