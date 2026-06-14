/// <reference types="vite/client" />

interface TaskVaultRuntimeConfig {
  apiBaseUrl: string;
  workerApiUrl: string;
  featureAdminReports: boolean;
}

interface Window {
  __TASKVAULT_CONFIG__?: TaskVaultRuntimeConfig;
}

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string;
  readonly VITE_WORKER_API_URL: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
