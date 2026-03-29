import "dotenv/config";
import cors from "cors";
import express from "express";

const app = express();
app.use(cors());
app.use(express.json({ limit: "64kb" }));

const PORT = Number(process.env.PORT || 3000);

const GROQ_API_KEY = process.env.GROQ_API_KEY?.trim();
const GROQ_MODEL =
  (process.env.GROQ_MODEL || "").trim() || "llama-3.3-70b-versatile";
const GROQ_BASE = (process.env.GROQ_API_BASE || "https://api.groq.com/openai/v1").replace(
  /\/$/,
  "",
);

const GROK_API_KEY = process.env.GROK_API_KEY?.trim();
const GROK_MODEL = (process.env.GROK_MODEL || "").trim() || "grok-2-latest";
const GROK_BASE = (process.env.GROK_API_BASE || "https://api.x.ai/v1").replace(/\/$/, "");

function resolveLlm() {
  if (GROQ_API_KEY) {
    return {
      provider: "groq",
      apiKey: GROQ_API_KEY,
      model: GROQ_MODEL,
      base: GROQ_BASE,
      label: "Groq",
    };
  }
  if (GROK_API_KEY) {
    return {
      provider: "xai",
      apiKey: GROK_API_KEY,
      model: GROK_MODEL,
      base: GROK_BASE,
      label: "xAI Grok",
    };
  }
  return null;
}

app.get("/health", (_req, res) => {
  const llm = resolveLlm();
  res.json({
    ok: true,
    llm: llm
      ? { provider: llm.provider, model: llm.model }
      : { configured: false },
  });
});

app.post("/api/plan", async (req, res) => {
  const llm = resolveLlm();
  if (!llm) {
    res.status(500).json({
      error:
        "No LLM API key: set GROQ_API_KEY (Groq) or GROK_API_KEY (xAI) in environment",
    });
    return;
  }

  const features = req.body?.features;
  if (!features || typeof features !== "object") {
    res.status(400).json({ error: "Body must include { features: { ... } }" });
    return;
  }

  const system = `You are a supportive wellness coach for a product called "Phone Life AI".
The app estimates sleep, stress, and activity from **phone behavior only** (screen patterns, app switching, steps, delivery-app opens). This is NOT medical data and you must NOT diagnose or claim clinical accuracy.

Write ONE short "Today's plan" for the user in plain language (150–280 words max). Structure:
1) One friendly opening line acknowledging their pattern (no shame).
2) 3–5 bullet points with concrete, time-bound actions for today (walk, caffeine cutoff, wind-down, hydration, focus block, etc.).
3) One closing line reinforcing autonomy.

Rules:
- No creepy tone; no "we are watching you".
- If scores look like missing data (e.g. zeros everywhere), say estimates are limited and suggest enabling usage access / motion permissions.
- Tie recommendations to the numeric signals you receive (sleepHoursEstimate, nightScreenMinutes, appSwitchCount24h, stepsToday, foodDeliveryOpens24h).
- Do not invent precise sleep times unless provided approximately via fields.`;

  const user = `Here is today's aggregated behavior summary (JSON). Use it to personalize the plan:\n${JSON.stringify(features)}`;

  try {
    const apiRes = await fetch(`${llm.base}/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${llm.apiKey}`,
      },
      body: JSON.stringify({
        model: llm.model,
        messages: [
          { role: "system", content: system },
          { role: "user", content: user },
        ],
        temperature: 0.65,
        max_tokens: 700,
      }),
    });

    const raw = await apiRes.text();
    if (!apiRes.ok) {
      res.status(502).json({
        error: `${llm.label} API error`,
        detail: raw,
      });
      return;
    }

    const data = JSON.parse(raw);
    const plan = data?.choices?.[0]?.message?.content?.trim();
    if (!plan) {
      res.status(502).json({ error: "Empty model response", detail: raw });
      return;
    }

    res.json({ plan });
  } catch (e) {
    res.status(500).json({ error: String(e?.message || e) });
  }
});

app.listen(PORT, () => {
  const llm = resolveLlm();
  console.log(`Phone Life AI API on http://localhost:${PORT}`);
  if (llm) {
    console.log(`LLM: ${llm.label} — model "${llm.model}"`);
  } else {
    console.warn("LLM: not configured (set GROQ_API_KEY or GROK_API_KEY)");
  }
});
