require('dotenv').config();
const express = require('express');
const cors = require('cors');
const axios = require('axios');
const rateLimit = require('express-rate-limit');
const fs = require('fs');
const path = require('path');

const app = express();

// ─────────────────────────────────────────────────────────────────────────────
// Trust proxy headers (required for Cloud Run / load balancers)
// ─────────────────────────────────────────────────────────────────────────────
app.set('trust proxy', 1);

app.use(express.json({ limit: '512kb' }));

// Basic security headers (no helmet dependency — manual)
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  next();
});

// ─────────────────────────────────────────────────────────────────────────────
// Server-side ChatGuard — second line of defence even if Flutter client is bypassed
// ─────────────────────────────────────────────────────────────────────────────
const GUARD_REFUSAL = 'Unable to find anything helpful in that prompt.';

const BLOCK_PATTERNS = [
  /\b(write|generate|create|build|give me|show me|make)\b.{0,40}\b(code|function|script|program|algorithm|class|method|api|snippet|html|css|javascript|python|dart|sql|regex)\b/i,
  /\b(debug|fix (this|the|my)? code|what does this code do|runtime error|null pointer|stack overflow)\b/i,
  /\b(write|draft|compose|create|generate)\b.{0,40}\b(essay|email|letter|story|poem|article|blog|speech|cover letter|resume|cv)\b/i,
  /\b(proofread|paraphrase|rewrite this|summarize this text|translate (this|to|into|from))\b/i,
  /\bwhat is the (capital|population|currency|president|prime minister|national dish) of\b/i,
  /\b(explain|how does|how do)\b.{0,30}\b(photosynthesis|evolution|black hole|quantum|gravity|nuclear|dna|atom|climate change)\b/i,
  /\bwho (is|was|invented|discovered|created)\b.{0,30}\b(einstein|newton|shakespeare|napoleon|gandhi|tesla|darwin)\b/i,
  /\b(solve|calculate|compute|find the value|evaluate)\b.{0,30}\b(equation|integral|derivative|matrix|polynomial|trigonometry|calculus)\b/i,
  /^\s*[\d\s\+\-\*\/\^\(\)=]+\??\s*$/,
  /\b(tell me a joke|tell me a riddle|write me a joke|write me a poem|give me a joke)\b/i,
  /\bplay\b.{0,20}\b(a game|chess|trivia|hangman|20 questions)\b/i,
  /\b(recipe for|how to cook|how to bake|ingredients (for|of|in)|nutrition facts|calories in)\b/i,
  /\b(recommend (a|some|me|the best)|suggest (a|some|the best))\b.{0,30}\b(movie|show|series|book|novel|song|album|restaurant|hotel)\b/i,
  /\b(diagnose|am I pregnant|symptoms of cancer|medical advice|is it legal to|tax advice|invest in stocks)\b/i,
  /\b(what is the weather (in|at|for|today|tomorrow)|weather forecast for|will it rain in|temperature in [a-z]+)\b/i,
];

const RESCUE_PATTERNS = [
  /\b(task|tasks|todo|to-do|deadline|due date|reminder|reminders|schedule|session|sessions)\b/i,
  /\b(add|create|set|schedule|plan)\b.{0,20}\b(task|reminder|session|deadline|block)\b/i,
  /\b(my (task|deadline|reminder|schedule|session|assignment))\b/i,
];

function serverGuard(query) {
  if (!query || typeof query !== 'string') return null;
  const trimmed = query.trim();
  if (trimmed.split(/\s+/).length <= 4) return null;
  const blocked = BLOCK_PATTERNS.some((p) => p.test(trimmed));
  if (!blocked) return null;
  const rescued = RESCUE_PATTERNS.some((p) => p.test(trimmed));
  return rescued ? null : GUARD_REFUSAL;
}

// ─────────────────────────────────────────────────────────────────────────────
// CORS — restrict to known origins + any ALLOWED_ORIGIN set via env var
// On Cloud Run set: ALLOWED_ORIGIN=https://your-project.web.app
// ─────────────────────────────────────────────────────────────────────────────
const buildAllowedOrigins = () => {
  const base = [
    'http://localhost',
    'http://localhost:8080',
    'http://localhost:8000',
    'http://localhost:5000',
    'http://127.0.0.1',
  ];
  // Support comma-separated list of origins (e.g. Cloud Run + Firebase Hosting)
  const extra = process.env.ALLOWED_ORIGIN;
  if (extra) {
    extra.split(',').forEach((o) => {
      const trimmed = o.trim();
      if (trimmed) base.push(trimmed);
    });
  }
  return base;
};

app.use(
  cors({
    origin(origin, callback) {
      // Allow requests with no Origin header (mobile apps, curl, Postman, Cloud Run health checks)
      if (!origin) {
        callback(null, true);
        return;
      }
      const allowedOrigins = buildAllowedOrigins();
      const allowed = allowedOrigins.some(
        (entry) => origin === entry || origin.startsWith(`${entry}:`),
      );
      if (allowed) {
        callback(null, true);
      } else {
        // Log CORS rejections for debugging (don't expose to client)
        console.warn(`CORS rejected: ${origin}`);
        callback(new Error(`Origin not allowed`));
      }
    },
    credentials: true,
  }),
);

// ─────────────────────────────────────────────────────────────────────────────
// Rate limiting — tuned for mobile (60 req/min; generous for AI chatbot usage)
// ─────────────────────────────────────────────────────────────────────────────
const limiter = rateLimit({
  windowMs: 60 * 1000,      // 1 minute window
  max: 60,                   // 60 requests per minute per IP
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
  // Skip rate limiting for health check endpoint
  skip: (req) => req.path === '/',
});
app.use('/chat', limiter);

// ─────────────────────────────────────────────────────────────────────────────
// Load system prompt from file
// ─────────────────────────────────────────────────────────────────────────────
let baseSystemPrompt = '';
try {
  baseSystemPrompt = fs.readFileSync(path.join(__dirname, 'system_prompt.txt'), 'utf8');
} catch (err) {
  console.error('Warning: Could not read system_prompt.txt:', err.message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Health check
// ─────────────────────────────────────────────────────────────────────────────
app.get('/', (req, res) => {
  res.json({ status: 'planMate Gemini proxy is running', version: '2.0' });
});

// ─────────────────────────────────────────────────────────────────────────────
// Chat endpoint
// ─────────────────────────────────────────────────────────────────────────────
app.post('/chat', async (req, res) => {
  try {
    const { messages, appState } = req.body;

    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: 'Invalid request format' });
    }

    // Reject oversized payloads before calling Gemini
    const payloadSize = JSON.stringify(req.body).length;
    if (payloadSize > 400_000) {
      return res.status(413).json({
        error: 'Context too large — please clear chat history and try again.',
      });
    }

    if (messages.length > 50) {
      return res.status(400).json({ error: 'Too many messages in context.' });
    }

    // Server-side scope guard
    const lastUserMsg = [...messages].reverse().find((m) => m.role === 'user');
    if (lastUserMsg) {
      const refusal = serverGuard(lastUserMsg.content ?? '');
      if (refusal) {
        return res.json({
          message: refusal,
          requires_confirmation: false,
          actions: [],
          proactive_hint: null,
        });
      }
    }

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
      console.error('GEMINI_API_KEY is not configured');
      return res.status(500).json({
        error: 'AI service is not configured. Please contact support.',
      });
    }

    const contents = messages.map((msg) => ({
      role: msg.role === 'model' ? 'model' : 'user',
      parts: [{ text: msg.content }],
    }));

    const currentDatetime = appState?.current_datetime || new Date().toISOString();
    let finalSystemPrompt = baseSystemPrompt.replace('{{CURRENT_DATETIME}}', currentDatetime);

    if (appState) {
      finalSystemPrompt += '\n\n<app_state>\n' + JSON.stringify(appState, null, 2) + '\n</app_state>';
    }

    const geminiRequest = {
      systemInstruction: {
        parts: [{ text: finalSystemPrompt }],
      },
      contents,
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 4096,
        responseMimeType: 'application/json',
      },
    };

    const response = await axios.post(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${apiKey}`,
      geminiRequest,
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: 45000,  // 45 second timeout (Cloud Run default is 60s)
      },
    );

    const content = response.data?.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!content) {
      console.error('Empty response from Gemini:', JSON.stringify(response.data));
      return res.status(500).json({ error: 'Empty response from AI service' });
    }

    let parsedResponse;
    try {
      const cleaned = content.replace(/```json|```/g, '').trim();
      parsedResponse = JSON.parse(cleaned);
    } catch (parseErr) {
      // If Gemini returned non-JSON, wrap it as a plain message
      parsedResponse = {
        message: content,
        requires_confirmation: false,
        actions: [],
        proactive_hint: null,
      };
    }

    res.json(parsedResponse);
  } catch (error) {
    const status = error.response?.status;
    const data = error.response?.data;

    if (status === 429) {
      console.warn('Gemini quota exceeded');
      return res.status(429).json({
        error: 'AI service is busy right now. Please try again in a moment.',
      });
    }

    if (status === 400) {
      console.error('Gemini bad request:', data);
      return res.status(400).json({
        error: 'Could not process your message. Please try rephrasing.',
      });
    }

    if (error.code === 'ECONNABORTED' || error.message?.includes('timeout')) {
      return res.status(504).json({
        error: 'AI service timed out. Please try again.',
      });
    }

    console.error('Gemini API error:', data || error.message);
    res.status(500).json({ error: 'AI service temporarily unavailable.' });
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Global error handler
// ─────────────────────────────────────────────────────────────────────────────
app.use((err, req, res, _next) => {
  // CORS errors come through here
  if (err.message === 'Origin not allowed') {
    return res.status(403).json({ error: 'CORS: origin not permitted' });
  }
  console.error('Unhandled error:', err.message);
  res.status(500).json({ error: 'Internal server error' });
});

// ─────────────────────────────────────────────────────────────────────────────
// Start
// ─────────────────────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`planMate Gemini proxy running on port ${PORT}`);
  console.log(`System prompt: ${baseSystemPrompt.length > 0 ? 'loaded' : 'MISSING'}`);
});
