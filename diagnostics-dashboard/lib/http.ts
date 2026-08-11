import { NextRequest, NextResponse } from 'next/server';

export function json(data: unknown, init?: ResponseInit): NextResponse {
  return NextResponse.json(data, init);
}

export function clientIp(request: NextRequest): string {
  // Vercel supplies x-real-ip. Do not trust arbitrary forwarded chains for
  // authorization; this value is used only as a salted rate-limit identifier.
  return request.headers.get('x-real-ip')?.trim() || 'unknown';
}

export function userAgent(request: NextRequest): string {
  return (request.headers.get('user-agent') ?? '').slice(0, 512);
}
