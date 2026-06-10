import { getConfig } from '../config.js';
import { log } from '../logger.js';

/**
 * vuln-3: optional runtime demo — lists secret *names* in demo-prod only.
 * Default OFF (FEATURE_K8S_SECRET_LIST=false). Never returns secret values.
 */
export async function listSecretNames(requestId: string): Promise<string[]> {
  const config = getConfig();

  if (!config.featureK8sSecretList) {
    return [];
  }

  const tokenPath =
    process.env.K8S_SA_TOKEN_PATH ?? '/var/run/secrets/kubernetes.io/serviceaccount/token';
  const namespace = process.env.K8S_NAMESPACE ?? 'demo-prod';
  const apiServer = process.env.KUBERNETES_SERVICE_HOST
    ? `https://${process.env.KUBERNETES_SERVICE_HOST}:${process.env.KUBERNETES_SERVICE_PORT ?? '443'}`
    : process.env.K8S_API_SERVER;

  if (!apiServer) {
    log('warn', {
      event_type: 'k8s_secret_list_skipped',
      message: 'No Kubernetes API server configured',
      request_id: requestId,
    });
    return [];
  }

  const fs = await import('node:fs/promises');
  const token = await fs.readFile(tokenPath, 'utf8');

  const response = await fetch(
    `${apiServer}/api/v1/namespaces/${namespace}/secrets`,
    {
      headers: { Authorization: `Bearer ${token.trim()}` },
      // Demo cluster uses in-cluster CA; skip verify only for local mock if needed.
    },
  );

  if (!response.ok) {
    throw new Error(`Kubernetes API returned ${response.status}`);
  }

  const body = (await response.json()) as { items?: Array<{ metadata?: { name?: string } }> };
  return (body.items ?? [])
    .map((item) => item.metadata?.name)
    .filter((name): name is string => Boolean(name));
}
