# Backend API route map

Service: `backend-api` (port 8080)

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/api/healthz` | **none** | Liveness probe |
| GET | `/api/readyz` | **none** | Readiness (DB check) |
| GET | `/api/version` | **none** | Build metadata |
| GET | `/metrics` | **none** | Prometheus metrics |
| GET | `/api/debug/status` | **none** | **vuln-1** — intentional weak route |
| GET | `/api/admin/reports/preview` | **none** | **vuln-1** — counts only; `FEATURE_ADMIN_PREVIEW` |
| POST | `/api/auth/register` | **none** | Create account + JWT |
| POST | `/api/auth/login` | **none** | Login + JWT |
| POST | `/api/auth/logout` | user | Stateless logout audit |
| GET | `/api/me` | user | Current user |
| POST | `/api/tasks` | user | Create task |
| GET | `/api/tasks` | user | List own tasks |
| GET | `/api/tasks/:id` | user | Get own task |
| PATCH | `/api/tasks/:id` | user | Update own task |
| DELETE | `/api/tasks/:id` | user | Delete own task |
| POST | `/api/files/upload` | user | Multipart upload → S3 |
| GET | `/api/files` | user | List files (admin: all) |
| GET | `/api/files/:id` | user | File metadata |
| GET | `/api/files/:id/download-url` | user | Presigned URL |
| POST | `/api/files/:id/process` | user | Enqueue worker job |
| POST | `/api/admin/reports/run` | **admin** | Run admin report |
| GET | `/api/admin/reports` | **admin** | List reports |
| GET | `/api/admin/audit-events` | **admin** | Paginated audit log |
| GET | `/api/admin/users` | **admin** | List users |
| GET | `/api/admin/files` | **admin** | All files incl. sensitive |
| GET | `/api/admin/internal/k8s-secret-names` | **admin** | **vuln-3** demo; `FEATURE_K8S_SECRET_LIST` |

**Auth legend:** `none` = public allowlist; `user` = valid JWT; `admin` = JWT with `role=admin`.

Public allowlist is defined in `src/middleware/auth.ts` (`PUBLIC_ROUTE_PATTERNS`).
