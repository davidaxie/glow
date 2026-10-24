// Owner: B2. Rooms and joining: resolving codes and links, the location check, join
// tickets, leaving, room state, and the web answers behind room links.
//
// For other agents:
// - B3: `verifyJoinTicket(ticket, { userId, roomId })` before `create_checkin`.
// - B7: `displayToken` lives in `@/server/qr`.
// - C2: `checkFix` and `recordLocationCheck` live in `@/server/geo`.
export { resolveRoom } from './resolve';
export { joinRoom, locationInaccurate, notInRoom } from './join';
export { leaveRoom } from './leave';
export { getRoomState } from './state';
export { getAppSiteAssociation, getRoomWebPage, appSiteAssociation, roomWebPage } from './web';
export {
  issueJoinTicket,
  verifyJoinTicket,
  type IssuedJoinTicket,
  type JoinTicketResult,
  type VerifiedJoinTicket,
} from './ticket';
