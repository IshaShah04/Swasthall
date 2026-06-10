export type LogLevel = 'info' | 'warn' | 'error';

export interface LogEntry {
  level: LogLevel;
  function: string;
  message: string;
  request_id?: string;
  user_id?: string;
  duration_ms?: number;
  [key: string]: unknown;
}

export function createLogger(functionName: string, requestId?: string) {
  return {
    info: (message: string, extra?: Record<string, unknown>) => {
      log('info', functionName, message, requestId, extra);
    },
    warn: (message: string, extra?: Record<string, unknown>) => {
      log('warn', functionName, message, requestId, extra);
    },
    error: (message: string, error?: unknown, extra?: Record<string, unknown>) => {
      log('error', functionName, message, requestId, {
        ...extra,
        error_message: error instanceof Error ? error.message : String(error),
        error_name: error instanceof Error ? error.name : undefined,
      });
    },
  };
}

function log(
  level: LogLevel,
  functionName: string,
  message: string,
  requestId?: string,
  extra?: Record<string, unknown>
) {
  const entry: LogEntry = {
    level,
    function: functionName,
    message,
    request_id: requestId,
    timestamp: new Date().toISOString(),
    ...extra,
  };
  // Supabase captures stdout as structured logs
  if (level === 'error') {
    console.error(JSON.stringify(entry));
  } else if (level === 'warn') {
    console.warn(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

export function getRequestId(req: Request): string {
  return req.headers.get('x-request-id') ?? 
         req.headers.get('cf-ray') ?? 
         crypto.randomUUID();
}

export function startTimer(): () => number {
  const start = Date.now();
  return () => Date.now() - start;
}
