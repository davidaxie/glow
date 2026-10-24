/**
 * Owner: B4. GET /api/matches through the real route and the real list_matches: first names
 * only ever after a match (P1), never a user ID (D20), newest first, ended matches gone, and
 * timeouts applied. See tests/deck/harness.ts for when these run.
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { CHOICE_WINDOW_SECONDS, zMatchList, type MatchList, type TapResult } from '@/contracts';
import { IT, useRealSupabase, World, type Person } from '../deck/harness';

// Setting up dozens of people takes a while on a busy machine.
vi.setConfig({ hookTimeout: 180_000, testTimeout: 180_000 });

vi.mock('@/server/deck/dependencies', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@/server/deck/dependencies')>();
  return {
    ...actual,
    notify: vi.fn(async () => ({ realtime: 'skipped', push: null })),
    notifySettled: vi.fn(async () => []),
  };
});
const { notifySettled } = await import('@/server/deck/dependencies');

describe.runIf(IT)('GET /api/matches (integration)', { timeout: 120_000 }, () => {
  let world: World;
  let room: string;
  let ana: Person;
  let ben: Person;
  let cal: Person;
  let dev: Person;
  const card = new Map<string, string>();

  const list = async (p: Person): Promise<MatchList> => {
    const res = await world.matches(p);
    expect(res.status).toBe(200);
    const text = await res.clone().text();
    for (const id of [ana, ben, cal, dev].map((x) => x.id)) expect(text).not.toContain(id);
    const body = (await res.json()) as MatchList;
    expect(zMatchList.parse(body)).toEqual(body);
    return body;
  };
  const tap = async (p: Person, other: Person) =>
    (await (await world.tap(p, room, card.get(other.id)!)).json()) as TapResult;

  beforeAll(async () => {
    world = new World(IT!);
    useRealSupabase(IT!);
    room = await world.room();
    ana = await world.person({ gender: 'woman', showMe: ['man'], firstName: 'Ana' });
    ben = await world.person({ gender: 'man', showMe: ['woman'], firstName: 'Ben' });
    cal = await world.person({ gender: 'man', showMe: ['woman'], firstName: 'Cal' });
    dev = await world.person({ gender: 'man', showMe: ['woman'], firstName: 'Dev' });
    for (const p of [ana, ben, cal, dev]) card.set(p.id, await world.checkIn(p, room));
    for (const p of [ana, ben, cal, dev]) await world.wholeDeck(p, room);
  });
  beforeEach(() => useRealSupabase(IT!));
  afterAll(() => world?.cleanup());

  it('before a match, nobody has a match or anyone’s name, even after a one-sided tap', async () => {
    expect((await tap(ana, cal)).result).toBe('sent');
    expect(await list(ana)).toEqual({ matches: [] });
    expect(await list(cal)).toEqual({ matches: [] });
  });

  it('after a mutual tap, each sees the other’s first name and nothing else about them', async () => {
    expect((await tap(ana, ben)).result).toBe('sent');
    const mutual = await tap(ben, ana);
    expect(mutual.result).toBe('mutual');

    const forAna = await list(ana);
    const forBen = await list(ben);
    expect(forAna.matches).toHaveLength(1);
    const m = forAna.matches[0]!;
    expect(m).toMatchObject({
      id: mutual.matchId,
      status: 'choosing',
      firstName: 'Ben',
      roomName: expect.any(String),
    });
    expect(Object.keys(m).sort()).toEqual([
      'choiceDeadline',
      'createdAt',
      'firstName',
      'id',
      'roomName',
      'status',
    ]);
    expect(Date.parse(m.choiceDeadline) - Date.parse(m.createdAt)).toBe(
      CHOICE_WINDOW_SECONDS * 1000,
    );
    expect(forBen.matches).toEqual([{ ...m, firstName: 'Ana' }]);
    // Cal (tapped by Ana, one-sided) and Dev (no taps) still see nothing.
    expect(await list(cal)).toEqual({ matches: [] });
    expect(await list(dev)).toEqual({ matches: [] });
  });

  it('newest first, and a choice window that ran out shows as chatting', async () => {
    expect((await tap(dev, ana)).result).toBe('sent');
    const second = await tap(ana, dev);
    expect(second.result).toBe('mutual');
    const [first] = (await list(ben)).matches;
    // Run Ana and Ben's choice window out.
    await world.update(
      'matches',
      {
        created_at: new Date(Date.now() - 2 * CHOICE_WINDOW_SECONDS * 1000).toISOString(),
        choice_deadline: new Date(Date.now() - CHOICE_WINDOW_SECONDS * 1000).toISOString(),
      },
      { id: first!.id },
    );
    vi.mocked(notifySettled).mockClear();
    const forAna = await list(ana);
    expect(forAna.matches.map((x) => [x.id, x.status, x.firstName])).toEqual([
      [second.matchId, 'choosing', 'Dev'],
      [first!.id, 'chatting', 'Ben'],
    ]);
    // The timeout list_matches applied goes to notifySettled, for both people (A2's settled).
    expect(notifySettled).toHaveBeenCalledTimes(1);
    const [settled] = vi.mocked(notifySettled).mock.calls[0]! as [
      Array<{ matchId: string; kind: string; userIds: string[] }>,
    ];
    expect(settled).toHaveLength(1);
    expect(settled[0]!.matchId).toBe(first!.id);
    expect(settled[0]!.kind).toBe('choice_timeout');
    expect([...settled[0]!.userIds].sort()).toEqual([ana.id, ben.id].sort());
    // Applied once: the next list sends nothing.
    await list(ben);
    expect(notifySettled).toHaveBeenCalledTimes(1);
  });

  it('an ended match (unmatch or block) disappears for both', async () => {
    const [devMatch] = (await list(dev)).matches;
    await world.update(
      'matches',
      { status: 'ended', ended_at: new Date().toISOString() },
      { id: devMatch!.id },
    );
    expect((await list(dev)).matches).toEqual([]);
    expect((await list(ana)).matches.map((x) => x.firstName)).toEqual(['Ben']);
  });
});
