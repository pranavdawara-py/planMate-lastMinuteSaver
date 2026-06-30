/// Client-side scope pre-filter for planMate AI chat.
///
/// ⚡ PERFORMANCE LAYER — not the security enforcement layer.
/// The real block/allow lists live in backend/index.js (Cloud Run server).
/// The server independently checks every request before calling Gemini,
/// so even if this client guard is bypassed, decompiled, or modified,
/// the server still rejects off-topic queries.
///
/// This client-side guard exists purely to save an HTTP round-trip:
/// obviously off-topic queries are refused instantly without a network call.
///
/// Two-layer logic (same algorithm as the server):
///   1. Short query (≤4 words) → pass (task names / quick commands)
///   2. Block-list checked FIRST
///   3. Rescue-list overrides a block-list hit (productivity keywords)
class ChatGuard {
  // Locked decision (context.md §Scope Refusal Message):
  // Exactly this string — no redirect, no explanation. Must match system_prompt.txt.
  static const String refusalMessage =
      'Unable to find anything helpful in that prompt.';

  // ── BLOCK-LIST: clearly off-topic patterns ────────────────────────────────
  // Checked FIRST. These fire only if a truly off-topic pattern is matched.
  static const List<String> _blockPatterns = [
    // Code / programming help
    r'\b(write|generate|create|build|give me|show me|make)\b.{0,40}\b(code|function|script|program|algorithm|class|method|api|snippet|html|css|javascript|python|dart|sql|regex)\b',
    r'\b(debug|fix (this|the|my)? code|what does this code do|runtime error|null pointer|stack overflow)\b',

    // Essay / creative writing
    r'\b(write|draft|compose|create|generate)\b.{0,40}\b(essay|email|letter|story|poem|article|blog|speech|cover letter|resume|cv)\b',
    r'\b(proofread|paraphrase|rewrite this|summarize this text|translate (this|to|into|from))\b',

    // General knowledge trivia
    r'\bwhat is the (capital|population|currency|president|prime minister|national dish) of\b',
    r'\b(explain|how does|how do)\b.{0,30}\b(photosynthesis|evolution|black hole|quantum|gravity|nuclear|dna|atom|climate change)\b',
    r'\bwho (is|was|invented|discovered|created)\b.{0,30}\b(einstein|newton|shakespeare|napoleon|gandhi|tesla|darwin)\b',

    // Math homework
    r'\b(solve|calculate|compute|find the value|evaluate)\b.{0,30}\b(equation|integral|derivative|matrix|polynomial|trigonometry|calculus)\b',
    r'^\s*[\d\s\+\-\*\/\^\(\)=]+\??\s*$', // pure arithmetic expression like "45 * 3 = ?"

    // Entertainment / jokes / games
    r'\b(tell me a joke|tell me a riddle|write me a joke|write me a poem|give me a joke)\b',
    r'\bplay\b.{0,20}\b(a game|chess|trivia|hangman|20 questions)\b',

    // Food / cooking
    r'\b(recipe for|how to cook|how to bake|ingredients (for|of|in)|nutrition facts|calories in)\b',

    // Media recommendations (movies, music, books — unrelated to tasks)
    r'\b(recommend (a|some|me|the best)|suggest (a|some|the best))\b.{0,30}\b(movie|show|series|book|novel|song|album|restaurant|hotel)\b',

    // Medical / legal / financial advice
    r'\b(diagnose|am I pregnant|symptoms of cancer|medical advice|is it legal to|tax advice|invest in stocks)\b',

    // Weather forecast (not planning-related)
    r'\b(what is the weather (in|at|for|today|tomorrow)|weather forecast for|will it rain in|temperature in [a-z]+)\b',
  ];

  // ── RESCUE-LIST: strong productivity keywords that override a block-list hit ─
  // If the blocked query ALSO contains one of these, it may be a legitimate task
  // management query that happens to use blocked vocabulary (e.g. "write task for my essay deadline").
  static const List<String> _rescuePatterns = [
    r'\b(task|tasks|todo|to-do|deadline|due date|reminder|reminders|schedule|session|sessions)\b',
    r'\b(add|create|set|schedule|plan)\b.{0,20}\b(task|reminder|session|deadline|block)\b',
    r'\b(my (task|deadline|reminder|schedule|session|assignment))\b',
  ];

  /// Returns null if the query is within scope (OK to send to backend).
  /// Returns [refusalMessage] if the query is clearly off-topic.
  static String? checkScope(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;

    // Short queries (≤4 words) are almost always task names or quick commands — pass through
    if (trimmed.split(RegExp(r'\s+')).length <= 4) return null;

    final lower = trimmed.toLowerCase();

    // ── Step 1: Check block-list first ───────────────────────────────────────
    bool blocked = false;
    for (final pattern in _blockPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lower)) {
        blocked = true;
        break;
      }
    }

    if (!blocked) return null; // Not off-topic — pass through

    // ── Step 2: Check if a strong productivity keyword rescues it ────────────
    // e.g. "write a task for my essay deadline" hits "write+essay" block
    // but "task" and "deadline" rescue it → pass through
    for (final pattern in _rescuePatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(lower)) {
        return null; // Rescued — productivity intent overrides
      }
    }

    // Blocked and not rescued — refuse
    return refusalMessage;
  }
}
