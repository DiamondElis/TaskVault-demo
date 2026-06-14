import { useEffect, useState } from 'react';
import { Navigate } from 'react-router-dom';
import {
  getMe,
  getWorkerJob,
  listAdminFiles,
  listAuditEvents,
  runAdminReport,
} from '../api/client';
import type { AuditEvent, FileRecord, Job, User } from '../api/types';
import { isAdminReportsEnabled } from '../config';
import { setLastJobId } from '../auth/token';

export function AdminPage() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [auditEvents, setAuditEvents] = useState<AuditEvent[]>([]);
  const [files, setFiles] = useState<FileRecord[]>([]);
  const [lastJob, setLastJob] = useState<Job | null>(null);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    getMe()
      .then(async (me) => {
        setUser(me);
        if (me.role !== 'admin') {
          return;
        }

        const [events, adminFiles] = await Promise.all([listAuditEvents(), listAdminFiles()]);
        setAuditEvents(events.slice(0, 20));
        setFiles(adminFiles.filter((f) => f.classification === 'sensitive'));
      })
      .catch(() => setError('Failed to load admin data.'))
      .finally(() => setLoading(false));
  }, []);

  if (loading) {
    return <p className="muted">Loading…</p>;
  }

  if (!user || user.role !== 'admin') {
    return <Navigate to="/dashboard" replace />;
  }

  const onRunReport = async () => {
    if (!isAdminReportsEnabled()) {
      setError('Admin reports disabled by runtime config.');
      return;
    }

    setError('');
    setMessage('');

    try {
      const result = await runAdminReport();
      setMessage(`Report ${result.report.id} requested.`);
      if (result.job) {
        setLastJobId(result.job.id);
        setLastJob(await getWorkerJob(result.job.id));
      }
    } catch {
      setError('Failed to run admin report.');
    }
  };

  return (
    <div>
      <h1>Admin</h1>
      {error && <p className="error">{error}</p>}
      {message && <p>{message}</p>}

      <div className="card">
        <h2>Run report</h2>
        <button type="button" onClick={onRunReport}>
          Run admin report
        </button>
      </div>

      <div className="card">
        <h2>Worker job status</h2>
        {lastJob ? (
          <p>
            {lastJob.id} — <span className="badge">{lastJob.status}</span> ({lastJob.type})
          </p>
        ) : (
          <p className="muted">Run a report or process a file to see the latest job.</p>
        )}
      </div>

      <div className="card">
        <h2>Recent audit events</h2>
        <table>
          <thead>
            <tr>
              <th>Time</th>
              <th>Service</th>
              <th>Event</th>
            </tr>
          </thead>
          <tbody>
            {auditEvents.map((event) => (
              <tr key={event.id}>
                <td>{new Date(event.timestamp).toLocaleString()}</td>
                <td>{event.service}</td>
                <td>{event.event_type}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h2>Sensitive demo files</h2>
        <table>
          <thead>
            <tr>
              <th>Filename</th>
              <th>Owner</th>
              <th>S3 key</th>
            </tr>
          </thead>
          <tbody>
            {files.map((file) => (
              <tr key={file.file_id}>
                <td>{file.filename}</td>
                <td>{file.owner_user_id}</td>
                <td className="muted">{file.s3_key}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
