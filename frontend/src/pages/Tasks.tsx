import { FormEvent, useEffect, useState } from 'react';
import { createTask, deleteTask, listTasks, updateTask } from '../api/client';
import type { Task } from '../api/types';

const STATUSES = ['open', 'in_progress', 'done'];

export function TasksPage() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [error, setError] = useState('');

  const refresh = () => {
    listTasks()
      .then(setTasks)
      .catch(() => setError('Failed to load tasks.'));
  };

  useEffect(() => {
    refresh();
  }, []);

  const onCreate = async (event: FormEvent) => {
    event.preventDefault();
    setError('');

    try {
      await createTask(title, description || undefined);
      setTitle('');
      setDescription('');
      refresh();
    } catch {
      setError('Failed to create task.');
    }
  };

  const onStatusChange = async (task: Task, status: string) => {
    try {
      await updateTask(task.id, status);
      refresh();
    } catch {
      setError('Failed to update task.');
    }
  };

  const onDelete = async (id: string) => {
    try {
      await deleteTask(id);
      refresh();
    } catch {
      setError('Failed to delete task.');
    }
  };

  return (
    <div>
      <h1>Tasks</h1>
      {error && <p className="error">{error}</p>}

      <div className="card">
        <h2>Create task</h2>
        <form onSubmit={onCreate}>
          <input
            placeholder="Title"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            required
          />
          <textarea
            placeholder="Description (optional)"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
          />
          <button type="submit">Add task</button>
        </form>
      </div>

      <div className="card">
        <h2>Your tasks</h2>
        <table>
          <thead>
            <tr>
              <th>Title</th>
              <th>Status</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {tasks.map((task) => (
              <tr key={task.id}>
                <td>
                  <strong>{task.title}</strong>
                  {task.description && <div className="muted">{task.description}</div>}
                </td>
                <td>
                  <span className="badge">{task.status}</span>
                </td>
                <td>
                  {STATUSES.map((status) => (
                    <button
                      key={status}
                      type="button"
                      className="secondary"
                      onClick={() => onStatusChange(task, status)}
                      style={{ marginRight: '0.25rem' }}
                    >
                      {status}
                    </button>
                  ))}
                  <button type="button" className="secondary" onClick={() => onDelete(task.id)}>
                    Delete
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
