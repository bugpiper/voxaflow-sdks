import { useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useVoxaChat } from '@voxaflow/react';

export interface ChatWidgetProps {
  conversationId?: string;
  channel?: string;
  accentColor?: string;
}

/** Minimal RN threaded chat + bot. Bot messages are labeled (AI transparency). */
export function ChatWidget({ conversationId, channel, accentColor = '#4f46e5' }: ChatWidgetProps): JSX.Element {
  const { messages, send } = useVoxaChat({ conversationId, channel });
  const [text, setText] = useState('');

  const onSend = () => {
    const t = text.trim();
    if (!t) return;
    setText('');
    void send(t);
  };

  return (
    <View style={styles.container}>
      <ScrollView style={styles.msgs} contentContainerStyle={styles.msgsContent}>
        {messages.length === 0 && <Text style={styles.empty}>Say hello to start the conversation.</Text>}
        {messages.map((m) => {
          const mine = m.sender === 'CONTACT';
          return (
            <View key={m.id} style={[styles.row, mine ? styles.rowMe : styles.rowThem]}>
              <View
                style={[
                  styles.bubble,
                  mine ? { backgroundColor: accentColor } : styles.bubbleThem,
                  m.isDraft ? styles.draft : null,
                ]}
              >
                {m.isBot && <Text style={styles.botLabel}>🤖 Bot{m.isDraft ? ' · draft' : ''}</Text>}
                <Text style={mine ? styles.textMe : styles.textThem}>{m.content}</Text>
              </View>
            </View>
          );
        })}
      </ScrollView>
      <View style={styles.inputRow}>
        <TextInput
          value={text}
          onChangeText={setText}
          placeholder="Type a message…"
          style={styles.input}
          onSubmitEditing={onSend}
          returnKeyType="send"
        />
        <Pressable style={[styles.send, { backgroundColor: accentColor }]} onPress={onSend}>
          <Text style={styles.sendText}>Send</Text>
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
  msgs: { flex: 1, backgroundColor: '#f9fafb' },
  msgsContent: { padding: 12 },
  empty: { color: '#9ca3af', textAlign: 'center', marginTop: 24 },
  row: { flexDirection: 'row', marginVertical: 4 },
  rowMe: { justifyContent: 'flex-end' },
  rowThem: { justifyContent: 'flex-start' },
  bubble: { maxWidth: '78%', paddingVertical: 8, paddingHorizontal: 11, borderRadius: 12 },
  bubbleThem: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#e5e7eb' },
  draft: { opacity: 0.6 },
  botLabel: { fontSize: 10, opacity: 0.7, marginBottom: 2 },
  textMe: { color: '#fff' },
  textThem: { color: '#111827' },
  inputRow: { flexDirection: 'row', gap: 8, padding: 8, borderTopWidth: 1, borderTopColor: '#e5e7eb' },
  input: { flex: 1, paddingVertical: 9, paddingHorizontal: 11, borderWidth: 1, borderColor: '#d1d5db', borderRadius: 10 },
  send: { paddingVertical: 9, paddingHorizontal: 16, borderRadius: 10, justifyContent: 'center' },
  sendText: { color: '#fff' },
});
