import { redirect } from 'next/navigation';
import { currentSession } from '../lib/security';

export default async function HomePage() {
  redirect((await currentSession()) ? '/dashboard' : '/login');
}
