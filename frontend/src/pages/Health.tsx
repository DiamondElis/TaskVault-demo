import { useEffect, useState } from 'react';
import { getHealth, getVersion } from '../api/client';

export function HealthPage() {
  const [backendHealth, setBackendHealth] = useState('checking…');
  const [version, setVersion] = useState('');
  const [frontendStatus, setFrontendStatus] = useState('checking…');

  useEffect(() => {
    fetch('/metrics')
      .then((res) => setFrontendStatus(res.ok ? 'ok' : 'degraded'))
      .catch(() => setFrontendStatus('unreachable'));

    Promise.all([getHealth(), getVersion()])
      .then(([health, info]) => {
        setBackendHealth(health.status);
        setVersion(`${info.service} ${info.buildSha} (${info.region})`);
      })
      .catch(() => setBackendHealth('unreachable'));
  }, []);

  return (
    <div>
      <h1>Health</h1>
      <div className="card">
        <h2>Frontend</h2>
        <p>
          Status: <span className="badge">{frontendStatus}</span>
        </p>
        <p className="muted">Public route — no auth required.</p>
      </div>
      <div className="card">
        <h2>Backend</h2>
        <p>
          Status: <span className="badge">{backendHealth}</span>
        </p>
        {version && <p className="muted">{version}</p>}
      </div>
    </div>
  );
}
