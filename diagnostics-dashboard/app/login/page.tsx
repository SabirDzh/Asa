import { redirect } from 'next/navigation';
import { currentSession } from '../../lib/security';

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  if (await currentSession()) redirect('/dashboard');
  const params = await searchParams;
  return (
    <main className="shell">
      <section className="card auth">
        <h1>ASA Diagnostics</h1>
        <p className="muted">Private administrator access.</p>
        <form action="/api/auth/login" method="post">
          <div className="field"><label htmlFor="username">Username</label><input id="username" name="username" autoComplete="username" required maxLength={128} /></div>
          <div className="field"><label htmlFor="password">Password</label><input id="password" name="password" type="password" autoComplete="current-password" required maxLength={512} /></div>
          <button className="primary" type="submit">Sign in</button>
        </form>
        {params.error ? <p className="error">Invalid credentials.</p> : null}
      </section>
    </main>
  );
}
