// Native setup
export { registerVoxaGlobals } from './setup.js';

// Provider + hooks are pure-React → reused from @voxaflow/react (no DOM at module level).
export {
  VoxaProvider,
  useVoxaClient,
  useConnectionState,
  useTranscript,
  useVoxaCall,
  useVoxaChat,
  type VoxaProviderProps,
  type UseTranscript,
  type UseVoxaCall,
  type UseVoxaChat,
} from '@voxaflow/react';

// RN-native components
export { CallView, type CallViewProps } from './components/CallView.js';
export { ChatWidget, type ChatWidgetProps } from './components/ChatWidget.js';

// Core types
export type {
  VoxaClient,
  VoxaConfig,
  Capability,
  TranscriptSegment,
  ChatMessage,
  ExtractedEntity,
  VoxaConnectionState,
  VoxaError,
} from '@voxaflow/web-core';
