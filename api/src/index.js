/**
 * 노들길 근무기록 — 동기화 API
 * GET  /data            -> { v, data }        현재 저장된 전체 데이터
 * PUT  /data { data, base } -> { v }          base 가 최신이 아니면 409 + 최신 데이터
 * 인증: X-Pass 헤더 == PASSCODE (wrangler secret)
 */

const ROW = 'main';

const cors = (origin) => ({
  'Access-Control-Allow-Origin': origin || '*',
  'Access-Control-Allow-Methods': 'GET,PUT,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,X-Pass',
  'Access-Control-Max-Age': '86400',
  'Vary': 'Origin',
});

const json = (body, status, headers) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...headers, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  });

async function readRow(env) {
  const row = await env.DB.prepare('SELECT data, updated FROM store WHERE id = ?').bind(ROW).first();
  return row ? { v: row.updated, data: JSON.parse(row.data) } : { v: 0, data: null };
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin');
    const h = cors(origin);

    if (request.method === 'OPTIONS') return new Response(null, { headers: h });

    const url = new URL(request.url);
    if (url.pathname !== '/data') return json({ error: 'not found' }, 404, h);

    if (!env.PASSCODE || (request.headers.get('X-Pass') || '') !== env.PASSCODE) {
      return json({ error: 'unauthorized' }, 401, h);
    }

    await env.DB.prepare(
      'CREATE TABLE IF NOT EXISTS store (id TEXT PRIMARY KEY, data TEXT NOT NULL, updated INTEGER NOT NULL)'
    ).run();

    if (request.method === 'GET') {
      return json(await readRow(env), 200, h);
    }

    if (request.method === 'PUT') {
      let body;
      try { body = await request.json(); } catch { return json({ error: 'bad json' }, 400, h); }

      const cur = await readRow(env);
      // 낙관적 동시성 제어: 다른 기기가 먼저 저장했으면 409
      if (typeof body.base === 'number' && body.base !== cur.v) {
        return json({ error: 'conflict', ...cur }, 409, h);
      }

      const v = Date.now();
      await env.DB.prepare(
        `INSERT INTO store (id, data, updated) VALUES (?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated = excluded.updated`
      ).bind(ROW, JSON.stringify(body.data ?? {}), v).run();

      return json({ v }, 200, h);
    }

    return json({ error: 'method not allowed' }, 405, h);
  },
};
