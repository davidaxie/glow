/**
 * Throwaway people, rooms, check-ins and matches on a live local Supabase, for B8's tests.
 * Everything made here is deleted by `cleanup()`, and every address is `@glow.test`.
 */
import { randomUUID } from 'node:crypto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { moderationFixtureJpeg } from '@/server/moderation';
import { adminClient, tag, type Live } from './live';

type Gender = Database['public']['Enums']['gender'];

export type Person = {
  readonly id: string;
  readonly email: string;
  readonly token: string;
};

export type Card = { readonly id: string; readonly path: string; readonly roomId: string };

export class World {
  readonly db: SupabaseClient<Database>;
  private readonly people: string[] = [];
  private readonly rooms: string[] = [];

  constructor(private readonly live: Live) {
    this.db = adminClient(live);
  }

  /** A signed-in person who finished onboarding. */
  async person(gender: Gender = 'woman', showMe: Gender[] = ['man', 'woman', 'nonbinary']) {
    const email = `b8-${tag()}@glow.test`;
    const password = `pw-${randomUUID()}`;
    const created = await this.db.auth.admin.createUser({ email, password, email_confirm: true });
    if (created.error || !created.data.user) throw new Error(`createUser: ${created.error?.message}`);
    const id = created.data.user.id;
    this.people.push(id);
    const profile = await this.db
      .from('profiles')
      .update({
        first_name: 'Test',
        birthdate: '1995-05-05',
        gender,
        show_me: showMe,
        onboarding_step: 'complete',
      })
      .eq('id', id);
    if (profile.error) throw new Error(`profile: ${profile.error.message}`);
    const anon = createClient(this.live.url, this.live.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const session = await anon.auth.signInWithPassword({ email, password });
    if (session.error || !session.data.session) throw new Error(`sign in: ${session.error?.message}`);
    return { id, email, token: session.data.session.access_token } satisfies Person;
  }

  /** A live room that started an hour ago and ends in three hours. */
  async room(): Promise<string> {
    const now = Date.now();
    const { data, error } = await this.db
      .from('rooms')
      .insert({
        slug: `b8-${tag()}`,
        name: 'B8 test room',
        lat: 37.8029,
        lng: -122.4484,
        starts_at: new Date(now - 3600_000).toISOString(),
        ends_at: new Date(now + 3 * 3600_000).toISOString(),
      })
      .select('id')
      .single();
    if (error || !data) throw new Error(`room: ${error?.message}`);
    this.rooms.push(data.id);
    return data.id;
  }

  /** Checks a person in with a stored card photo, as B3's route would. */
  async checkIn(person: Person, roomId: string): Promise<Card> {
    const id = randomUUID();
    const path = `${roomId}/${id}.jpg`;
    // A passed join check (migration 0002 requires one before a check-in).
    await this.db
      .from('location_checks')
      .insert({ user_id: person.id, room_id: roomId, purpose: 'join', result: 'pass' });
    const photo = await moderationFixtureJpeg([]);
    const upload = await this.db.storage
      .from('room-cards')
      .upload(path, photo, { contentType: 'image/jpeg' });
    if (upload.error) throw new Error(`upload: ${upload.error.message}`);
    const { error } = await this.db.rpc('create_checkin', {
      p_user_id: person.id,
      p_room_id: roomId,
      p_checkin_id: id,
      p_card_path: path,
      p_tags: { topColor: 'blue' },
    });
    if (error) throw new Error(`create_checkin: ${error.message}`);
    return { id, path, roomId };
  }

  /** Card IDs in this person's deck right now (and records them as shown, like the app). */
  async deck(person: Person, roomId: string): Promise<string[]> {
    const { data, error } = await this.db.rpc('get_deck', {
      p_viewer_id: person.id,
      p_room_id: roomId,
      p_filters: {},
      p_limit: 10,
      p_offset: 0,
    });
    if (error) throw new Error(`get_deck: ${error.message}`);
    return ((data as { cards?: { id: string }[] }).cards ?? []).map((c) => c.id);
  }

  /** Both tap each other; returns the match ID. */
  async match(a: Person, aCard: Card, b: Person, bCard: Card): Promise<string> {
    await this.deck(a, aCard.roomId);
    await this.deck(b, bCard.roomId);
    const first = await this.db.rpc('record_tap', {
      p_viewer_id: a.id,
      p_room_id: bCard.roomId,
      p_checkin_id: bCard.id,
    });
    if (first.error) throw new Error(`tap: ${first.error.message}`);
    const second = await this.db.rpc('record_tap', {
      p_viewer_id: b.id,
      p_room_id: aCard.roomId,
      p_checkin_id: aCard.id,
    });
    if (second.error) throw new Error(`tap: ${second.error.message}`);
    const matchId = (second.data as { matchId?: string }).matchId;
    if (!matchId) throw new Error('no match');
    return matchId;
  }

  async objectExists(bucket: 'room-cards' | 'profile-photos', path: string): Promise<boolean> {
    const slash = path.lastIndexOf('/');
    const { data } = await this.db.storage
      .from(bucket)
      .list(path.slice(0, slash), { search: path.slice(slash + 1) });
    return (data ?? []).some((o) => o.name === path.slice(slash + 1));
  }

  async cleanup(): Promise<void> {
    for (const roomId of this.rooms) {
      const { data } = await this.db.storage.from('room-cards').list(roomId);
      const paths = (data ?? []).map((o) => `${roomId}/${o.name}`);
      if (paths.length > 0) await this.db.storage.from('room-cards').remove(paths);
    }
    for (const id of this.people) {
      const { data } = await this.db.storage.from('profile-photos').list(id);
      const paths = (data ?? []).map((o) => `${id}/${o.name}`);
      if (paths.length > 0) await this.db.storage.from('profile-photos').remove(paths);
      await this.db.auth.admin.deleteUser(id);
    }
    if (this.rooms.length > 0) await this.db.from('rooms').delete().in('id', this.rooms);
  }
}
