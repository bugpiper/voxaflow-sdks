export { VoxaProvider, useVoxaClient, type VoxaProviderProps } from './context.js';
export {
  useConnectionState,
  useTranscript,
  useVoxaCall,
  useVoxaChat,
  useEntities,
  useSuggestions,
  useIncomingCall,
  type UseTranscript,
  type UseVoxaCall,
  type UseVoxaChat,
  type UseEntities,
  type UseSuggestions,
  type UseIncomingCall,
} from './hooks.js';
export { CallView, type CallViewProps } from './components/CallView.js';
export { ChatWidget, type ChatWidgetProps } from './components/ChatWidget.js';
export { CopilotPanel, type CopilotPanelProps } from './components/CopilotPanel.js';
export { IncomingCallModal, type IncomingCallModalProps } from './components/IncomingCallModal.js';

// Re-export core types so consumers don't need a direct @voxaflow/web-core import.
export type {
  VoxaClient,
  VoxaConfig,
  Capability,
  TranscriptSegment,
  ChatMessage,
  ExtractedEntity,
  VoxaConnectionState,
  VoxaError,
  VoxaCallRing,
  VoxaCallSignal,
} from '@voxaflow/web-core';
