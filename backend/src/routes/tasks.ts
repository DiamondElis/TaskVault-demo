import { Router } from 'express';
import { audit } from '../logger.js';
import { requireAuth } from '../middleware/auth.js';
import * as tasksRepo from '../repositories/tasks.repo.js';

const router = Router();

router.use(requireAuth);

router.post('/', async (req, res) => {
  const title = String(req.body?.title ?? '').trim();
  const description = req.body?.description ? String(req.body.description) : null;

  if (!title) {
    res.status(400).json({ error: 'title_required' });
    return;
  }

  const task = await tasksRepo.createTask(req.user!.id, title, description);

  await audit('task_created', {
    user_id: req.user!.id,
    request_id: req.requestId,
    task_id: task.id,
  });

  res.status(201).json(task);
});

router.get('/', async (req, res) => {
  const tasks = await tasksRepo.listByOwner(req.user!.id);
  res.status(200).json(tasks);
});

router.get('/:id', async (req, res) => {
  const task = await tasksRepo.findById(req.params.id);
  if (!task || task.owner_user_id !== req.user!.id) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  res.status(200).json(task);
});

router.patch('/:id', async (req, res) => {
  const task = await tasksRepo.updateTask(req.params.id, req.user!.id, {
    title: req.body?.title ? String(req.body.title) : undefined,
    description:
      req.body?.description !== undefined ? String(req.body.description) : undefined,
    status: req.body?.status ? String(req.body.status) : undefined,
  });

  if (!task) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  res.status(200).json(task);
});

router.delete('/:id', async (req, res) => {
  const deleted = await tasksRepo.deleteTask(req.params.id, req.user!.id);
  if (!deleted) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  res.status(204).send();
});

export default router;
