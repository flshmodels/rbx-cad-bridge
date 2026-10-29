'use strict';

const { createClient } = require('./relay-client.cjs');
const { mapToCad } = require('./map-to-cad.cjs');

async function main() {
  const [flag, file, ...extra] = process.argv.slice(2);
  let snapshot;
  if (flag === '--file' && file && !extra.length) {
    // Offline example: no credentials, Roblox installation, or network required.
    snapshot = JSON.parse(require('node:fs').readFileSync(file, 'utf8'));
  } else if (flag === undefined) {
    const session = process.env.CAD_SESSION_ID;
    if (!session || !process.env.CAD_RELAY_URL || !process.env.CAD_READ_TOKEN) {
      throw Error('Set CAD_SESSION_ID, CAD_RELAY_URL, and CAD_READ_TOKEN, or use --file examples/snapshot.json');
    }
    const read = createClient({ relayUrl: process.env.CAD_RELAY_URL, sessions: { [session]: process.env.CAD_READ_TOKEN } });
    snapshot = await read(session, 'snapshot');
  } else throw Error('Usage: node examples/read-snapshot.cjs [--file examples/snapshot.json]');
  console.log(JSON.stringify(mapToCad(snapshot), null, 2));
}

if (require.main === module) main().catch(() => {
  console.error('Example could not read/map a snapshot. Check the file or relay configuration; see docs/ADAPTING.md.');
  process.exitCode = 1;
});
module.exports = { main };
