'use client';
// Owner: B7. Making a room at the venue, from a phone, in under two minutes: a name, one tap
// for the center, a radius, three meeting spots (already filled in), and times that default
// to now and twelve hours from now. Also edits an existing room's details.
import { useRouter } from 'next/navigation';
import { useMemo, useState, useTransition } from 'react';
import type { AdminRoom } from '@/contracts';
import {
  MEETING_SPOTS_MAX,
  MEETING_SPOTS_MIN,
  ROOM_RADIUS_DEFAULT_METERS,
} from '@/contracts/constants';
import { createRoomAction, updateRoomAction } from '../actions';
import { RoomMap, type LatLng } from './RoomMap';

const DEFAULT_SPOTS = ['Main entrance', 'Info desk', 'Water station'];
const SLUG = /^[a-z0-9](?:[a-z0-9-]{0,38}[a-z0-9])?$/;

/** "Cal Hacks 13: Main Hall" → "cal-hacks-13-main-hall" */
export function slugify(name: string): string {
  return name
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 40)
    .replace(/-+$/g, '');
}

/** An ISO time as the value of a datetime-local input, in this browser's timezone. */
function toLocalInput(iso: string): string {
  const d = new Date(iso);
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function fromLocalInput(value: string): string | null {
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? new Date(ms).toISOString() : null;
}

function defaultTimes(): { starts: string; ends: string } {
  const start = new Date();
  start.setSeconds(0, 0);
  start.setMinutes(start.getMinutes() - (start.getMinutes() % 5));
  const end = new Date(start.getTime() + 12 * 3600 * 1000);
  return { starts: toLocalInput(start.toISOString()), ends: toLocalInput(end.toISOString()) };
}

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Los_Angeles';
  } catch {
    return 'America/Los_Angeles';
  }
}

type Props = { readonly room?: AdminRoom };

export function RoomForm({ room }: Props) {
  const router = useRouter();
  const editing = room !== undefined;
  const times = useMemo(() => defaultTimes(), []);
  const timezones = useMemo(() => {
    try {
      return Intl.supportedValuesOf('timeZone');
    } catch {
      return [browserTimezone()];
    }
  }, []);

  const [name, setName] = useState(room?.name ?? '');
  const [slug, setSlug] = useState(room?.slug ?? '');
  const [slugEdited, setSlugEdited] = useState(editing);
  const [center, setCenter] = useState<LatLng | null>(
    room ? { latitude: room.latitude, longitude: room.longitude } : null,
  );
  const [radiusM, setRadiusM] = useState(room?.radiusM ?? ROOM_RADIUS_DEFAULT_METERS);
  const [focusKey, setFocusKey] = useState(room ? 1 : 0);
  const [spots, setSpots] = useState<string[]>(room ? [] : DEFAULT_SPOTS);
  const [startsAt, setStartsAt] = useState(room ? toLocalInput(room.startsAt) : times.starts);
  const [endsAt, setEndsAt] = useState(room ? toLocalInput(room.endsAt) : times.ends);
  const [timezone, setTimezone] = useState(room?.timezone ?? browserTimezone());
  const [allowStaticQr, setAllowStaticQr] = useState(false);
  const [demoMode, setDemoMode] = useState(false);
  const [locating, setLocating] = useState(false);
  const [locationNote, setLocationNote] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [pending, startTransition] = useTransition();

  const effectiveSlug = slugEdited ? slug : slugify(name);
  const slugValid = SLUG.test(effectiveSlug);

  function locateMe() {
    if (!('geolocation' in navigator)) {
      setLocationNote("This browser can't share its location. Tap the map instead.");
      return;
    }
    setLocating(true);
    setLocationNote(null);
    // Used once, to put the room's center where you're standing. Never stored as yours.
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLocating(false);
        setCenter({ latitude: position.coords.latitude, longitude: position.coords.longitude });
        setFocusKey((k) => k + 1);
        const accuracy = Math.round(position.coords.accuracy);
        setLocationNote(
          accuracy > radiusM
            ? `Your location is rough (within ${accuracy} m). Drag the pin onto the venue.`
            : `Centered on you, within about ${accuracy} m.`,
        );
      },
      (failure) => {
        setLocating(false);
        setLocationNote(
          failure.code === failure.PERMISSION_DENIED
            ? 'Location is off for this site. Tap the map to place the center instead.'
            : "Couldn't get a location fix. Tap the map to place the center instead.",
        );
      },
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 0 },
    );
  }

  function submit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);
    setSaved(false);
    const starts = fromLocalInput(startsAt);
    const ends = fromLocalInput(endsAt);
    if (!name.trim()) return setError('Give the room a name.');
    if (!editing && !slugValid) return setError('The link name can use a to z, 0 to 9 and dashes.');
    if (!center) return setError('Set the center: tap "Use my location" or tap the map.');
    if (!starts || !ends) return setError('Check the start and end times.');
    if (Date.parse(ends) <= Date.parse(starts))
      return setError('The room must end after it starts.');
    const cleanSpots = spots.map((s) => s.trim()).filter(Boolean);
    if (
      !editing &&
      (cleanSpots.length < MEETING_SPOTS_MIN || cleanSpots.length > MEETING_SPOTS_MAX)
    ) {
      return setError(`Add ${MEETING_SPOTS_MIN} to ${MEETING_SPOTS_MAX} meeting spots.`);
    }

    startTransition(async () => {
      if (editing) {
        const result = await updateRoomAction(room.id, {
          name: name.trim(),
          latitude: center.latitude,
          longitude: center.longitude,
          radiusM,
          timezone,
          startsAt: starts,
          endsAt: ends,
        });
        if (!result.ok) return setError(result.message);
        setSaved(true);
        router.refresh();
        return;
      }
      const result = await createRoomAction({
        slug: effectiveSlug,
        name: name.trim(),
        latitude: center.latitude,
        longitude: center.longitude,
        radiusM,
        timezone,
        allowStaticQr,
        demoMode,
        startsAt: starts,
        endsAt: ends,
        spots: cleanSpots,
      });
      if (!result.ok) return setError(result.message);
      router.push(`/admin/rooms/${result.value.id}`);
    });
  }

  return (
    <form onSubmit={submit} className="ga-stack" noValidate>
      <div className="ga-field">
        <label className="ga-label" htmlFor="room-name">
          Room name
        </label>
        <input
          id="room-name"
          className="ga-input"
          value={name}
          maxLength={80}
          onChange={(e) => setName(e.target.value)}
          placeholder="Cal Hacks main hall"
          autoFocus={!editing}
          required
        />
        <span className="ga-hint">People see this when they scan in.</span>
      </div>

      {!editing ? (
        <div className="ga-field">
          <label className="ga-label" htmlFor="room-slug">
            Link name
          </label>
          <input
            id="room-slug"
            className="ga-input"
            value={effectiveSlug}
            maxLength={40}
            autoCapitalize="none"
            spellCheck={false}
            onChange={(e) => {
              setSlugEdited(true);
              setSlug(e.target.value.toLowerCase());
            }}
            aria-invalid={effectiveSlug && !slugValid ? true : undefined}
            aria-describedby="room-slug-hint"
          />
          <span id="room-slug-hint" className="ga-hint">
            In the room’s link: …/r/{effectiveSlug || 'name'}. Letters, numbers and dashes.
          </span>
        </div>
      ) : null}

      <fieldset className="ga-card ga-stack" style={{ margin: 0 }}>
        <legend className="ga-label" style={{ padding: '0 4px' }}>
          Where
        </legend>
        <button
          type="button"
          className="ga-button ga-button--secondary ga-button--block"
          onClick={locateMe}
          disabled={locating}
        >
          {locating ? 'Finding you…' : 'Set center to my location'}
        </button>
        {locationNote ? (
          <p className="ga-small ga-muted" role="status" style={{ margin: 0 }}>
            {locationNote}
          </p>
        ) : null}
        <RoomMap center={center} radiusM={radiusM} onCenterChange={setCenter} focusKey={focusKey} />
        <div className="ga-field">
          <label className="ga-label" htmlFor="room-radius">
            Radius: {radiusM} m
          </label>
          <input
            id="room-radius"
            type="range"
            className="ga-range"
            min={25}
            max={1000}
            step={5}
            value={radiusM}
            onChange={(e) => setRadiusM(Number(e.target.value))}
            aria-valuetext={`${radiusM} meters`}
          />
          <span className="ga-hint">
            Anyone inside the circle can join. Big enough for the whole venue, no bigger.
          </span>
        </div>
        {center ? (
          <p className="ga-hint" style={{ margin: 0 }}>
            Center {center.latitude.toFixed(5)}, {center.longitude.toFixed(5)}
          </p>
        ) : null}
      </fieldset>

      {!editing ? (
        <fieldset className="ga-card ga-stack" style={{ margin: 0 }}>
          <legend className="ga-label" style={{ padding: '0 4px' }}>
            Meeting spots
          </legend>
          <p className="ga-hint" style={{ margin: 0 }}>
            Where two people who both chose Find go to meet. Easy to spot, easy to say.
          </p>
          {spots.map((spot, i) => (
            <div key={i} className="ga-row">
              <label className="ga-visually-hidden" htmlFor={`spot-${i}`}>
                Meeting spot {i + 1}
              </label>
              <input
                id={`spot-${i}`}
                className="ga-input"
                style={{ flex: 1 }}
                value={spot}
                maxLength={60}
                onChange={(e) => setSpots(spots.map((s, j) => (j === i ? e.target.value : s)))}
              />
              {spots.length > MEETING_SPOTS_MIN ? (
                <button
                  type="button"
                  className="ga-button ga-button--secondary ga-button--small"
                  onClick={() => setSpots(spots.filter((_, j) => j !== i))}
                  aria-label={`Remove meeting spot ${i + 1}`}
                >
                  Remove
                </button>
              ) : null}
            </div>
          ))}
          {spots.length < MEETING_SPOTS_MAX ? (
            <button
              type="button"
              className="ga-button ga-button--secondary ga-button--small"
              onClick={() => setSpots([...spots, ''])}
            >
              Add a spot
            </button>
          ) : null}
        </fieldset>
      ) : null}

      <fieldset className="ga-card ga-stack" style={{ margin: 0 }}>
        <legend className="ga-label" style={{ padding: '0 4px' }}>
          When
        </legend>
        <div className="ga-field">
          <label className="ga-label" htmlFor="room-starts">
            Starts
          </label>
          <input
            id="room-starts"
            type="datetime-local"
            className="ga-input"
            value={startsAt}
            onChange={(e) => setStartsAt(e.target.value)}
          />
        </div>
        <div className="ga-field">
          <label className="ga-label" htmlFor="room-ends">
            Ends
          </label>
          <input
            id="room-ends"
            type="datetime-local"
            className="ga-input"
            value={endsAt}
            onChange={(e) => setEndsAt(e.target.value)}
          />
          <span className="ga-hint">
            Times are in this phone’s time zone. Every card in the room ends when the room does.
          </span>
        </div>
        <div className="ga-field">
          <label className="ga-label" htmlFor="room-tz">
            Room’s time zone
          </label>
          <select
            id="room-tz"
            className="ga-select"
            value={timezone}
            onChange={(e) => setTimezone(e.target.value)}
          >
            {(timezones.includes(timezone) ? timezones : [timezone, ...timezones]).map((tz) => (
              <option key={tz} value={tz}>
                {tz}
              </option>
            ))}
          </select>
          <span className="ga-hint">Daily tap limits reset at midnight here.</span>
        </div>
      </fieldset>

      {!editing ? (
        <fieldset className="ga-card ga-stack" style={{ margin: 0 }}>
          <legend className="ga-label" style={{ padding: '0 4px' }}>
            Options
          </legend>
          <label className="ga-switch">
            <input
              type="checkbox"
              checked={allowStaticQr}
              onChange={(e) => setAllowStaticQr(e.target.checked)}
            />
            <span>
              <strong>Printed posters</strong>
              <br />
              <span className="ga-hint">
                A poster’s code never changes, so a photo of it works anywhere. People still have to
                be inside the room to join. Screens with a changing code work either way.
              </span>
            </span>
          </label>
          <label className="ga-switch">
            <input
              type="checkbox"
              checked={demoMode}
              onChange={(e) => setDemoMode(e.target.checked)}
            />
            <span>
              <strong>Demo mode</strong>
              <br />
              <span className="ga-hint">
                Admins skip the location check here, so stage phones work wherever the stage is.
                Every skip is logged. Everyone else is still checked.
              </span>
            </span>
          </label>
        </fieldset>
      ) : null}

      {error ? (
        <p className="ga-message ga-message--error" role="alert">
          {error}
        </p>
      ) : null}
      {saved ? (
        <p className="ga-message ga-message--ok" role="status">
          Saved.
        </p>
      ) : null}
      <button className="ga-button ga-button--block" disabled={pending}>
        {pending ? 'Saving…' : editing ? 'Save details' : 'Create room'}
      </button>
    </form>
  );
}
