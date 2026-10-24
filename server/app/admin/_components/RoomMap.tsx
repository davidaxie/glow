'use client';
// Owner: B7. The room's center and radius on a map: MapLibre GL with OpenStreetMap's raster
// tiles, and OpenStreetMap's attribution always shown in full, as its licence requires.
// Drag the pin or tap the map to move the center.
import 'maplibre-gl/dist/maplibre-gl.css';
import { useEffect, useRef } from 'react';
import type { GeoJSONSource, Map as MapLibreMap, Marker } from 'maplibre-gl';

export type LatLng = { readonly latitude: number; readonly longitude: number };

type PolygonFeature = {
  type: 'Feature';
  properties: Record<string, never>;
  geometry: { type: 'Polygon'; coordinates: [number, number][][] };
};

const EARTH_RADIUS_M = 6_371_008.8;
const ACCENT = '#FF4FA3';

/** A circle of `radiusM` around `center`, as a 64-sided polygon. */
export function circlePolygon(center: LatLng, radiusM: number): PolygonFeature {
  const lat1 = (center.latitude * Math.PI) / 180;
  const lng1 = (center.longitude * Math.PI) / 180;
  const d = radiusM / EARTH_RADIUS_M;
  const ring: [number, number][] = [];
  for (let i = 0; i <= 64; i++) {
    const bearing = (i / 64) * 2 * Math.PI;
    const lat2 = Math.asin(
      Math.sin(lat1) * Math.cos(d) + Math.cos(lat1) * Math.sin(d) * Math.cos(bearing),
    );
    const lng2 =
      lng1 +
      Math.atan2(
        Math.sin(bearing) * Math.sin(d) * Math.cos(lat1),
        Math.cos(d) - Math.sin(lat1) * Math.sin(lat2),
      );
    ring.push([(lng2 * 180) / Math.PI, (lat2 * 180) / Math.PI]);
  }
  return { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [ring] } };
}

const OSM_STYLE = {
  version: 8 as const,
  sources: {
    osm: {
      type: 'raster' as const,
      tiles: ['https://tile.openstreetmap.org/{z}/{x}/{y}.png'],
      tileSize: 256,
      maxzoom: 19,
      attribution:
        '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors',
    },
  },
  layers: [{ id: 'osm', type: 'raster' as const, source: 'osm' }],
};

type Props = {
  readonly center: LatLng | null;
  readonly radiusM: number;
  readonly onCenterChange: (center: LatLng) => void;
  /** Bump to fly to the current center and radius (after "Use my location"). */
  readonly focusKey: number;
};

export function RoomMap({ center, radiusM, onCenterChange, focusKey }: Props) {
  const holder = useRef<HTMLDivElement>(null);
  const map = useRef<MapLibreMap | null>(null);
  const marker = useRef<Marker | null>(null);
  const latest = useRef({ center, radiusM, onCenterChange });
  latest.current = { center, radiusM, onCenterChange };

  // Create the map once.
  useEffect(() => {
    let cancelled = false;
    let created: MapLibreMap | null = null;
    void import('maplibre-gl').then((maplibre) => {
      if (cancelled || !holder.current) return;
      const start = latest.current.center;
      created = new maplibre.Map({
        container: holder.current,
        style: OSM_STYLE,
        center: start ? [start.longitude, start.latitude] : [-98.5, 39.8],
        zoom: start ? 16 : 2.5,
        attributionControl: { compact: false },
        cooperativeGestures: false,
      });
      created.addControl(new maplibre.NavigationControl({ showCompass: false }), 'top-right');
      created.on('load', () => {
        if (!created) return;
        created.addSource('room', {
          type: 'geojson',
          data: { type: 'FeatureCollection', features: [] },
        });
        created.addLayer({
          id: 'room-fill',
          type: 'fill',
          source: 'room',
          paint: { 'fill-color': ACCENT, 'fill-opacity': 0.18 },
        });
        created.addLayer({
          id: 'room-line',
          type: 'line',
          source: 'room',
          paint: { 'line-color': ACCENT, 'line-width': 2 },
        });
        draw();
      });
      created.on('click', (e) => {
        latest.current.onCenterChange({ latitude: e.lngLat.lat, longitude: e.lngLat.lng });
      });
      const pin = new maplibre.Marker({ color: ACCENT, draggable: true });
      pin.on('dragend', () => {
        const at = pin.getLngLat();
        latest.current.onCenterChange({ latitude: at.lat, longitude: at.lng });
      });
      marker.current = pin;
      map.current = created;
    });
    return () => {
      cancelled = true;
      created?.remove();
      map.current = null;
      marker.current = null;
    };
  }, []);

  function draw() {
    const m = map.current;
    const { center: c, radiusM: r } = latest.current;
    if (!m || !m.isStyleLoaded()) return;
    const source = m.getSource('room') as GeoJSONSource | undefined;
    source?.setData(
      c
        ? { type: 'FeatureCollection', features: [circlePolygon(c, r)] }
        : { type: 'FeatureCollection', features: [] },
    );
    if (c && marker.current) marker.current.setLngLat([c.longitude, c.latitude]).addTo(m);
  }

  // Redraw whenever the center or radius changes.
  useEffect(() => {
    draw();
  }, [center?.latitude, center?.longitude, radiusM]);

  // Fly to the circle when asked.
  useEffect(() => {
    const m = map.current;
    if (!m || !center || focusKey === 0) return;
    const ring = circlePolygon(center, radiusM).geometry.coordinates[0]!;
    const lngs = ring.map((p) => p[0]!);
    const lats = ring.map((p) => p[1]!);
    m.fitBounds(
      [
        [Math.min(...lngs), Math.min(...lats)],
        [Math.max(...lngs), Math.max(...lats)],
      ],
      { padding: 32, maxZoom: 18, duration: 600 },
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps -- only when asked
  }, [focusKey]);

  return (
    <div
      ref={holder}
      className="ga-map"
      role="application"
      aria-label="Map of the room. Tap the map or drag the pin to move the room's center."
    />
  );
}
