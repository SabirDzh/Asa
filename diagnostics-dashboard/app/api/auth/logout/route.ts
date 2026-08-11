import { NextRequest, NextResponse } from 'next/server';
import { clearSessionCookie, currentSession, requireSameOrigin } from '../../../../lib/security';

export const runtime = 'nodejs';

export async function POST(request: NextRequest) {
  if (!(await requireSameOrigin())) return new NextResponse('Forbidden', { status: 403 });
  await currentSession();
  await clearSessionCookie();
  return NextResponse.redirect(new URL('/login', request.url), 303);
}
