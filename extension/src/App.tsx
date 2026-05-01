import React, { useState, useEffect, useRef } from 'react';
import QRCode from 'qrcode';
import { Smartphone, Laptop, Speaker, Loader2, CheckCircle2, AlertCircle, Radio, Download, Send, Volume2, VolumeX } from 'lucide-react';

const SIGNALING_SERVER = 'https://syncronization.vercel.app';
const CONNECT_PAGE_URL = 'https://syncronization.vercel.app/';

type Mode = 'SEND' | 'RECEIVE';
type Status = 'IDLE' | 'CONNECTING' | 'CAPTURING' | 'LISTENING' | 'ERROR';

function App() {
  const [mode, setMode] = useState<Mode>('SEND');
  const [sessionId, setSessionId] = useState('');
  const [remoteSessionId, setRemoteSessionId] = useState('');
  const [mobileServerUrl, setMobileServerUrl] = useState('https://syncronization.vercel.app');
  const [status, setStatus] = useState<Status>('IDLE');
  const [error, setError] = useState('');
  // true = laptop speakers are silent, false = laptop keeps playing alongside remotes
  const [sourceMuted, setSourceMuted] = useState(false);
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    if (mode === 'SEND') {
      const newSessionId = Math.random().toString(36).substring(2, 10).toUpperCase();
      setSessionId(newSessionId);
      generateQR(newSessionId, mobileServerUrl);
    }
  }, [mode]);

  useEffect(() => {
    if (mode === 'SEND' && sessionId) {
      generateQR(sessionId, mobileServerUrl);
    }
  }, [mobileServerUrl, mode, sessionId]);

  const generateQR = (id: string, serverUrl: string) => {
    const params = new URLSearchParams({ id });
    if (serverUrl.trim()) {
      params.set('server', serverUrl.trim());
    }
    const connectionUrl = `${CONNECT_PAGE_URL}?${params.toString()}`;
    setTimeout(() => {
      if (canvasRef.current) {
        QRCode.toCanvas(canvasRef.current, connectionUrl, {
          width: 160,
          margin: 2,
          color: { dark: '#ffffff', light: '#00000000' }
        });
      }
    }, 100);
  };

  const handleStartSend = async () => {
    setStatus('CONNECTING');
    try {
      chrome.tabCapture.getMediaStreamId({ targetTabId: undefined }, (streamId) => {
        if (!streamId) {
          setError('Could not get tab stream ID');
          setStatus('ERROR');
          return;
        }
        chrome.runtime.sendMessage({
          type: 'START_CAPTURE',
          sessionId: sessionId,
          streamId: streamId
        });
        setStatus('CAPTURING');
      });
    } catch (err: any) {
      setError(err.message || 'Failed to start capture');
      setStatus('ERROR');
    }
  };

  const handleStartReceive = () => {
    if (!remoteSessionId) return;
    setStatus('CONNECTING');
    chrome.runtime.sendMessage({
      type: 'START_RECEIVE',
      sessionId: remoteSessionId.toUpperCase()
    });
    // We'll update status to LISTENING when connection is confirmed via message from background
  };

  const handleToggleSourceMute = () => {
    const next = !sourceMuted;
    setSourceMuted(next);
    chrome.runtime.sendMessage({ type: 'SET_SOURCE_MUTE', muted: next });
  };

  // Listen for status updates from background/offscreen
  useEffect(() => {
    const listener = (message: any) => {
      if (message.type === 'CONNECTION_SUCCESS') {
        setStatus(mode === 'SEND' ? 'CAPTURING' : 'LISTENING');
      } else if (message.type === 'CONNECTION_ERROR') {
        setError(message.error);
        setStatus('ERROR');
      }
    };
    chrome.runtime.onMessage.addListener(listener);
    return () => chrome.runtime.onMessage.removeListener(listener);
  }, [mode]);

  return (
    <div className="min-h-[420px] w-[320px] bg-[#0a0a0c] text-white p-6 font-sans flex flex-col">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <div className="p-2 bg-gradient-to-br from-purple-500 to-blue-500 rounded-xl">
          <Speaker size={20} className="text-white" />
        </div>
        <h1 className="text-lg font-bold bg-clip-text text-transparent bg-gradient-to-r from-white to-gray-400">
          Syncronization
        </h1>
      </div>

      {/* Mode Switcher */}
      {status === 'IDLE' && (
        <div className="flex bg-[#16161a] p-1 rounded-xl mb-6 border border-white/5">
          <button
            onClick={() => setMode('SEND')}
            className={`flex-1 py-2 rounded-lg text-sm font-medium transition-all flex items-center justify-center gap-2 ${
              mode === 'SEND' ? 'bg-white text-black shadow-lg' : 'text-gray-400 hover:text-white'
            }`}
          >
            <Send size={14} /> Send
          </button>
          <button
            onClick={() => setMode('RECEIVE')}
            className={`flex-1 py-2 rounded-lg text-sm font-medium transition-all flex items-center justify-center gap-2 ${
              mode === 'RECEIVE' ? 'bg-white text-black shadow-lg' : 'text-gray-400 hover:text-white'
            }`}
          >
            <Download size={14} /> Receive
          </button>
        </div>
      )}

      {/* Main Area */}
      <div className="flex-1 flex flex-col items-center justify-center">
        {status === 'IDLE' && mode === 'SEND' && (
          <div className="flex flex-col items-center w-full">
            <div className="bg-[#16161a] p-3 rounded-2xl border border-white/5 mb-4">
              <canvas ref={canvasRef} />
            </div>
            <p className="text-gray-400 text-xs text-center mb-6">
              Scan with mobile or use ID: <br />
              <span className="text-purple-400 font-mono font-bold">{sessionId}</span>
            </p>
            <div className="w-full bg-[#16161a] border border-purple-500/20 rounded-xl px-3 py-2 mb-4 text-center">
              <p className="text-purple-400 text-[10px] font-mono">
                ✓ Connected to Vercel Cloud Relay
              </p>
            </div>
            <button
              onClick={handleStartSend}
              className="w-full py-3 bg-white text-black font-bold rounded-xl hover:scale-[1.02] active:scale-[0.98] transition-all"
            >
              Start Streaming
            </button>
          </div>
        )}

        {status === 'IDLE' && mode === 'RECEIVE' && (
          <div className="flex flex-col items-center w-full">
            <div className="w-16 h-16 bg-purple-500/10 rounded-full flex items-center justify-center mb-6 border border-purple-500/20">
              <Radio className="text-purple-500 animate-pulse" />
            </div>
            <input
              type="text"
              placeholder="Enter Session ID"
              value={remoteSessionId}
              onChange={(e) => setRemoteSessionId(e.target.value.toUpperCase())}
              className="w-full bg-[#16161a] border border-white/10 rounded-xl px-4 py-3 mb-4 text-center font-mono focus:border-purple-500 outline-none transition-colors"
            />
            <button
              onClick={handleStartReceive}
              disabled={!remoteSessionId}
              className="w-full py-3 bg-purple-500 text-white font-bold rounded-xl hover:bg-purple-600 disabled:opacity-50 disabled:hover:bg-purple-500 transition-all"
            >
              Connect as Speaker
            </button>
          </div>
        )}

        {status === 'CONNECTING' && (
          <div className="flex flex-col items-center">
            <Loader2 className="w-10 h-10 text-purple-500 animate-spin mb-4" />
            <p className="text-gray-400 text-sm">Negotiating connection...</p>
          </div>
        )}

        {(status === 'CAPTURING' || status === 'LISTENING') && (
          <div className="flex flex-col items-center w-full">
            <div className="relative mb-6">
              <div className={`absolute inset-0 blur-3xl rounded-full ${status === 'CAPTURING' ? 'bg-blue-500/20' : 'bg-purple-500/20'}`}></div>
              {status === 'CAPTURING' ? (
                <CheckCircle2 className="w-16 h-16 text-blue-500 relative" />
              ) : (
                <div className="relative flex items-center justify-center">
                  <Speaker className="w-16 h-16 text-purple-500 animate-bounce" />
                </div>
              )}
            </div>
            <h2 className="text-xl font-bold mb-1">{status === 'CAPTURING' ? 'Live Stream' : 'Output Active'}</h2>
            <p className="text-gray-500 text-xs mb-4 uppercase tracking-widest font-bold">
              {status === 'CAPTURING' ? 'Broadcasting audio' : 'Playing remote audio'}
            </p>

            {/* Source audio toggle — only relevant when this device is the sender */}
            {status === 'CAPTURING' && (
              <button
                onClick={handleToggleSourceMute}
                className={`w-full flex items-center justify-between px-4 py-3 rounded-xl border mb-4 transition-all ${
                  sourceMuted
                    ? 'bg-red-500/10 border-red-500/30 text-red-400 hover:bg-red-500/15'
                    : 'bg-green-500/10 border-green-500/30 text-green-400 hover:bg-green-500/15'
                }`}
              >
                <span className="flex items-center gap-2 text-sm font-semibold">
                  {sourceMuted
                    ? <><VolumeX size={16} /> Source muted</>
                    : <><Volume2 size={16} /> Source playing</>
                  }
                </span>
                <span className={`text-[10px] font-bold uppercase tracking-widest px-2 py-1 rounded-lg ${
                  sourceMuted ? 'bg-red-500/20 text-red-400' : 'bg-green-500/20 text-green-400'
                }`}>
                  {sourceMuted ? 'Tap to unmute' : 'Tap to mute'}
                </span>
              </button>
            )}

            {status === 'CAPTURING' && (
              <p className="text-gray-600 text-[10px] text-center mb-4 px-2">
                {sourceMuted
                  ? 'Laptop speakers are silent — audio plays only on connected devices.'
                  : 'Laptop speakers are active — audio plays here and on all connected devices.'}
              </p>
            )}

            <div className="w-full bg-[#16161a] p-4 rounded-xl border border-white/5 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Laptop size={18} className="text-gray-400" />
                <span className="text-sm text-gray-300 font-mono">{mode === 'SEND' ? sessionId : remoteSessionId}</span>
              </div>
              <span className="flex items-center gap-1.5">
                <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                <span className="text-[10px] font-bold text-green-500 uppercase">Live</span>
              </span>
            </div>

            <button
              onClick={() => window.location.reload()}
              className="mt-8 text-gray-500 text-xs hover:text-white transition-colors"
            >
              Disconnect
            </button>
          </div>
        )}

        {status === 'ERROR' && (
          <div className="flex flex-col items-center text-center">
            <AlertCircle className="w-12 h-12 text-red-500 mb-4" />
            <p className="text-red-400 font-medium mb-1">Failed to Connect</p>
            <p className="text-gray-500 text-xs mb-6 px-4">{error}</p>
            <button
              onClick={() => setStatus('IDLE')}
              className="px-4 py-2 bg-[#16161a] rounded-lg border border-white/10 text-xs"
            >
              Back to Menu
            </button>
          </div>
        )}
      </div>

      {/* Footer */}
      <div className="mt-6 pt-4 border-t border-white/5 flex items-center justify-between text-[10px] text-gray-600 font-bold uppercase tracking-widest">
        <span>WebRTC 2.0</span>
        <span className="flex items-center gap-1">
          <div className="w-1.5 h-1.5 bg-green-500 rounded-full"></div> Server Online
        </span>
      </div>
    </div>
  );
}

export default App;
