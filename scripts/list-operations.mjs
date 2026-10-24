#!/usr/bin/env node
// Owner: A1. Prints one line per contract operation, for shell scripts:
//   METHOD PATH AUTH BODY OPERATION_ID OWNER STATUSES (comma-separated, from the contract)
// with sample values filled into the path parameters.
import { readOperations } from './lib/contract-operations.mjs';

const SAMPLE = {
  id: '11111111-1111-4111-8111-111111111111',
  cardId: '22222222-2222-4222-8222-222222222222',
  n: '0',
  slug: 'demo',
};

for (const op of readOperations()) {
  const path = op.path.replace(/\{(\w+)\}/g, (_, name) => SAMPLE[name] ?? 'x');
  console.log(
    [op.method, path, op.auth, op.body, op.id, op.owner, op.statuses.join(',')].join(' '),
  );
}
