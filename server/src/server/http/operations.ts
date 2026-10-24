/**
 * The operation registry the route helper reads. Today it's A1's placeholder; when
 * A2's generated contract merges, this file re-exports `server/src/contracts` instead
 * and the placeholder is deleted. Route files never import the registry directly.
 */
import { placeholderOperations } from './contract-placeholder';

export const operations = placeholderOperations;

export type Operations = typeof operations;
export type OperationId = keyof Operations;
