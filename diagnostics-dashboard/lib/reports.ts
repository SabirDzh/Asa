import { sql } from './db';
import { env } from './env';
import type { DiagnosticPayload } from './validation';

export async function isRateLimited(installationHash: string, ipHash: string): Promise<boolean> {
  const result = await sql()`
    select
      count(*) filter (where installation_id = ${installationHash}) as installation_count,
      count(*) filter (where ip_hash = ${ipHash}) as ip_count
    from diagnostic_reports
    where received_at > now() - interval '1 hour'
      and deleted_at is null
  ` as unknown as Array<{ installation_count: string | number; ip_count: string | number }>;
  const row = result[0];
  return Number(row?.installation_count ?? 0) >= env.maxReportsPerInstallationPerHour ||
    Number(row?.ip_count ?? 0) >= env.maxReportsPerIpPerHour;
}

export async function insertReport(
  id: string,
  payload: DiagnosticPayload,
  installationHash: string,
  ipHash: string,
  userAgent: string,
): Promise<void> {
  const storedPayload = { ...payload, installationId: installationHash };
  await sql()`
    insert into diagnostic_reports
      (id, installation_id, app_version, platform, device_name, user_agent, ip_hash, sent_at, payload)
    values
      (${id}, ${installationHash}, ${payload.appVersion}, ${payload.platform}, ${payload.deviceName}, ${userAgent}, ${ipHash}, ${payload.sentAt}, ${JSON.stringify(storedPayload)})
  `;
}

export type ReportRow = {
  id: string;
  app_version: string;
  platform: string;
  device_name: string;
  user_agent: string;
  sent_at: string;
  received_at: string;
  payload: DiagnosticPayload;
};

export async function listReports(): Promise<ReportRow[]> {
  const rows = await sql()`
    select id, app_version, platform, device_name, user_agent, sent_at, received_at, payload
    from diagnostic_reports
    where deleted_at is null
    order by received_at desc
    limit 200
  ` as unknown as ReportRow[];
  return rows;
}

export async function deleteReport(id: string): Promise<void> {
  await sql()`
    update diagnostic_reports
    set deleted_at = now()
    where id = ${id} and deleted_at is null
  `;
}
