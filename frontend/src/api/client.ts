import { getApiBaseUrl, getWorkerApiUrl } from '../config';
import { clearToken, getToken } from '../auth/token';

type HttpMethod = 'GET' | 'POST' | 'PATCH' | 'DELETE';

interface RequestOptions {
  method?: HttpMethod;
  body?: unknown;
  auth?: boolean;
  formData?: FormData;
}

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message);
  }
}

function buildUrl(path: string, baseUrl = getApiBaseUrl()): string {
  if (path.startsWith('http')) {
    return path;
  }
  const prefix = baseUrl || '';
  return `${prefix}${path.startsWith('/') ? path : `/${path}`}`;
}

export async function apiRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = {};

  if (!options.formData) {
    headers['Content-Type'] = 'application/json';
  }

  if (options.auth !== false) {
    const token = getToken();
    if (token) {
      headers.Authorization = `Bearer ${token}`;
    }
  }

  const response = await fetch(buildUrl(path), {
    method: options.method ?? 'GET',
    headers,
    body: options.formData ?? (options.body ? JSON.stringify(options.body) : undefined),
  });

  if (response.status === 401 && options.auth !== false) {
    clearToken();
    if (!window.location.pathname.startsWith('/login')) {
      window.location.href = '/login';
    }
    throw new ApiError('unauthorized', 401);
  }

  if (!response.ok) {
    const text = await response.text();
    throw new ApiError(text || response.statusText, response.status);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}

export async function workerRequest<T>(path: string, options: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };

  const response = await fetch(buildUrl(path, getWorkerApiUrl()), {
    method: options.method ?? 'GET',
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  if (!response.ok) {
    const text = await response.text();
    throw new ApiError(text || response.statusText, response.status);
  }

  return (await response.json()) as T;
}

// Auth
export const login = (email: string, password: string) =>
  apiRequest<import('./types').AuthResponse>('/api/auth/login', {
    method: 'POST',
    body: { email, password },
    auth: false,
  });

export const register = (email: string, password: string) =>
  apiRequest<import('./types').AuthResponse>('/api/auth/register', {
    method: 'POST',
    body: { email, password },
    auth: false,
  });

export const getMe = () => apiRequest<import('./types').User>('/api/me');

// Tasks
export const listTasks = () => apiRequest<import('./types').Task[]>('/api/tasks');
export const createTask = (title: string, description?: string) =>
  apiRequest<import('./types').Task>('/api/tasks', {
    method: 'POST',
    body: { title, description },
  });
export const updateTask = (id: string, status: string) =>
  apiRequest<import('./types').Task>(`/api/tasks/${id}`, {
    method: 'PATCH',
    body: { status },
  });
export const deleteTask = (id: string) =>
  apiRequest<void>(`/api/tasks/${id}`, { method: 'DELETE' });

// Files
export const listFiles = () => apiRequest<import('./types').FileRecord[]>('/api/files');
export const uploadFile = (file: File, classification: string) => {
  const formData = new FormData();
  formData.append('file', file);
  formData.append('classification', classification);
  return apiRequest<import('./types').FileRecord>('/api/files/upload', {
    method: 'POST',
    formData,
  });
};
export const processFile = (id: string) =>
  apiRequest<import('./types').Job>(`/api/files/${id}/process`, { method: 'POST' });

// Admin
export const runAdminReport = () =>
  apiRequest<{ report: import('./types').Report; job: import('./types').Job | null }>(
    '/api/admin/reports/run',
    { method: 'POST' },
  );
export const listAuditEvents = () =>
  apiRequest<import('./types').AuditEvent[]>('/api/admin/audit-events');
export const listAdminFiles = () =>
  apiRequest<import('./types').FileRecord[]>('/api/admin/files');

// Health (public)
export const getHealth = () =>
  apiRequest<import('./types').HealthStatus>('/api/healthz', { auth: false });
export const getVersion = () =>
  apiRequest<import('./types').VersionInfo>('/api/version', { auth: false });

export const getWorkerJob = (id: string) =>
  workerRequest<import('./types').Job>(`/internal/jobs/${id}`, { auth: false });
