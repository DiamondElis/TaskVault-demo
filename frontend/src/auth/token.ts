const TOKEN_KEY = 'taskvault_jwt';
const LAST_JOB_KEY = 'taskvault_last_job_id';

export function getToken(): string | null {
  return sessionStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
  sessionStorage.setItem(TOKEN_KEY, token);
}

export function clearToken(): void {
  sessionStorage.removeItem(TOKEN_KEY);
}

export function setLastJobId(jobId: string): void {
  sessionStorage.setItem(LAST_JOB_KEY, jobId);
}

export function getLastJobId(): string | null {
  return sessionStorage.getItem(LAST_JOB_KEY);
}
