import { NextRequest } from 'next/server';
import { NextResponse } from 'next/server';
import { deleteReport } from '../../../../lib/reports';
import { requireSameOrigin, requireSession } from '../../../../lib/security';

export const runtime = 'nodejs';

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  await requireSession();
  if (!(await requireSameOrigin())) return new NextResponse('Forbidden', { status: 403 });
  const { id } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    return new NextResponse('Bad request', { status: 400 });
  }
  await deleteReport(id);
  return NextResponse.redirect(new URL('/dashboard', request.url), 303);
}
