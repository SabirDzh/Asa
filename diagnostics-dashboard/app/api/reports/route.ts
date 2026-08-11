import { NextRequest } from 'next/server';
import { randomReportId, hashRateLimitIdentifier } from '../../../lib/security';
import { clientIp, json, userAgent } from '../../../lib/http';
import { insertReport, isRateLimited } from '../../../lib/reports';
import { pruneExpiredReports } from '../../../lib/retention';
import { MAX_BODY_BYTES, parseDiagnosticPayload } from '../../../lib/validation';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  const contentLength = Number(request.headers.get('content-length') ?? 0);
  if (contentLength > MAX_BODY_BYTES) return json({ error: 'payload_too_large' }, { status: 413 });
  if (request.headers.get('content-type')?.split(';')[0].trim() !== 'application/json') {
    return json({ error: 'json_required' }, { status: 415 });
  }

  let raw: unknown;
  try {
    const body = await request.arrayBuffer();
    if (body.byteLength > MAX_BODY_BYTES) return json({ error: 'payload_too_large' }, { status: 413 });
    raw = JSON.parse(new TextDecoder().decode(body));
  } catch {
    return json({ error: 'invalid_json' }, { status: 400 });
  }

  const payload = parseDiagnosticPayload(raw);
  if (!payload) return json({ error: 'invalid_payload' }, { status: 400 });

  const ipHash = hashRateLimitIdentifier(clientIp(request));
  const installationHash = hashRateLimitIdentifier(payload.installationId);
  try {
    if (await isRateLimited(installationHash, ipHash)) {
      return json({ error: 'rate_limited' }, { status: 429, headers: { 'Retry-After': '3600' } });
    }
    const reportId = randomReportId();
    await insertReport(reportId, payload, installationHash, ipHash, userAgent(request));
    try {
      await pruneExpiredReports();
    } catch {
      // Retention is best-effort and must not make a successfully stored report
      // look failed to the client, which could cause duplicate submissions.
    }
    return json({ reportId }, { status: 201 });
  } catch {
    return json({ error: 'temporarily_unavailable' }, { status: 503 });
  }
}
