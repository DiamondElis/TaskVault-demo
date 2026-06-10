import { Router } from 'express';
import multer from 'multer';
import { buildObjectKey, getPresignedDownloadUrl, putObject } from '../aws/s3.js';
import { sendJob } from '../aws/sqs.js';
import { audit } from '../logger.js';
import { requireAuth } from '../middleware/auth.js';
import * as filesRepo from '../repositories/files.repo.js';
import type { FileClassification } from '../repositories/files.repo.js';
import * as jobsRepo from '../repositories/jobs.repo.js';

const router = Router();
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });

router.use(requireAuth);

function parseClassification(value: unknown): FileClassification | null {
  if (value === 'public' || value === 'private' || value === 'sensitive') {
    return value;
  }
  return null;
}

router.post('/upload', upload.single('file'), async (req, res) => {
  if (!req.file) {
    res.status(400).json({ error: 'file_required' });
    return;
  }

  const classification = parseClassification(req.body?.classification ?? 'private');
  if (!classification) {
    res.status(400).json({ error: 'invalid_classification' });
    return;
  }

  const key = buildObjectKey(classification, req.user!.id, req.file.originalname);
  const { bucket, key: s3Key } = await putObject({
    key,
    body: req.file.buffer,
    contentType: req.file.mimetype || 'application/octet-stream',
  });

  const file = await filesRepo.createFile({
    ownerUserId: req.user!.id,
    filename: req.file.originalname,
    s3Bucket: bucket,
    s3Key,
    contentType: req.file.mimetype || 'application/octet-stream',
    size: req.file.size,
    classification,
  });

  await audit('file_uploaded', {
    user_id: req.user!.id,
    s3_bucket: bucket,
    s3_key: s3Key,
    request_id: req.requestId,
    file_id: file.file_id,
  });

  await audit('s3_object_written', {
    user_id: req.user!.id,
    s3_bucket: bucket,
    s3_key: s3Key,
    request_id: req.requestId,
  });

  res.status(201).json(file);
});

router.get('/', async (req, res) => {
  const files =
    req.user!.role === 'admin'
      ? await filesRepo.listAll()
      : await filesRepo.listByOwner(req.user!.id);

  res.status(200).json(files);
});

router.get('/:id', async (req, res) => {
  const file = await filesRepo.findById(req.params.id);
  if (!file) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  if (req.user!.role !== 'admin' && file.owner_user_id !== req.user!.id) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  res.status(200).json(file);
});

router.get('/:id/download-url', async (req, res) => {
  const file = await filesRepo.findById(req.params.id);
  if (!file) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  if (req.user!.role !== 'admin' && file.owner_user_id !== req.user!.id) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  const url = await getPresignedDownloadUrl(file.s3_bucket, file.s3_key);
  res.status(200).json({ url, expiresInSeconds: 300 });
});

router.post('/:id/process', async (req, res) => {
  const file = await filesRepo.findById(req.params.id);
  if (!file) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  if (req.user!.role !== 'admin' && file.owner_user_id !== req.user!.id) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  const job = await jobsRepo.createJob(file.file_id, 'file_analysis');
  await sendJob({ jobId: job.id, fileId: file.file_id, type: job.type });

  await audit('worker_job_created', {
    user_id: req.user!.id,
    request_id: req.requestId,
    job_id: job.id,
    file_id: file.file_id,
  });

  res.status(202).json(job);
});

export default router;
