// Owner: B7. The reports queue, oldest first. People appear only as watermark codes.
import type { Metadata } from 'next';
import Link from 'next/link';
import { zReportStatus, type ReportStatus } from '@/contracts';
import { listReports } from '@/server/admin/reports';
import { listRooms } from '@/server/admin/rooms';
import { adminPage } from '@/server/admin/web';
import { formatTime } from '../../_components/format';
import { ReportActions } from '../../_components/ReportActions';

export const metadata: Metadata = { title: 'Reports' };

const REASONS: Record<string, string> = {
  harassment: 'Harassment',
  inappropriate_photo: 'Inappropriate photo',
  underage: 'Might be under 18',
  spam: 'Spam',
  unsafe: 'Made someone feel unsafe',
  other: 'Something else',
};

const CONTEXTS: Record<string, string> = {
  card: 'from a card',
  match: 'from a match',
  chat: 'from a chat',
};

const TABS: { status: ReportStatus; label: string }[] = [
  { status: 'open', label: 'Open' },
  { status: 'actioned', label: 'Acted on' },
  { status: 'dismissed', label: 'Dismissed' },
];

export default async function ReportsPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string | string[] }>;
}) {
  await adminPage();
  const parsed = zReportStatus.safeParse((await searchParams).status);
  const status: ReportStatus = parsed.success ? parsed.data : 'open';
  const [reports, rooms] = await Promise.all([listReports(status), listRooms()]);
  const roomNames = new Map(rooms.map((r) => [r.id, r.name]));
  const roomZones = new Map(rooms.map((r) => [r.id, r.timezone]));

  return (
    <div className="ga-stack">
      <h1>Reports</h1>
      <nav className="ga-tabs" aria-label="Report status">
        {TABS.map((tab) => (
          <Link
            key={tab.status}
            href={tab.status === 'open' ? '/admin/reports' : `/admin/reports?status=${tab.status}`}
            aria-current={tab.status === status ? 'page' : undefined}
          >
            {tab.label}
          </Link>
        ))}
      </nav>
      {reports.length === 0 ? (
        <p className="ga-muted">{status === 'open' ? 'Nothing to review. ' : ''}No reports here.</p>
      ) : (
        <ul className="ga-list">
          {reports.map((report) => (
            <li key={report.id} className="ga-card ga-stack">
              <div className="ga-row ga-row--between">
                <h2 style={{ margin: 0 }}>{REASONS[report.reason] ?? report.reason}</h2>
                <span className="ga-small ga-muted">
                  {formatTime(
                    report.createdAt,
                    (report.roomId && roomZones.get(report.roomId)) || 'America/Los_Angeles',
                  )}
                </span>
              </div>
              <p className="ga-small ga-muted" style={{ margin: 0 }}>
                Reported {CONTEXTS[report.context]}
                {report.roomId ? ` in ${roomNames.get(report.roomId) ?? 'a room'}` : ''}. Reported
                person <span className="ga-code">{report.reportedViewerCode}</span>, by{' '}
                <span className="ga-code">{report.reporterViewerCode}</span>.
              </p>
              {report.details ? (
                <blockquote className="ga-message" style={{ margin: 0, whiteSpace: 'pre-wrap' }}>
                  {report.details}
                </blockquote>
              ) : null}
              {report.evidence.length > 0 ? (
                <details>
                  <summary>
                    Their last{' '}
                    {report.evidence.length === 1
                      ? 'message'
                      : `${report.evidence.length} messages`}
                  </summary>
                  <ol className="ga-evidence" style={{ marginTop: 8 }}>
                    {report.evidence.map((e, i) => (
                      <li key={i}>{e.body}</li>
                    ))}
                  </ol>
                </details>
              ) : null}
              {report.status === 'open' ? <ReportActions reportId={report.id} /> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
