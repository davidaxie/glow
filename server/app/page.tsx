export default function Home() {
  return (
    <main
      style={{
        display: 'grid',
        placeItems: 'center',
        minHeight: '100vh',
        padding: 24,
        textAlign: 'center',
      }}
    >
      <div>
        <h1 style={{ fontSize: 40, margin: 0, color: '#FF4FA3' }}>Glow</h1>
        <p style={{ color: '#A1A1AA', marginTop: 12 }}>
          Find out, privately, that you noticed each other.
        </p>
      </div>
    </main>
  );
}
