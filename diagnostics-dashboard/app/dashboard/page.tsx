import { requireSession } from '../../lib/security';
import { listReports } from '../../lib/reports';
import { pruneExpiredReports } from '../../lib/retention';

export const dynamic = 'force-dynamic';

function formatDate(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? value : date.toLocaleString();
}

export default async function DashboardPage() {
  const session = await requireSession();
  await pruneExpiredReports();
  const reports = await listReports();
  return (
    <main className="shell">
      <header className="header">
        <div><h1>ASA Diagnostics</h1><p className="muted">Signed in as {session.username}. Reports are retained according to server policy.</p></div>
        <form action="/api/auth/logout" method="post"><button className="secondary" type="submit">Sign out</button></form>
      </header>
      <div className="stats"><div className="card stat"><span className="muted">Visible reports</span><strong>{reports.length}</strong></div></div>
      {reports.length === 0 ? <section className="card empty"><p className="muted">No diagnostic reports yet.</p></section> : reports.map((report) => (
        <article className="card report" key={report.id}>
          <div className="report-head">
            <div>
              <h2>{report.app_version} · {report.platform}</h2>
              <div className="report-meta"><span className="badge">{report.device_name}</span><span>Received {formatDate(report.received_at)}</span><span>Sent {formatDate(report.sent_at)}</span><span>#{report.id}</span></div>
            </div>
            <form action={`/api/reports/${report.id}`} method="post"><button className="danger" type="submit">Delete</button></form>
          </div>
          <pre>{JSON.stringify(report.payload, null, 2)}</pre>
        </article>
      ))}
    </main>
  );
}
