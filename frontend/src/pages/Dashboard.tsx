import { useEffect, useState } from 'react';
import { getHealth, getMe, getVersion, getWorkerJob, listFiles, listTasks } from '../api/client';
import type { Job, User, VersionInfo } from '../api/types';
import { getLastJobId } from '../auth/token';

export function DashboardPage() {
  const [user, setUser] = useState<User | null>(null);
  const [taskCount, setTaskCount] = useState(0);
  const [fileCount, setFileCount] = useState(0);
  const [health, setHealth] = useState('unknown');
  const [version, setVersion] = useState<VersionInfo | null>(null);
  const [lastJob, setLastJob] = useState<Job | null>(null);
  const [error, setError] = useState('');

  useEffect(() => {
    Promise.all([getMe(), listTasks(), listFiles(), getHealth(), getVersion()])
      .then(async ([me, tasks, files, healthRes, versionRes]) => {
        setUser(me);
        setTaskCount(tasks.length);
        setFileCount(files.length);
        setHealth(healthRes.status);
        setVersion(versionRes);

        const lastJobId = getLastJobId();
        if (lastJobId) {
          try {
            setLastJob(await getWorkerJob(lastJobId));
          } catch {
            setLastJob(null);
          }
        }
      })
      .catch(() => setError('Failed to load dashboard data.'));
  }, []);

  return (
    <div>
      <h1>Dashboard</h1>
      {error && <p className="error">{error}</p>}

      <div className="card">
        <h2>Current user</h2>
        {user ? (
          <p>
            {user.email} <span className="badge">{user.role}</span>
          </p>
        ) : (
          <p className="muted">Loading…</p>
        )}
      </div>

      <div className="card">
        <h2>Counts</h2>
        <p>Tasks: {taskCount}</p>
        <p>Files: {fileCount}</p>
      </div>

      <div className="card">
        <h2>Last processed job</h2>
        {lastJob ? (
          <p>
            {lastJob.id} — <span className="badge">{lastJob.status}</span> ({lastJob.type})
          </p>
        ) : (
          <p className="muted">Process a file to track the latest job.</p>
        )}
      </div>

      <div className="card">
        <h2>Backend status</h2>
        <p>
          Health: <span className="badge">{health}</span>
        </p>
        {version && (
          <p className="muted">
            {version.service} · build {version.buildSha} · {version.region}
          </p>
        )}
      </div>
    </div>
  );
}
