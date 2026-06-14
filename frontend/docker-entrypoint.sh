#!/bin/sh
set -eu

API_BASE_URL="${API_BASE_URL:-}"
WORKER_API_URL="${WORKER_API_URL:-}"
FEATURE_ADMIN_REPORTS="${FEATURE_ADMIN_REPORTS:-true}"

cat > /usr/share/nginx/html/config.js <<EOF
window.__TASKVAULT_CONFIG__ = {
  apiBaseUrl: '${API_BASE_URL}',
  workerApiUrl: '${WORKER_API_URL}',
  featureAdminReports: ${FEATURE_ADMIN_REPORTS},
};
EOF

exec nginx -g 'daemon off;'
