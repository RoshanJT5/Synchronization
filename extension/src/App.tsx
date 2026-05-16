function App() {
  return (
    <div
      style={{
        width: '320px',
        padding: '24px',
        background: '#030303',
        color: '#f8fafc',
        fontFamily: 'Inter, sans-serif',
      }}
    >
      <h2 style={{ color: '#a855f7', margin: 0 }}>Synchronization</h2>
      <p style={{ color: '#94a3b8', fontSize: '13px', margin: '8px 0 0' }}>
        Multi-device audio sync
      </p>
      <div
        style={{
          background: '#0f0f12',
          border: '1px solid rgba(255,255,255,0.08)',
          borderRadius: '8px',
          padding: '16px',
          marginTop: '16px',
        }}
      >
        <p
          style={{
            color: '#94a3b8',
            fontSize: '13px',
            textAlign: 'center',
            margin: 0,
            lineHeight: 1.5,
          }}
        >
          Open the Synchronization app on your phone to host or join a session.
        </p>
      </div>
      <a
        href="https://synchronization-807q.onrender.com"
        target="_blank"
        rel="noreferrer"
        style={{
          display: 'block',
          marginTop: '16px',
          padding: '10px',
          background: '#a855f7',
          borderRadius: '8px',
          color: 'white',
          textAlign: 'center',
          textDecoration: 'none',
          fontSize: '13px',
          fontWeight: 700,
        }}
      >
        Download App
      </a>
    </div>
  );
}

export default App;
