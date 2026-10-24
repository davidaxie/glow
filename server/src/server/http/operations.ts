/**
 * The operation registry the route helper reads: A2's generated contract, from
 * contracts/openapi.yaml through scripts/codegen.sh. Route files never import the
 * registry directly; they name an operationId in `route()`.
 */
import { operations as generated } from '@/contracts/operations';

export const operations = generated;

export type Operations = typeof operations;
export type OperationId = keyof Operations;
