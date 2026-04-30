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

function normalizeServerUrl(value: string) {
  const trimmed = value.trim().replace(/\/+$/, '');
  if (!trimmed) return DEFAULT_SERVER || '';
  if (/^https?:\/\//i.test(trimmed)) return trimmed;
  return `http://${trimmed}`;
}

export default function App() {
  const [status, setStatus] = useState<ConnectionStatus>('IDLE');
  const [serverUrl, setServerUrl] = useState(DEFAULT_SERVER);
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

  const handleDeepLink = useCallback((url: string) => {
    const match = url.match(/[?&]id=([^&]+)/);
    const sid = match?.[1] ? decodeURIComponent(match[1]).toUpperCase() : '';
    
    const serverMatch = url.match(/[?&]server=([^&]+)/);
    const server = serverMatch?.[1] ? decodeURIComponent(serverMatch[1]) : '';

    if (sid) {
      setSessionInput(sid);
      if (server) setServerUrl(server);
      // Automatically connect
      setTimeout(() => connectToSession(sid, server), 500);
    }
  }, []);

  useEffect(() => {
    Linking.getInitialURL().then(url => {
      if (url) handleDeepLink(url);
    });
    const sub = Linking.addEventListener('url', ({ url }) => handleDeepLink(url));
    return () => sub.remove();
  }, [handleDeepLink]);

  const connectToSession = useCallback((rawCode?: string, serverOverride?: string) => {
    const sid = parseSessionCode(rawCode || sessionInput);
    const server = normalizeServerUrl(serverOverride || serverUrl);

    if (!sid) {
      Alert.alert('Error', 'Please enter a session ID or scan a QR code.');
      return;
    }

    if (!server || server === 'http://') {
      Alert.alert('Error', 'Please enter your signaling server address (e.g., 192.168.1.5:3000)');
      return;
    }

    resetConnection();
    setStatus('CONNECTING');
    setActiveSessionId(sid);
    setError('');

    try {
      const socket = io(server, {
        timeout: 10000,
        transports: ['websocket'],
      });
      socketRef.current = socket;

      socket.on('connect', () => {
        socket.emit('join-session', { sessionId: sid, role: 'receiver' });
      });

      socket.on('session-joined', () => {
        setStatus('CONNECTED');
        startPlaybackService();
      });

      socket.on('offer', async ({ offer, from }) => {
        targetPeerRef.current = from;
        const pc = new RTCPeerConnection({
          iceServers: [{ urls: 'stun:stun.l.google.com:19302' }],
        });
        pcRef.current = pc;

        pc.onicecandidate = ({ candidate }) => {
          if (candidate) {
            socket.emit('ice-candidate', { candidate, to: from });
          }
        };

        pc.onconnectionstatechange = () => {
          setPeerState(pc.connectionState);
        };

        pc.ontrack = (event) => {
          if (event.streams && event.streams[0]) {
            setRemoteStream(event.streams[0]);
          }
        };

        await pc.setRemoteDescription(new RTCSessionDescription(offer));
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);

        socket.emit('answer', { answer, to: from });

        // Add any pending candidates
        while (pendingCandidatesRef.current.length > 0) {
          const cand = pendingCandidatesRef.current.shift();
          await pc.addIceCandidate(new RTCIceCandidate(cand));
        }
      });

      socket.on('ice-candidate', async ({ candidate }) => {
        if (pcRef.current?.remoteDescription) {
          await pcRef.current.addIceCandidate(new RTCIceCandidate(candidate));
        } else {
          pendingCandidatesRef.current.push(candidate);
        }
      });

      socket.on('connect_error', (err) => {
        setError(`Connection failed: ${err.message}`);
        setStatus('ERROR');
      });

      socket.on('disconnect', () => {
        if (status === 'CONNECTED') {
          setStatus('IDLE');
          resetConnection();
        }
      });

    } catch (err: any) {
      setError(err.message);
      setStatus('ERROR');
    }
  }, [sessionInput, serverUrl, resetConnection, startPlaybackService, status]);

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="light-content" backgroundColor="#0f172a" />
      
      <ScrollView contentContainerStyle={styles.scrollContent}>
        {/* Header */}
        <View style={styles.header}>
          <View style={styles.logoContainer}>
            <Speaker size={32} color="#22d3ee" strokeWidth={2.5} />
            <Text style={styles.logoText}>Syncronization</Text>
          </View>
          <Text style={styles.tagline}>Ultra-low latency remote audio</Text>
        </View>

        {/* Status Card */}
        <View style={[styles.card, styles.glass]}>
          <View style={styles.statusHeader}>
            <View style={styles.statusIndicator}>
              <View style={[styles.dot, { backgroundColor: status === 'CONNECTED' ? '#22c55e' : (status === 'ERROR' ? '#ef4444' : '#64748b') }]} />
              <Text style={styles.statusLabel}>{status}</Text>
            </View>
            {status === 'CONNECTED' && (
              <View style={styles.peerBadge}>
                <Wifi size={14} color="#22d3ee" />
                <Text style={styles.peerText}>{peerState}</Text>
              </View>
            )}
          </View>

          {activeSessionId && (
            <View style={styles.sessionBadge}>
              <Text style={styles.sessionLabel}>ACTIVE SESSION</Text>
              <Text style={styles.sessionId}>{activeSessionId}</Text>
            </View>
          )}

          {error ? (
            <View style={styles.errorBox}>
              <AlertCircle size={18} color="#ef4444" />
              <Text style={styles.errorText}>{error}</Text>
            </View>
          ) : status === 'IDLE' ? (
            <Text style={styles.hintText}>Enter session code or scan QR to start</Text>
          ) : null}
        </View>

        {/* Input Controls */}
        {status === 'IDLE' || status === 'ERROR' ? (
          <View style={styles.controls}>
            <View style={styles.inputGroup}>
              <View style={styles.inputLabelRow}>
                <Radio size={16} color="#94a3b8" />
                <Text style={styles.inputLabel}>Signaling Server</Text>
              </View>
              <TextInput
                style={styles.input}
                placeholder="e.g. 192.168.1.5:3000"
                placeholderTextColor="#475569"
                value={serverUrl}
                onChangeText={setServerUrl}
                autoCapitalize="none"
                autoCorrect={false}
              />
            </View>

            <View style={styles.inputGroup}>
              <View style={styles.inputLabelRow}>
                <Keyboard size={16} color="#94a3b8" />
                <Text style={styles.inputLabel}>Session Code</Text>
              </View>
              <View style={styles.actionRow}>
                <TextInput
                  style={[styles.input, { flex: 1, marginRight: 12 }]}
                  placeholder="EX: ABCD-1234"
                  placeholderTextColor="#475569"
                  value={sessionInput}
                  onChangeText={setSessionInput}
                  autoCapitalize="characters"
                  autoCorrect={false}
                />
                <TouchableOpacity 
                  style={styles.scanButton}
                  onPress={() => Alert.alert('Coming Soon', 'QR Scanning integration is almost ready. Use the session code for now!')}
                >
                  <CameraIcon size={20} color="#fff" />
                </TouchableOpacity>
              </View>
            </View>

            <TouchableOpacity 
              style={styles.connectButton}
              onPress={() => connectToSession()}
            >
              <Text style={styles.connectButtonText}>Connect to Speaker</Text>
            </TouchableOpacity>
          </View>
        ) : (
          <View style={styles.connectedView}>
            {status === 'CONNECTING' ? (
              <View style={styles.loadingBox}>
                <ActivityIndicator size="large" color="#22d3ee" />
                <Text style={styles.loadingText}>Establishing secure link...</Text>
              </View>
            ) : (
              <View style={styles.activeView}>
                <View style={styles.pulseContainer}>
                  <View style={styles.pulseRing} />
                  <Speaker size={64} color="#22d3ee" />
                </View>
                <Text style={styles.activeText}>Audio Link Active</Text>
                <Text style={styles.activeSubtext}>Your device is now a remote speaker</Text>
                
                <TouchableOpacity 
                  style={styles.disconnectButton}
                  onPress={resetConnection}
                >
                  <X size={20} color="#fff" />
                  <Text style={styles.disconnectButtonText}>Stop Listening</Text>
                </TouchableOpacity>
              </View>
            )}
          </View>
        )}

        {/* Remote Video (Hidden, used for audio only) */}
        {remoteStream && (
          <View style={{ height: 0, opacity: 0 }}>
            <RTCView streamURL={remoteStream.toURL()} style={{ width: 1, height: 1 }} />
          </View>
        )}
      </ScrollView>

      {/* Footer Info */}
      <View style={styles.footer}>
        <Text style={styles.footerText}>Version 1.0.0 • Stability Master Build</Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0f172a',
  },
  scrollContent: {
    padding: 24,
    flexGrow: 1,
  },
  header: {
    marginTop: 20,
    marginBottom: 40,
    alignItems: 'center',
  },
  logoContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  logoText: {
    fontSize: 28,
    fontWeight: '800',
    color: '#fff',
    letterSpacing: -0.5,
  },
  tagline: {
    color: '#94a3b8',
    marginTop: 8,
    fontSize: 16,
  },
  card: {
    padding: 20,
    borderRadius: 24,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    marginBottom: 32,
  },
  glass: {
    backgroundColor: 'rgba(30, 41, 59, 0.5)',
  },
  statusHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 16,
  },
  statusIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  statusLabel: {
    color: '#fff',
    fontSize: 12,
    fontWeight: '700',
    letterSpacing: 1,
  },
  peerBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(34, 211, 238, 0.1)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 12,
    gap: 6,
  },
  peerText: {
    color: '#22d3ee',
    fontSize: 11,
    fontWeight: '600',
  },
  sessionBadge: {
    backgroundColor: 'rgba(255,255,255,0.05)',
    padding: 16,
    borderRadius: 16,
    alignItems: 'center',
  },
  sessionLabel: {
    color: '#64748b',
    fontSize: 10,
    fontWeight: '800',
    marginBottom: 4,
  },
  sessionId: {
    color: '#fff',
    fontSize: 20,
    fontWeight: '800',
    letterSpacing: 2,
  },
  errorBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 12,
  },
  errorText: {
    color: '#ef4444',
    fontSize: 14,
    flex: 1,
  },
  hintText: {
    color: '#64748b',
    fontSize: 14,
    textAlign: 'center',
  },
  controls: {
    gap: 20,
  },
  inputGroup: {
    gap: 8,
  },
  inputLabelRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingLeft: 4,
  },
  inputLabel: {
    color: '#94a3b8',
    fontSize: 13,
    fontWeight: '600',
  },
  input: {
    backgroundColor: '#1e293b',
    borderRadius: 16,
    padding: 16,
    color: '#fff',
    fontSize: 16,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  actionRow: {
    flexDirection: 'row',
  },
  scanButton: {
    width: 56,
    height: 56,
    backgroundColor: '#334155',
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
  },
  connectButton: {
    backgroundColor: '#22d3ee',
    padding: 18,
    borderRadius: 18,
    alignItems: 'center',
    marginTop: 12,
    shadowColor: '#22d3ee',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 0.3,
    shadowRadius: 12,
    elevation: 8,
  },
  connectButtonText: {
    color: '#0f172a',
    fontSize: 16,
    fontWeight: '800',
  },
  connectedView: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 40,
  },
  loadingBox: {
    alignItems: 'center',
    gap: 16,
  },
  loadingText: {
    color: '#94a3b8',
    fontSize: 15,
  },
  activeView: {
    alignItems: 'center',
  },
  pulseContainer: {
    width: 120,
    height: 120,
    justifyContent: 'center',
    alignItems: 'center',
    marginBottom: 24,
  },
  pulseRing: {
    position: 'absolute',
    width: 100,
    height: 100,
    borderRadius: 50,
    borderWidth: 2,
    borderColor: '#22d3ee',
    opacity: 0.5,
  },
  activeText: {
    color: '#fff',
    fontSize: 24,
    fontWeight: '800',
    marginBottom: 8,
  },
  activeSubtext: {
    color: '#64748b',
    fontSize: 15,
    marginBottom: 40,
  },
  disconnectButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#334155',
    paddingVertical: 14,
    paddingHorizontal: 24,
    borderRadius: 100,
    gap: 10,
  },
  disconnectButtonText: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  footer: {
    padding: 20,
    alignItems: 'center',
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.05)',
  },
  footerText: {
    color: '#475569',
    fontSize: 11,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1,
  }
});
