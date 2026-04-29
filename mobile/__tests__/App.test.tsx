/**
 * @format
 */

import React from 'react';
import ReactTestRenderer from 'react-test-renderer';
import App from '../App';

jest.mock('react-native-vision-camera', () => {
  const React = require('react');
  const { View } = require('react-native');

  return {
    Camera: (props: any) => React.createElement(View, props),
    VisionCamera: {
      cameraPermissionStatus: 'authorized',
      requestCameraPermission: jest.fn(async () => true),
    },
    useCameraDevice: jest.fn(() => ({ id: 'back-camera' })),
    useObjectOutput: jest.fn(() => ({ type: 'object-output' })),
  };
});

jest.mock('socket.io-client', () => ({
  io: jest.fn(() => ({
    connect: jest.fn(),
    disconnect: jest.fn(),
    emit: jest.fn(),
    on: jest.fn(),
    removeAllListeners: jest.fn(),
  })),
}));

jest.mock('react-native-webrtc', () => {
  const React = require('react');
  const { View } = require('react-native');

  class RTCPeerConnection {
    connectionState = 'new';
    remoteDescription = null;
    addEventListener = jest.fn();
    addIceCandidate = jest.fn();
    addTransceiver = jest.fn();
    close = jest.fn();
    createAnswer = jest.fn(async () => ({ type: 'answer', sdp: '' }));
    setLocalDescription = jest.fn();
    setRemoteDescription = jest.fn();
  }

  return {
    MediaStream: jest.fn(),
    RTCIceCandidate: jest.fn(candidate => candidate),
    RTCPeerConnection,
    RTCSessionDescription: jest.fn(description => description),
    RTCView: (props: any) => React.createElement(View, props),
  };
});

test('renders correctly', async () => {
  await ReactTestRenderer.act(() => {
    ReactTestRenderer.create(<App />);
  });
});
