import { useEffect, useRef, useState } from 'react';
import QRCode from 'qrcode';

const CONNECT_PAGE_URL = 'https://synchronization-807q.onrender.com/c';

type Status = 'IDLE' | 'READY' | 'CONNECTING' | 'STREAMING' | 'ERROR';

function App() {
  const [sessionId, setSessionId] = useState('');
  const [status, setStatus] = useState<Status>('IDLE');
  const [readyPeers, setReadyPeers] = useState(0);
  const [error, setError] = useState('');
  const [sourceMuted, setSourceMuted] = useState(false);
  const [showQR, setShowQR] = useState(true);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    chrome.runtime.sendMessage({ type: 'GET_STATE' }, (response) => {
      const id = response?.sessionId || createSessionId();
      setSessionId(id);
      setStatus((response?.status || 'READY') as Status);
      setReadyPeers(response?.readyPeers || 0);
      setError(response?.error || '');
      setSourceMuted(Boolean(response?.sourceMuted));
      generateQR(id);
      if (!response?.sessionId || response?.status === 'IDLE') {
        chrome.runtime.sendMessage({
          type: 'PREPARE_EXTENSION_SESSION',
          sessionId: id,
        });
      }
    });
  }, []);

  useEffect(() => {
    if (sessionId && showQR) generateQR(sessionId);
  }, [sessionId, showQR]);

  useEffect(() => {
    const listener = (message: any) => {
      if (message.type !== 'STATE_UPDATED' || !message.state) return;
      setStatus(message.state.status);
      setReadyPeers(message.state.readyPeers || 0);
      setError(message.state.error || '');
      setSourceMuted(Boolean(message.state.sourceMuted));
      if (message.state.sessionId) setSessionId(message.state.sessionId);
    };
    chrome.runtime.onMessage.addListener(listener);
    return () => chrome.runtime.onMessage.removeListener(listener);
  }, []);

  const createSessionId = () => {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const bytes = new Uint8Array(6);
    crypto.getRandomValues(bytes);
    return Array.from(bytes, (byte) => chars[byte % chars.length]).join('');
  };

  const generateQR = (id: string) => {
    const url = `${CONNECT_PAGE_URL}/${encodeURIComponent(id)}`;
    setTimeout(() => {
      if (!canvasRef.current) return;
      QRCode.toCanvas(canvasRef.current, url, {
        width: 208,
        margin: 4,
        color: { dark: '#050505', light: '#ffffff' },
        errorCorrectionLevel: 'H',
      });
    }, 50);
  };

  const resetSession = () => {
    chrome.runtime.sendMessage({ type: 'STOP_EXTENSION_HOST' });
    const id = createSessionId();
    setSessionId(id);
    setStatus('READY');
    setReadyPeers(0);
    setError('');
    setShowQR(true);
    chrome.runtime.sendMessage({
      type: 'PREPARE_EXTENSION_SESSION',
      sessionId: id,
    });
  };

  const startStreaming = () => {
    setStatus('CONNECTING');
    chrome.tabCapture.getMediaStreamId({ targetTabId: undefined }, (streamId) => {
      if (!streamId) {
        setStatus('ERROR');
        setError('Could not capture this tab. Open a tab with audio and try again.');
        return;
      }
      chrome.runtime.sendMessage({
        type: 'START_EXTENSION_HOST',
        sessionId,
        streamId,
      });
    });
  };

  const toggleSourceMute = () => {
    const next = !sourceMuted;
    setSourceMuted(next);
    chrome.runtime.sendMessage({ type: 'SET_SOURCE_MUTE', muted: next });
  };

  const isStreaming = status === 'STREAMING';
  const isConnecting = status === 'CONNECTING';
  const statusLabel = isStreaming
    ? 'Live Stream'
    : isConnecting
      ? 'Starting...'
      : 'Ready to Stream';

  return (
    <div className="w-[320px] min-h-[520px] bg-[#0a0a0c] text-white p-6 font-sans box-border flex flex-col">
      <div className="flex items-center gap-3 mb-5">
        <img
          src="/app_icon.jpg"
          alt=""
          className="w-10 h-10 rounded-xl object-cover border border-white/10"
        />
        <div>
          <h1 className="m-0 text-lg font-black tracking-tight">Synchronization</h1>
          <p className="m-0 text-[11px] text-slate-500 font-bold uppercase tracking-[0.18em]">
            WebRTC 2.0
          </p>
        </div>
      </div>

      <div className="flex-1 flex flex-col items-center">
        {!isStreaming && showQR && (
          <div className="w-full flex flex-col items-center">
            <div className="bg-white p-3 rounded-2xl border border-white/10 mb-4 shadow-xl shadow-purple-500/10">
              <canvas ref={canvasRef} />
            </div>
            <p className="text-slate-400 text-xs text-center mb-4">
              Scan with the mobile app or enter ID
              <br />
              <span className="text-purple-400 font-mono text-lg font-black tracking-[0.2em]">
                {sessionId}
              </span>
            </p>
          </div>
        )}

        {(isStreaming || !showQR) && (
          <div className="w-full flex flex-col items-center">
            <div className="relative mb-5">
              <div className="absolute inset-0 blur-3xl rounded-full bg-purple-500/20" />
              <div className="relative w-16 h-16 rounded-full bg-purple-500/10 border border-purple-500/30 flex items-center justify-center">
                <span className="text-3xl">{isStreaming ? '✓' : '♪'}</span>
              </div>
            </div>
            <h2 className="text-xl font-black mb-1">{statusLabel}</h2>
            <p className="text-slate-500 text-xs mb-5 uppercase tracking-widest font-bold">
              {isStreaming ? 'Broadcasting browser audio' : 'Waiting for phones'}
            </p>
          </div>
        )}

        <div className="w-full bg-[#16161a] border border-purple-500/20 rounded-xl px-3 py-3 mb-4 text-center">
          <p className="text-purple-400 text-[10px] font-mono font-bold">
            Cloud Relay Active
          </p>
          <p className="text-slate-400 text-xs m-0">
            {readyPeers} device{readyPeers === 1 ? '' : 's'} connected
          </p>
        </div>

        {readyPeers > 0 && !isStreaming && (
          <div className="w-full bg-green-500/10 border border-green-500/30 rounded-xl px-3 py-3 mb-4 text-center">
            <p className="text-green-400 text-sm font-bold m-0">
              {readyPeers} phone{readyPeers === 1 ? '' : 's'} ready
            </p>
          </div>
        )}

        {isStreaming && (
          <button
            onClick={toggleSourceMute}
            className={`w-full flex items-center justify-between px-4 py-3 rounded-xl border mb-4 transition-all ${
              sourceMuted
                ? 'bg-red-500/10 border-red-500/30 text-red-400'
                : 'bg-green-500/10 border-green-500/30 text-green-400'
            }`}
          >
            <span className="flex items-center gap-2 text-sm font-semibold">
              <span>{sourceMuted ? '🔇' : '🔊'}</span>
              {sourceMuted ? 'Source muted' : 'Source playing'}
            </span>
            <span
              className={`text-[10px] font-bold uppercase tracking-widest px-2 py-1 rounded-lg ${
                sourceMuted ? 'bg-red-500/20 text-red-400' : 'bg-green-500/20 text-green-400'
              }`}
            >
              {sourceMuted ? 'Unmute' : 'Mute'}
            </span>
          </button>
        )}

        {error && (
          <div className="w-full bg-red-500/10 border border-red-500/30 rounded-xl p-3 mb-4 text-xs text-red-300">
            {error}
          </div>
        )}

        <button
          onClick={isStreaming ? resetSession : startStreaming}
          disabled={isConnecting}
          className="w-full py-3 bg-white text-black font-black rounded-xl hover:scale-[1.02] active:scale-[0.98] transition-all disabled:opacity-50"
        >
          {isConnecting ? 'Starting...' : isStreaming ? 'Stop Streaming' : 'Start Streaming'}
        </button>

        {isStreaming && (
          <button
            onClick={() => {
              setShowQR(!showQR);
              if (!showQR) generateQR(sessionId);
            }}
            className="mt-4 text-xs text-purple-400 hover:text-purple-300 font-bold uppercase tracking-wider transition-colors"
          >
            {showQR ? 'Hide QR Code' : '+ Add Another Device'}
          </button>
        )}

        {isStreaming && showQR && (
          <div className="bg-white p-3 rounded-2xl border border-white/10 mt-3">
            <canvas ref={canvasRef} />
          </div>
        )}
      </div>

      <div className="mt-5 pt-4 border-t border-white/5 flex items-center justify-between text-[10px] text-slate-600 font-bold uppercase tracking-widest">
        <span>Browser Audio</span>
        <span className="flex items-center gap-1.5">
          <span className={`w-1.5 h-1.5 rounded-full ${isStreaming ? 'bg-green-500' : 'bg-purple-500'}`} />
          {isStreaming ? 'Live' : 'Ready'}
        </span>
      </div>
    </div>
  );
}

export default App;
