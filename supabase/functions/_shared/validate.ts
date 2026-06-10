export class ValidationError extends Error {
  status: number;
  constructor(message: string) {
    super(message);
    this.name = 'ValidationError';
    this.status = 400;
  }
}

export function requireString(value: unknown, field: string): string {
  if (value === undefined || value === null || value === '') {
    throw new ValidationError(`Missing required field: ${field}`);
  }
  if (typeof value !== 'string') {
    throw new ValidationError(`Field ${field} must be a string`);
  }
  return value.trim();
}

export function requireUUID(value: unknown, field: string): string {
  const str = requireString(value, field);
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (!uuidRegex.test(str)) {
    throw new ValidationError(`Field ${field} must be a valid UUID`);
  }
  return str;
}

export function requirePositiveNumber(value: unknown, field: string): number {
  if (value === undefined || value === null) {
    throw new ValidationError(`Missing required field: ${field}`);
  }
  const num = Number(value);
  if (isNaN(num) || num <= 0) {
    throw new ValidationError(`Field ${field} must be a positive number`);
  }
  return num;
}

export function optionalString(value: unknown, defaultValue = ''): string {
  if (value === undefined || value === null) return defaultValue;
  return String(value).trim().slice(0, 500);
}

export function handleValidationError(e: unknown): Response {
  if (e instanceof ValidationError) {
    return new Response(
      JSON.stringify({ error: e.message }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }
  throw e; // re-throw non-validation errors
}
