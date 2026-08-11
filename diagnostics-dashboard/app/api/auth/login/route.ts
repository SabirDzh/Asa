import { NextRequest, NextResponse } from 'next/server';
import { json } from '../../../../lib/http';
import { clientIp } from '../../../../lib/http';
import { isLoginRateLimited, recordFailedLogin } from '../../../../lib/login-rate-limit';
import { createSession, requireSameOrigin, setSessionCookie, verifyAdminCredentials } from '../../../../lib/security';

export const runtime = 'nodejs';

export async function POST(request: NextRequest) {
  if (!(await requireSameOrigin())) return json({ error: 'forbidden' }, { status: 403 });
  const form = await request.formData();
  const username = String(form.get('username') ?? '').trim();
  const password = String(form.get('password') ?? '');
  const identifier = `${clientIp(request)}:${username}`;
  if (
    username.length > 64 ||
    password.length > 512 ||
    await isLoginRateLimited(identifier) ||
    !verifyAdminCredentials(username, password)
  ) {
    await recordFailedLogin(identifier);
    return NextResponse.redirect(new URL('/login?error=1', request.url), 303);
  }
  await setSessionCookie(createSession(username));
  return NextResponse.redirect(new URL('/dashboard', request.url), 303);
}
