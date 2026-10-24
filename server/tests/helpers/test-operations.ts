import { z } from 'zod';
import { defineOperations } from '@/server/http/operation';

/** A tiny contract used only by the route helper's tests. */
export const testOperations = defineOperations({
  echo: {
    method: 'POST',
    path: '/api/test/{id}',
    auth: 'user',
    params: z.object({ id: z.uuid() }),
    query: z.object({ page: z.coerce.number().int().min(1).optional() }),
    body: z.object({ lat: z.number().min(-90).max(90), lng: z.number(), note: z.string().max(5) }),
    responses: {
      200: z.object({ id: z.uuid(), ok: z.boolean(), page: z.number().optional() }),
      204: null,
    },
  },
  file: { method: 'GET', path: '/api/test/file', auth: 'public', responses: { 200: 'raw' } },
  upload: {
    method: 'POST',
    path: '/api/test/upload',
    auth: 'user',
    body: 'multipart',
    maxBodyBytes: 2048,
    responses: { 201: z.object({ size: z.number() }) },
  },
});
