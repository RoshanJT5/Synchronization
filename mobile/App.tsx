import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  AppState,
  Linking,
  NativeModules,
  PermissionsAndroid,
  Platform,
  SafeAreaView,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { io, Socket } from 'socket.io-client';
import {
  MediaStream,
  RTCIceCandidate,
  RTCPeerConnection,
  RTCSessionDescription,
  RTCView,
} from 'react-native-webrtc';
import {
  AlertCircle,
  Camera as CameraIcon,
  CheckCircle2,
  Keyboard,
  Radio,
  RefreshCcw,
  Speaker,
  Wifi,
  X,
} from 'lucide-react-native';

type ConnectionStatus = 'IDLE' | 'SCANNING' | 'CONNECTING' | 'CONNECTED' | 'ERROR';

const DEFAULT_SERVER = '';

const { SyncronizationPlayback } = NativeModules;

function parseSessionCode(value: string) {
  const trimmed = value.trim();

  if (trimmed.startsWith('sync://connect') || trimmed.startsWith('syncronization://connect') || trimmed.includes('/connect')) {
    const match = trimmed.match(/[?&]id=([^&]+)/);
    return decodeURIComponent(match?.[1] || '').toUpperCase();
  }

  return trimmed.replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
}

function parseServerUrl(value: string) {
  const match = value.trim().match(/[?&]server=([^&]+)/);
  return match?.[1] ? decodeURIComponent(match[1]) : '';
}

function normalizeServerUrl(value: string) {
  const trimmed = value.trim().replace(/\/+$/, '');
  if (!trimmed) return DEFAULT_SERVER || '';
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  return `http://${trimmed}`;
}

export default function App() {
  const [status, setStatus] = useState<ConnectionStatus>('IDLE');
  const [serverUrl, setServerUrl] = useState(DEFAULT_SERVER || '');
  const [sessionInput, setSessionInput] = useState('');
  const [activeSessionId, setActiveSessionId] = useState('');
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);
  const [error, setError] = useState('');
  const [peerState, setPeerState] = useState('Not connected');

  const socketRef = useRef<Socket | null>(null);
  const pcRef = useRef<RTCPeerConnection | null>(null);
  const targetPeerRef = useRef<string | null>(null);
  const pendingCandidatesRef = useRef<any[]>([]);
  const connectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const connectToSessionRef = useRef<((rawCode?: string, serverOverride?: string) => void) | null>(null);

  const cleanServerUrl = useMemo(() => normalizeServerUrl(serverUrl), [serverUrl]);

  const stopPlaybackService = useCallback(() => {
    if (Platform.OS === 'android' && SyncronizationPlayback?.stop) {
      SyncronizationPlayback.stop();
    }
  }, []);

  const startPlaybackService = useCallback(async () => {
    if (Platform.OS === 'android' && SyncronizationPlayback?.start) {
      if (Platform.Version >= 33) {
        await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS);
      }
      SyncronizationPlayback.start();
    }
  }, []);

  const resetConnection = useCallback(() => {
    if (connectTimeoutRef.current) {
      clearTimeout(connectTimeoutRef.current);
      connectTimeoutRef.current = null;
    }

    socketRef.current?.removeAllListeners();
    socketRef.current?.disconnect();
    socketRef.current = null;

    pcRef.current?.close();
    pcRef.current = null;

    targetPeerRef.current = null;
    pendingCandidatesRef.current = [];
    setRemoteStream(null);
    setPeerState('Not connected');
    stopPlaybackService();
  }, [stopPlaybackService]);

  useEffect(() => {
    return resetConnection;
  }, [resetConnection]);

  useEffect(() => {
    const sub = AppState.addEventListener('change', nextState => {
      if (nextState === 'active' && status === 'CONNECTED') {
        startPlaybackService();
      }
    });

    return () => sub.remove();
  }, [startPlaybackService, status]);

  const requestCameraAndScan = useCallback(async () => {
    Alert.alert(
      'Use your phone camera',
      'Open the normal Camera app or Google Lens, scan the extension QR, and choose Syncronization. You can also type the session code here.'
    );
  }, []);

  const handleScannedValue = useCallback((value: string) => {
    const sid = parseSessionCode(value);
    if (!sid) return;

    const linkedServerUrl = parseServerUrl(value);
    if (linkedServerUrl) {
      setServerUrl(linkedServerUrl);
    }

    setSessionInput(sid);
    connectToSessionRef.current?.(sid, linkedServerUrl || undefined);
  }, []);

  const failConnection = useCallback((message: string) => {
    resetConnection();
    setError(message);
    setStatus('ERROR');
  }, [resetConnection]);

  const connectToSession = useCallback(async (rawCode?: string, serverOverride?: string) => {
    const sid = parseSessionCode(rawCode || sessionInput);
    const url = normalizeServerUrl(serverOverride || serverUrl);

    if (!sid) {
      setError('Enter or scan a session code first.');
      setStatus('ERROR');
      return;
    }

    resetConnection();
    setError('');
    setActiveSessionId(sid);
    setStatus('CONNECTING');
    setPeerState('Connecting to signaling server');

    const socket = io(url, {
      autoConnect: false,
      transports: ['websocket', 'polling'],
      reconnectionAttempts: 3,
      timeout: 10000,
    });

    const pc = new RTCPeerConnection({
      iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
    });

    socketRef.current = socket;
    pcRef.current = pc;

    connectTimeoutRef.current = setTimeout(() => {
      failConnection(`Could not connect to ${url}. Check that the signaling server is running and your phone is on the same network.`);
    }, 12000);

    pc.addTransceiver('audio', { direction: 'recvonly' });

    (pc as any).addEventListener('icecandidate', (event: any) => {
      if (!event.candidate) return;

      socket.emit('signal', {
        sessionId: sid,
        to: targetPeerRef.current || undefined,
        signal: { candidate: event.candidate },
      });
    });

    (pc as any).addEventListener('connectionstatechange', () => {
      const state = pc.connectionState || 'connecting';
      setPeerState(`WebRTC ${state}`);

      if (state === 'failed' || state === 'closed' || state === 'disconnected') {
        failConnection(`WebRTC connection ${state}. Try reconnecting from both devices.`);
      }
    });

    (pc as any).addEventListener('track', (event: any) => {
      const stream = event.streams?.[0];
      if (!stream) return;

      stream.getAudioTracks().forEach((track: any) => {
        track.enabled = true;
      });

      setRemoteStream(stream);
      setStatus('CONNECTED');
      setPeerState('Receiving audio');
      startPlaybackService();
    });

    socket.on('connect', () => {
      if (connectTimeoutRef.current) {
        clearTimeout(connectTimeoutRef.current);
        connectTimeoutRef.current = null;
      }

      setPeerState('Joined signaling room');
      socket.emit('join-session', sid);
    });

    socket.on('connect_error', err => {
      failConnection(err.message || `Could not connect to ${url}`);
    });

    socket.on('disconnect', reason => {
      if (status !== 'IDLE') {
        setPeerState(`Signaling disconnected: ${reason}`);
      }
    });

    socket.on('signal', async ({ from, signal }) => {
      try {
        targetPeerRef.current = from;

        if (signal.type === 'offer') {
          setPeerState('Offer received');
          await pc.setRemoteDescription(new RTCSessionDescription(signal));

          for (const candidate of pendingCandidatesRef.current) {
            await pc.addIceCandidate(new RTCIceCandidate(candidate));
          }
          pendingCandidatesRef.current = [];

          const answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);

          socket.emit('signal', {
            sessionId: sid,
            to: from,
            signal: answer,
          });

          setPeerState('Answer sent');
          return;
        }

        if (signal.candidate) {
          if (!pc.remoteDescription) {
            pendingCandidatesRef.current.push(signal.candidate);
            return;
          }

          await pc.addIceCandidate(new RTCIceCandidate(signal.candidate));
        }
      } catch (err: any) {
        failConnection(err?.message || 'Failed during WebRTC negotiation.');
      }
    });

    socket.connect();
  }, [failConnection, resetConnection, serverUrl, sessionInput, startPlaybackService, status]);

  useEffect(() => {
    connectToSessionRef.current = connectToSession;
  }, [connectToSession]);

  useEffect(() => {
    const openFromUrl = (url: string | null) => {
      if (!url) return;
      handleScannedValue(url);
    };

    Linking.getInitialURL().then(openFromUrl);
    const sub = Linking.addEventListener('url', event => openFromUrl(event.url));

    return () => sub.remove();
  }, [handleScannedValue]);

  const disconnect = useCallback(() => {
    resetConnection();
    setStatus('IDLE');
    setError('');
    setActiveSessionId('');
  }, [resetConnection]);

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#0a0a0c" />

      <View style={styles.header}>
        <View style={styles.brandMark}>
          <Speaker size={22} color="#ffffff" />
        </View>
        <View style={styles.brandTextWrap}>
          <Text style={styles.brandTitle}>Syncronization</Text>
          <Text style={styles.brandSubtitle}>Mobile speaker</Text>
        </View>
        {status !== 'IDLE' && (
          <TouchableOpacity onPress={disconnect} style={styles.iconButton} accessibilityLabel="Disconnect">
            <X size={20} color="#a1a1aa" />
          </TouchableOpacity>
        )}
      </View>

      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
          {status === 'IDLE' && (
            <View style={styles.panel}>
              <View style={styles.heroIcon}>
                <Radio size={38} color="#a855f7" />
              </View>

              <Text style={styles.title}>Connect as Speaker</Text>
              <Text style={styles.copy}>Scan the QR code from the extension or type the session code.</Text>

              <View style={styles.fieldGroup}>
                <Text style={styles.label}>Signaling server</Text>
                <View style={styles.inputRow}>
                  <Wifi size={18} color="#71717a" />
                  <TextInput
                    value={serverUrl}
                    onChangeText={setServerUrl}
                    placeholder="http://192.168.1.5:3001"
                    placeholderTextColor="#52525b"
                    autoCapitalize="none"
                    autoCorrect={false}
                    keyboardType="url"
                    style={styles.input}
                  />
                </View>
                <Text style={styles.hint}>Phone users should enter the computer IP, not localhost.</Text>
              </View>

              <View style={styles.fieldGroup}>
                <Text style={styles.label}>Session code</Text>
                <View style={styles.inputRow}>
                  <Keyboard size={18} color="#71717a" />
                  <TextInput
                    value={sessionInput}
                    onChangeText={text => setSessionInput(parseSessionCode(text))}
                    placeholder="A1B2C3D4"
                    placeholderTextColor="#52525b"
                    autoCapitalize="characters"
                    autoCorrect={false}
                    style={[styles.input, styles.codeInput]}
                    maxLength={16}
                  />
                </View>
              </View>

              <TouchableOpacity style={styles.primaryButton} onPress={() => connectToSession()}>
                <Speaker size={19} color="#0a0a0c" />
                <Text style={styles.primaryButtonText}>Connect</Text>
              </TouchableOpacity>

              <TouchableOpacity style={styles.scanButton} onPress={requestCameraAndScan}>
                <CameraIcon size={19} color="#ffffff" />
                <Text style={styles.scanButtonText}>Scan QR Code</Text>
              </TouchableOpacity>
            </View>
          )}

          {status === 'CONNECTING' && (
            <View style={styles.centerPanel}>
              <ActivityIndicator size="large" color="#a855f7" />
              <Text style={styles.title}>Negotiating</Text>
              <Text style={styles.copy}>{peerState}</Text>
              <View style={styles.sessionBox}>
                <Text style={styles.sessionLabel}>Session</Text>
                <Text style={styles.sessionValue}>{activeSessionId}</Text>
              </View>
            </View>
          )}

          {status === 'CONNECTED' && (
            <View style={styles.centerPanel}>
              <View style={styles.liveGlow}>
                <CheckCircle2 size={68} color="#3b82f6" />
              </View>
              <Text style={styles.title}>Output Active</Text>
              <Text style={styles.copy}>Audio keeps playing while the screen is off.</Text>

              {remoteStream && (
                <RTCView
                  streamURL={remoteStream.toURL()}
                  objectFit="cover"
                  style={styles.hiddenRtcView}
                />
              )}

              <View style={styles.waveRow}>
                {[28, 52, 38, 70, 44, 58, 32].map((height, index) => (
                  <View key={index} style={[styles.waveBar, { height }]} />
                ))}
              </View>

              <View style={styles.sessionBox}>
                <Text style={styles.sessionLabel}>Live session</Text>
                <Text style={styles.sessionValue}>{activeSessionId}</Text>
                <Text style={styles.stateText}>{cleanServerUrl}</Text>
              </View>

              <TouchableOpacity style={styles.secondaryButton} onPress={disconnect}>
                <Text style={styles.secondaryButtonText}>Disconnect</Text>
              </TouchableOpacity>
            </View>
          )}

          {status === 'ERROR' && (
            <View style={styles.centerPanel}>
              <AlertCircle size={58} color="#ef4444" />
              <Text style={styles.title}>Could not connect</Text>
              <Text style={styles.errorText}>{error}</Text>
              <TouchableOpacity style={styles.primaryButton} onPress={() => setStatus('IDLE')}>
                <RefreshCcw size={19} color="#0a0a0c" />
                <Text style={styles.primaryButtonText}>Try Again</Text>
              </TouchableOpacity>
            </View>
          )}
      </ScrollView>

      <View style={styles.footer}>
        <Text style={styles.footerText}>WebRTC receiver</Text>
        <View style={styles.footerDot} />
        <Text style={styles.footerText}>{peerState}</Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0a0a0c',
  },
  header: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 12,
    paddingHorizontal: 20,
    paddingVertical: 16,
  },
  brandMark: {
    alignItems: 'center',
    backgroundColor: '#7c3aed',
    borderRadius: 14,
    height: 44,
    justifyContent: 'center',
    width: 44,
  },
  brandTextWrap: {
    flex: 1,
  },
  brandTitle: {
    color: '#ffffff',
    fontSize: 20,
    fontWeight: '800',
  },
  brandSubtitle: {
    color: '#71717a',
    fontSize: 12,
    fontWeight: '700',
    textTransform: 'uppercase',
  },
  iconButton: {
    alignItems: 'center',
    backgroundColor: '#18181b',
    borderColor: '#27272a',
    borderRadius: 12,
    borderWidth: 1,
    height: 42,
    justifyContent: 'center',
    width: 42,
  },
  content: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 20,
  },
  panel: {
    gap: 18,
  },
  heroIcon: {
    alignItems: 'center',
    alignSelf: 'center',
    backgroundColor: 'rgba(168, 85, 247, 0.12)',
    borderColor: 'rgba(168, 85, 247, 0.25)',
    borderRadius: 40,
    borderWidth: 1,
    height: 80,
    justifyContent: 'center',
    width: 80,
  },
  title: {
    color: '#ffffff',
    fontSize: 24,
    fontWeight: '800',
    textAlign: 'center',
  },
  copy: {
    color: '#a1a1aa',
    fontSize: 15,
    lineHeight: 22,
    textAlign: 'center',
  },
  fieldGroup: {
    gap: 8,
  },
  label: {
    color: '#d4d4d8',
    fontSize: 12,
    fontWeight: '800',
    letterSpacing: 0.8,
    textTransform: 'uppercase',
  },
  inputRow: {
    alignItems: 'center',
    backgroundColor: '#16161a',
    borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 12,
    borderWidth: 1,
    flexDirection: 'row',
    gap: 10,
    paddingHorizontal: 14,
  },
  input: {
    color: '#ffffff',
    flex: 1,
    fontSize: 15,
    minHeight: 52,
  },
  codeInput: {
    fontSize: 20,
    fontWeight: '800',
    letterSpacing: 2,
    textAlign: 'center',
  },
  hint: {
    color: '#71717a',
    fontSize: 12,
  },
  primaryButton: {
    alignItems: 'center',
    backgroundColor: '#ffffff',
    borderRadius: 12,
    flexDirection: 'row',
    gap: 10,
    justifyContent: 'center',
    minHeight: 52,
  },
  primaryButtonText: {
    color: '#0a0a0c',
    fontSize: 16,
    fontWeight: '800',
  },
  scanButton: {
    alignItems: 'center',
    backgroundColor: '#7c3aed',
    borderRadius: 12,
    flexDirection: 'row',
    gap: 10,
    justifyContent: 'center',
    minHeight: 52,
  },
  scanButtonText: {
    color: '#ffffff',
    fontSize: 16,
    fontWeight: '800',
  },
  centerPanel: {
    alignItems: 'center',
    gap: 18,
  },
  sessionBox: {
    alignItems: 'center',
    backgroundColor: '#16161a',
    borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 12,
    borderWidth: 1,
    padding: 18,
    width: '100%',
  },
  sessionLabel: {
    color: '#71717a',
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  sessionValue: {
    color: '#c084fc',
    fontSize: 22,
    fontWeight: '900',
    letterSpacing: 2,
    marginTop: 4,
  },
  stateText: {
    color: '#71717a',
    fontSize: 12,
    marginTop: 8,
  },
  liveGlow: {
    alignItems: 'center',
    backgroundColor: 'rgba(59, 130, 246, 0.1)',
    borderRadius: 50,
    height: 100,
    justifyContent: 'center',
    width: 100,
  },
  hiddenRtcView: {
    height: 1,
    opacity: 0,
    width: 1,
  },
  waveRow: {
    alignItems: 'center',
    flexDirection: 'row',
    gap: 8,
    height: 84,
    justifyContent: 'center',
  },
  waveBar: {
    backgroundColor: '#a855f7',
    borderRadius: 5,
    width: 10,
  },
  secondaryButton: {
    alignItems: 'center',
    backgroundColor: '#18181b',
    borderColor: '#27272a',
    borderRadius: 12,
    borderWidth: 1,
    minHeight: 48,
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  secondaryButtonText: {
    color: '#ffffff',
    fontSize: 15,
    fontWeight: '800',
  },
  errorText: {
    color: '#fca5a5',
    fontSize: 14,
    lineHeight: 21,
    textAlign: 'center',
  },
  footer: {
    alignItems: 'center',
    borderColor: 'rgba(255,255,255,0.06)',
    borderTopWidth: 1,
    flexDirection: 'row',
    gap: 8,
    justifyContent: 'center',
    padding: 14,
  },
  footerDot: {
    backgroundColor: '#22c55e',
    borderRadius: 4,
    height: 7,
    width: 7,
  },
  footerText: {
    color: '#52525b',
    fontSize: 11,
    fontWeight: '800',
    textTransform: 'uppercase',
  },
});
