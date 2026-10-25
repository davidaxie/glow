/**
 * Throwaway people, rooms, check-ins, photos and matches on a live local stack, for D2's
 * tests. Everything made here is deleted by `cleanup()`; every address is `@glow.test`, and
 * every name is unique, so a test can search any response for it.
 */
import { randomUUID } from 'node:crypto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/contracts';
import { moderationFixtureJpeg } from '@/server/moderation';
import { tag, type Live } from './live';

type Gender = Database['public']['Enums']['gender'];

export type Person = {
  readonly id: string;
  readonly email: string;
  readonly firstName: string;
  readonly token: string;
};

export type Card = { readonly id: string; readonly path: string; readonly roomId: string };

export class World {
  readonly db: SupabaseClient<Database>;
  private readonly people: string[] = [];
  private readonly rooms: string[] = [];

  constructor(private readonly live: Live) {
    this.db = createClient<Database>(live.url, live.serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }

  /** A signed-in person who finished onboarding, with one approved profile photo. */
  async person(
    gender: Gender = 'woman',
    showMe: Gender[] = ['man', 'woman', 'nonbinary'],
  ): Promise<Person> {
    const email = `d2-${tag()}@glow.test`;
    const password = `pw-${randomUUID()}`;
    const firstName = `Dtwo${tag().replace(/[^a-z]/g, 'x')}`;
    const created = await this.db.auth.admin.createUser({ email, password, email_confirm: true });
    if (created.error || !created.data.user)
      throw new Error(`createUser: ${created.error?.message}`);
    const id = created.data.user.id;
    this.people.push(id);
    const profile = await this.db
      .from('profiles')
      .update({
        first_name: firstName,
        birthdate: '1995-05-05',
        gender,
        show_me: showMe,
        onboarding_step: 'complete',
      })
      .eq('id', id);
    if (profile.error) throw new Error(`profile: ${profile.error.message}`);
    await this.profilePhoto(id);
    const anon = createClient(this.live.url, this.live.anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const session = await anon.auth.signInWithPassword({ email, password });
    if (session.error || !session.data.session)
      throw new Error(`sign in: ${session.error?.message}`);
    return { id, email, firstName, token: session.data.session.access_token };
  }

  /** An approved profile photo at position 0, stored like B1's route stores it. */
  async profilePhoto(userId: string): Promise<string> {
    const photoId = randomUUID();
    const path = `${userId}/${photoId}.jpg`;
    const upload = await this.db.storage
      .from('profile-photos')
      .upload(path, await moderationFixtureJpeg([]), { contentType: 'image/jpeg' });
    if (upload.error) throw new Error(`profile photo upload: ${upload.error.message}`);
    const row = await this.db
      .from('profile_photos')
      .insert({ id: photoId, user_id: userId, path, position: 0, moderation_status: 'approved' });
    if (row.error) throw new Error(`profile photo row: ${row.error.message}`);
    return path;
  }

  /** A live room that started an hour ago and ends in three hours, with three spots. */
  async room(): Promise<string> {
    const now = Date.now();
    const { data, error } = await this.db
      .from('rooms')
      .insert({
        slug: `d2-${tag()}`,
        name: 'D2 test room',
        lat: 37.8029,
        lng: -122.4484,
        starts_at: new Date(now - 3600_000).toISOString(),
        ends_at: new Date(now + 3 * 3600_000).toISOString(),
      })
      .select('id')
      .single();
    if (error || !data) throw new Error(`room: ${error?.message}`);
    this.rooms.push(data.id);
    await this.db
      .from('meeting_spots')
      .insert(
        ['Spot A', 'Spot B', 'Spot C'].map((name, sort) => ({ room_id: data.id, name, sort })),
      );
    return data.id;
  }

  /** Checks a person in with a stored card photo, as B3's route does. */
  async checkIn(person: Person, roomId: string): Promise<Card> {
    const id = randomUUID();
    const path = `${roomId}/${id}.jpg`;
    await this.db
      .from('location_checks')
      .insert({ user_id: person.id, room_id: roomId, purpose: 'join', result: 'pass' });
    const upload = await this.db.storage
      .from('room-cards')
      .upload(path, await moderationFixtureJpeg([]), { contentType: 'image/jpeg' });
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

  /** Both tap each other through the database; returns the match ID. */
  async match(a: Person, aCard: Card, b: Person, bCard: Card): Promise<string> {
    for (const [viewer, card] of [
      [a, aCard],
      [b, bCard],
    ] as const) {
      const deck = await this.db.rpc('get_deck', {
        p_viewer_id: viewer.id,
        p_room_id: card.roomId,
        p_filters: {},
        p_limit: 10,
        p_offset: 0,
      });
      if (deck.error) throw new Error(`get_deck: ${deck.error.message}`);
    }
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
