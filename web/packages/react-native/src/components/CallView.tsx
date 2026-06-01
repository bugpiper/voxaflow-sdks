import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useConnectionState, useTranscript, useVoxaCall } from '@voxaflow/react';

export interface CallViewProps {
  video?: boolean;
  accentColor?: string;
}

/**
 * Minimal RN call surface: start/end + mic toggle, connection state, and a live transcript
 * (final + interim). For video tiles, render `@livekit/react-native`'s VideoTrack/VideoView
 * against `call.lkRoom`.
 */
export function CallView({ video = false, accentColor = '#4f46e5' }: CallViewProps): JSX.Element {
  const conn = useConnectionState();
  const { call, micOn, starting, start, end, toggleMic } = useVoxaCall();
  const { finals, interim } = useTranscript();
  const inCall = call !== null;

  return (
    <View style={styles.container}>
      <View style={styles.bar}>
        {!inCall ? (
          <Pressable
            style={[styles.btn, { backgroundColor: accentColor }]}
            disabled={starting}
            onPress={() => void start({ video })}
          >
            <Text style={styles.btnLight}>{starting ? 'Starting…' : video ? 'Start video call' : 'Start call'}</Text>
          </Pressable>
        ) : (
          <>
            <Pressable style={styles.btn} onPress={() => void toggleMic()}>
              <Text>{micOn ? 'Mute' : 'Unmute'}</Text>
            </Pressable>
            <Pressable style={[styles.btn, { backgroundColor: '#dc2626' }]} onPress={() => void end()}>
              <Text style={styles.btnLight}>End</Text>
            </Pressable>
          </>
        )}
        <Text style={styles.status}>{conn}</Text>
      </View>
      <ScrollView style={styles.msgs} contentContainerStyle={styles.msgsContent}>
        {finals.length === 0 && Object.keys(interim).length === 0 && (
          <Text style={styles.empty}>Speak after starting the call — your words appear here.</Text>
        )}
        {finals.map((s, i) => (
          <Text key={s.id ?? String(i)} style={styles.line}>
            <Text style={styles.spk}>{s.speaker}: </Text>
            {s.text}
          </Text>
        ))}
        {Object.entries(interim).map(([spk, text]) => (
          <Text key={`i-${spk}`} style={[styles.line, styles.interim]}>
            <Text style={styles.spk}>{spk}: </Text>
            {text}
          </Text>
        ))}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  bar: { flexDirection: 'row', alignItems: 'center', gap: 8, padding: 8, borderBottomWidth: 1, borderBottomColor: '#e5e7eb' },
  btn: { paddingVertical: 8, paddingHorizontal: 14, borderRadius: 8, borderWidth: 1, borderColor: '#d1d5db' },
  btnLight: { color: '#fff' },
  status: { marginLeft: 'auto', fontSize: 12, color: '#6b7280' },
  msgs: { flex: 1 },
  msgsContent: { padding: 12 },
  empty: { color: '#9ca3af' },
  line: { marginVertical: 4, lineHeight: 20 },
  spk: { fontWeight: '700' },
  interim: { opacity: 0.55, fontStyle: 'italic' },
});
