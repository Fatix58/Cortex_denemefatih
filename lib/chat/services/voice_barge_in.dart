// lib/chat/services/voice_barge_in.dart
//
// Confidence-gated barge-in for Voice Mode.
//
// The remote microphone stays OPEN while the assistant speaks (continuous
// capture, no muting, whatever AEC the record config enabled stays on), so
// the problem is deciding which of the sounds and transcripts arriving
// during playback are the USER starting to talk rather than the assistant's
// own voice bouncing back.
//
// A transcript alone can be the assistant's speaker echo, so the detector
// applies confidence, fingerprint, and timing checks before interrupting.
//
//   * a transcript the provider was confident about (>= [minConfidence]),
//     with at least [minWords] words (single-word echoes are rejected),
//   * that is not the assistant's own words echoed back ([echoSimilarity]
//     against the recently spoken sentences below [echoSimilarityLimit]),
//   * arriving outside the [postTtsDiscardWindow] after playback stopped
//     (the tail of the assistant's audio often transcribes right after TTS
//     ends),
//
// Pure logic, clock-injected: everything is testable without engines.

import 'package:flutter/foundation.dart';

class BargeInDetector {
  BargeInDetector({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.now());

  /// Provider confidence an incoming transcript needs to count as evidence.
  /// Null confidence ("unknown", not "zero") does not disqualify — the
  /// native fallback never reports one and must not lose barge-in entirely.
  static const double minConfidence = 0.55;

  /// Minimum word count in the transcript evidence.
  static const int minWords = 1;

  /// Token-set similarity at or above which a transcript is judged to be
  /// the assistant's own words coming back (echo), not the user.
  static const double echoSimilarityLimit = 0.85;

  /// Transcripts arriving this soon after playback stopped are discarded:
  /// they are almost always the tail of the assistant's own audio.
  static const Duration postTtsDiscardWindow = Duration(milliseconds: 250);

  /// How many recent assistant sentences are kept as the echo fingerprint.
  static const int _fingerprintDepth = 3;

  final DateTime Function() _clock;

  /// Normalized text of the most recently spoken assistant sentences — the
  /// echo fingerprint. Bounded: only the last few sentences can still be
  /// audibly bleeding into the mic.
  final List<String> _assistantFingerprints = [];

  /// When the assistant's playback last stopped, for the discard window.
  DateTime? _assistantStoppedAt;

  /// Whether an accepted transcript (confident, non-echo, in-window) has
  /// been seen since the last reset.
  bool _transcriptEvidence = false;
  String acceptedTranscript = '';

  /// One-shot latch: barge-in fires once per reset cycle.
  bool _fired = false;

  /// The assistant started saying [sentence]. Feeds the echo fingerprint.
  /// Also clears any playback-stopped discard window: while audio flows,
  /// transcripts are judged on confidence and similarity alone.
  void onAssistantSpeechStarted(String sentence) {
    final normalized = _normalize(sentence);
    if (normalized.isEmpty) return;
    _assistantFingerprints.add(normalized);
    if (_assistantFingerprints.length > _fingerprintDepth) {
      _assistantFingerprints.removeAt(0);
    }
    _assistantStoppedAt = null;
    _fired = false;
  }

  /// The assistant's playback stopped (queue drained or audio halted):
  /// starts the post-TTS discard window.
  void onAssistantSpeechStopped() {
    _assistantStoppedAt = _clock();
  }

  /// One transcript frame captured while the assistant speaks — interim or
  /// final alike: interims react faster, and the quality gates below already
  /// reject noise. Accepts it as barge-in evidence only when every gate
  /// passes. Cheap: returns early on the first disqualifier.
  void onUserTranscript({required String text, double? confidence}) {
    if (_fired) return;

    // The provider itself was unsure of these words.
    if (confidence != null && confidence < minConfidence) return;

    final words = _normalize(text).split(' ');
    if (words.where((w) => w.isNotEmpty).length < minWords) return;

    // The tail of the assistant's own playback transcribing right after
    // TTS stopped.
    final stoppedAt = _assistantStoppedAt;
    if (stoppedAt != null &&
        _clock().difference(stoppedAt) < postTtsDiscardWindow) {
      return;
    }

    // The assistant's own words bouncing back from the speaker. Allow short
    // interruption commands even if the assistant sentence contains them.
    final normalizedText = _normalize(text);
    const interruptCues = {
      'stop', 'wait', 'pause', 'hold on', 'no', 'hey', 'enough',
      'dur', 'bekle', 'yeter', 'hayır', 'hayir', 'kes', 'sus',
      'devam', 'tamam', 'bırak', 'birak',
    };
    final isInterruptCue = interruptCues.contains(normalizedText);
    for (final fingerprint in _assistantFingerprints) {
      final isSingleWordEcho =
          words.length == 1 && fingerprint.split(' ').contains(normalizedText);
      if (!isInterruptCue &&
          (echoSimilarity(text, fingerprint) >= echoSimilarityLimit ||
              isSingleWordEcho)) {
        return;
      }
    }

    _transcriptEvidence = true;
    acceptedTranscript = text;
  }

  /// Whether the accumulated evidence means "the user is talking over the
  /// assistant". One-shot: latches until [reset].
  bool get shouldBargeIn {
    if (_fired) return false;
    if (!_transcriptEvidence) return false;
    // STT only emits structured transcripts after recognizing speech. Do not
    // additionally gate on mic-level samples; some device audio stacks report
    // zero while TTS is active, which otherwise prevents all interruptions.
    _fired = true;
    return true;
  }

  /// Full reset — a new session, a completed interrupt, a state where the
  /// detector no longer applies.
  void reset() {
    _assistantFingerprints.clear();
    _assistantStoppedAt = null;
    _transcriptEvidence = false;
    acceptedTranscript = '';
    _fired = false;
  }

  /// Token-set similarity between two utterances, 0..1 (Jaccard over the
  /// normalized word sets). Pure and exposed for tests.
  @visibleForTesting
  static double echoSimilarity(String candidate, String spoken) {
    final setA = _normalize(candidate)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toSet();
    final setB = _normalize(spoken)
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toSet();
    if (setA.isEmpty || setB.isEmpty) return 0.0;
    final union = setA.union(setB).length;
    return union == 0 ? 0.0 : setA.intersection(setB).length / union;
  }

  /// Lowercase, alphanumeric words only (Turkish letters included).
  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .trim();
  }
}
