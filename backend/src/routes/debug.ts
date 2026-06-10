import { Router } from 'express';
import { getConfig } from '../config.js';
import * as filesRepo from '../repositories/files.repo.js';
import * as usersRepo from '../repositories/users.repo.js';

const router = Router();

// vuln-1 (spec §7): intentional unauthenticated debug route — harmless metadata only.
router.get('/api/debug/status', (_req, res) => {
  const config = getConfig();
  res.status(200).json({
    service: 'backend-api',
    buildSha: config.buildSha,
    region: config.awsRegion,
    bucket: config.s3Bucket,
  });
});

// vuln-1 (spec §7): second weak surface — counts only, no row data. Behind feature flag.
router.get('/api/admin/reports/preview', async (_req, res) => {
  const config = getConfig();

  if (!config.featureAdminPreview) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  const [userCount, fileCount, sensitiveFileCount] = await Promise.all([
    usersRepo.countUsers(),
    filesRepo.countFiles(),
    filesRepo.countSensitiveFiles(),
  ]);

  res.status(200).json({ userCount, fileCount, sensitiveFileCount });
});

export default router;
