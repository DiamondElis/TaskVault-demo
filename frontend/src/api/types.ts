export interface User {
  id: string;
  email: string;
  role: string;
}

export interface AuthResponse {
  token: string;
  user: User;
}

export interface Task {
  id: string;
  title: string;
  description: string | null;
  status: string;
  owner_user_id: string;
  created_at: string;
  updated_at: string;
}

export interface FileRecord {
  file_id: string;
  owner_user_id: string;
  filename: string;
  s3_bucket: string;
  s3_key: string;
  content_type: string;
  size: string;
  classification: 'public' | 'private' | 'sensitive';
  created_at: string;
  latest_job_id?: string | null;
  latest_job_status?: string | null;
}

export interface Job {
  id: string;
  file_id: string;
  type: string;
  status: string;
  result_s3_key: string | null;
  created_at: string;
  updated_at: string;
}

export interface AuditEvent {
  id: string;
  service: string;
  event_type: string;
  user_id: string | null;
  request_id: string;
  timestamp: string;
}

export interface Report {
  id: string;
  requested_by: string;
  user_count: number;
  file_count: number;
  sensitive_file_count: number;
  report_s3_key: string;
  created_at: string;
}

export interface HealthStatus {
  status: string;
}

export interface VersionInfo {
  service: string;
  buildSha: string;
  region: string;
}
