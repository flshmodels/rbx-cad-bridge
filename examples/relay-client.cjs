// Backend-side CAD reader example. Keep tokens out of browser/client bundles.
'use strict';

function validateConfig(config) {
  const url = new URL(config.relayUrl);
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/') throw Error('relayUrl must be an origin, without a path or credentials');
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname))) throw Error('Use HTTPS, or HTTP loopback for local tests');
  if (!config.sessions || typeof config.sessions !== 'object') throw Error('Configure session CAD tokens');
  for (const [session, token] of Object.entries(config.sessions)) {
    if (!/^[A-Za-z0-9_-]{1,100}$/.test(session) || typeof token !== 'string' || token.length < 32 || /\s/.test(token)) throw Error('Invalid session or CAD token');
  }
  return url.origin;
}

function createClient(config) {
  const origin = validateConfig(config);
  return async function request(session, route) {
    if (route !== 'snapshot') throw Error('The CAD bridge only reads Roblox snapshots');
    if (!Object.hasOwn(config.sessions, session)) throw Error('This session is not configured for the bridge');
    const response = await fetch(`${origin}/v1/sessions/${session}/${route}`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${config.sessions[session]}`, 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(8000),
      redirect: 'error'
    });
    const data = await response.json();
    if (!response.ok) throw Error(data.error || `Relay returned HTTP ${response.status}`);
    return data;
  };
}

module.exports = { createClient, validateConfig };
