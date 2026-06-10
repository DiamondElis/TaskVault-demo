import { Router } from 'express';
import { listSecretNames } from '../aws/k8s-secrets-demo.js';
import { sendJob } from '../aws/sqs.js';
import { getConfig } from '../config.js';
import { audit } from '../logger.js';
import { requireAdmin, requireAuth } from '../middleware/auth.js';
import * as auditRepo from '../repositories/audit.repo.js';
import * as filesRepo from '../repositories/files.repo.js';
import * as jobsRepo from '../repositories/jobs.repo.js';
import * as reportsRepo from '../repositories/reports.repo.js';
import * as usersRepo from '../repositories/users.repo.js';

const router = Router();

router.use(requireAuth, requireAdmin);

router.post('/reports/run', async (req, res) => {
  const config = getConfig();

  if (!config.featureAdminReports) {
    res.status(403).json({ error: 'feature_disabled' });
    return;
  }

  const [userCount, fileCount, sensitiveFileCount] = await Promise.all([
    usersRepo.countUsers(),
    filesRepo.countFiles(),
    filesRepo.countSensitiveFiles(),
  ]);

  const reportS3Key = `reports/admin/report-${Date.now()}.json`;
  const report = await reportsRepo.createReport({
    requestedBy: req.user!.id,
    userCount,
    fileCount,
    sensitiveFileCount,
    reportS3Key,
  });

  const [firstFile] = await filesRepo.listAll(1);
  let job = null;

  if (firstFile) {
    job = await jobsRepo.createJob(firstFile.file_id, 'admin_report');
    await sendJob({
      jobId: job.id,
      fileId: job.file_id,
      type: 'admin_report',
    });
  }

  await audit('admin_report_requested', {
    user_id: req.user!.id,
    request_id: req.requestId,
    report_id: report.id,
    report_s3_key: reportS3Key,
  });

  res.status(202).json({ report, job });
});

router.get('/reports', async (req, res) => {
  const limit = Number(req.query.limit ?? 50);
  const offset = Number(req.query.offset ?? 0);
  const reports = await reportsRepo.listReports(limit, offset);
  res.status(200).json(reports);
});

router.get('/audit-events', async (req, res) => {
  const limit = Number(req.query.limit ?? 50);
  const offset = Number(req.query.offset ?? 0);
  const events = await auditRepo.list(limit, offset);
  res.status(200).json(events);
});

router.get('/users', async (req, res) => {
  const limit = Number(req.query.limit ?? 100);
  const offset = Number(req.query.offset ?? 0);
  const users = await usersRepo.listUsers(limit, offset);
  res.status(200).json(users);
});

router.get('/files', async (req, res) => {
  const limit = Number(req.query.limit ?? 100);
  const offset = Number(req.query.offset ?? 0);
  const files = await filesRepo.listAll(limit, offset);
  res.status(200).json(files);
});

// vuln-3: optional runtime demo — lists secret names only when FEATURE_K8S_SECRET_LIST=true.
router.get('/internal/k8s-secret-names', async (req, res) => {
  const names = await listSecretNames(req.requestId);
  res.status(200).json({ namespace: process.env.K8S_NAMESPACE ?? 'demo-prod', names });
});

export default router;
