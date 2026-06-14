import { FormEvent, useEffect, useState } from 'react';
import { listFiles, processFile, uploadFile } from '../api/client';
import type { FileRecord } from '../api/types';
import { setLastJobId } from '../auth/token';

export function FilesPage() {
  const [files, setFiles] = useState<FileRecord[]>([]);
  const [file, setFile] = useState<File | null>(null);
  const [classification, setClassification] = useState<'public' | 'private' | 'sensitive'>(
    'private',
  );
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  const refresh = () => {
    listFiles()
      .then(setFiles)
      .catch(() => setError('Failed to load files.'));
  };

  useEffect(() => {
    refresh();
  }, []);

  const onUpload = async (event: FormEvent) => {
    event.preventDefault();
    if (!file) {
      return;
    }

    setError('');
    setMessage('');

    try {
      await uploadFile(file, classification);
      setFile(null);
      setMessage('Upload complete.');
      refresh();
    } catch {
      setError('Upload failed.');
    }
  };

  const onProcess = async (fileId: string) => {
    setError('');
    setMessage('');

    try {
      const job = await processFile(fileId);
      setLastJobId(job.id);
      setMessage(`Job ${job.id} queued (${job.status}).`);
      refresh();
    } catch {
      setError('Failed to enqueue processing job.');
    }
  };

  return (
    <div>
      <h1>Files</h1>
      {error && <p className="error">{error}</p>}
      {message && <p>{message}</p>}

      <div className="card">
        <h2>Upload</h2>
        <form onSubmit={onUpload}>
          <input type="file" onChange={(e) => setFile(e.target.files?.[0] ?? null)} required />
          <select
            value={classification}
            onChange={(e) => setClassification(e.target.value as typeof classification)}
          >
            <option value="public">public</option>
            <option value="private">private</option>
            <option value="sensitive">sensitive</option>
          </select>
          <button type="submit">Upload</button>
        </form>
      </div>

      <div className="card">
        <h2>Your files</h2>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Classification</th>
              <th>Size</th>
              <th>Job status</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            {files.map((item) => (
              <tr key={item.file_id}>
                <td>{item.filename}</td>
                <td>
                  <span className={`badge ${item.classification === 'sensitive' ? 'sensitive' : ''}`}>
                    {item.classification}
                  </span>
                </td>
                <td>{item.size} bytes</td>
                <td>
                  {item.latest_job_status ? (
                    <span className="badge">{item.latest_job_status}</span>
                  ) : (
                    <span className="muted">—</span>
                  )}
                </td>
                <td>
                  <button type="button" onClick={() => onProcess(item.file_id)}>
                    Process
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
