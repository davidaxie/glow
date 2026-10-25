// Owner: X1. Blind mode. Logic in server/src/server/blind.
import { route } from '@/server/http';
import { blindGetPartnerPhoto } from '@/server/blind/handlers';

export const GET = route('blindGetPartnerPhoto', blindGetPartnerPhoto);
