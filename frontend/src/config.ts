function readRuntimeConfig(): TaskVaultRuntimeConfig {
  return (
    window.__TASKVAULT_CONFIG__ ?? {
      apiBaseUrl: '',
      workerApiUrl: 'http://localhost:8081',
      featureAdminReports: true,
    }
  );
}

export function getApiBaseUrl(): string {
  const runtime = readRuntimeConfig().apiBaseUrl;
  if (runtime) {
    return runtime.replace(/\/$/, '');
  }

  const buildTime = import.meta.env.VITE_API_BASE_URL;
  if (buildTime) {
    return buildTime.replace(/\/$/, '');
  }

  return '';
}

export function getWorkerApiUrl(): string {
  const runtime = readRuntimeConfig().workerApiUrl;
  if (runtime) {
    return runtime.replace(/\/$/, '');
  }

  const buildTime = import.meta.env.VITE_WORKER_API_URL;
  if (buildTime) {
    return buildTime.replace(/\/$/, '');
  }

  return '';
}

export function isAdminReportsEnabled(): boolean {
  return readRuntimeConfig().featureAdminReports ?? true;
}
