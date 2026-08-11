export const MAX_BODY_BYTES = 256 * 1024;
export const MAX_LOGS = 200;
export const MAX_LOG_LENGTH = 8 * 1024;

export type DiagnosticPayload = {
  installationId: string;
  appVersion: string;
  platform: string;
  deviceName: string;
  sentAt: string;
  logs: string[];
};

const idPattern = /^[A-Za-z0-9._:-]{8,128}$/;
const safeTextPattern = /^[^\u0000-\u0008\u000B\u000C\u000E-\u001F]{1,256}$/;

function text(value: unknown, max: number): string | null {
  if (typeof value !== 'string' || value.length === 0 || value.length > max) return null;
  return value;
}

export function parseDiagnosticPayload(value: unknown): DiagnosticPayload | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const input = value as Record<string, unknown>;
  const installationId = text(input.installationId, 128);
  const appVersion = text(input.appVersion, 64);
  const platform = text(input.platform, 32);
  const deviceName = text(input.deviceName, 128);
  const sentAt = text(input.sentAt, 64);
  const rawLogs = input.logs;
  if (
    !installationId ||
    !idPattern.test(installationId) ||
    !appVersion ||
    !safeTextPattern.test(appVersion) ||
    !platform ||
    !safeTextPattern.test(platform) ||
    !deviceName ||
    !safeTextPattern.test(deviceName) ||
    !sentAt ||
    !Number.isFinite(Date.parse(sentAt)) ||
    !Array.isArray(rawLogs) ||
    rawLogs.length === 0 ||
    rawLogs.length > MAX_LOGS
  ) return null;

  const logs: string[] = [];
  for (const entry of rawLogs) {
    const log = text(entry, MAX_LOG_LENGTH);
    if (!log) return null;
    logs.push(log);
  }
  return { installationId, appVersion, platform, deviceName, sentAt, logs };
}
