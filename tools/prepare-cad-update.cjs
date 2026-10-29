'use strict';

// Produces a reviewable update folder. It never writes into the installed CAD.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const args = process.argv.slice(2);
if (args.length !== 3) throw Error('Usage: node tools/prepare-cad-update.cjs <GitHub-App-folder> <index.html> <new-output-folder>');
const [shellRoot, indexFile, output] = args.map(value => path.resolve(value));
if (fs.existsSync(output)) throw Error('Output folder already exists; choose a new folder');
const mainFile = path.join(shellRoot, 'main.js');
let main = fs.readFileSync(mainFile, 'utf8');
let index = fs.readFileSync(indexFile, 'utf8');
const mainAnchor = 'let mainWindow = null;';
const indexAnchor = "const isDispatcher = (trooperSettings?.Department || selectedDepartment) === 'DISPATCHER';";
const required = ['sessionAccess[selectedUserSession]', 'selectedUserSession', 'authenticatedUser', 'tokenSaved'];
const componentAnchor = 'const WarrantDots = () => {';
const feedAnchor = '        {/* Header card — matches License Plate Search */}';
if (main.split(mainAnchor).length !== 2 || index.split(indexAnchor).length !== 2 || index.split(componentAnchor).length !== 2 || index.split(feedAnchor).length !== 2 || required.some(text => !index.includes(text))) throw Error('CAD source does not match the reviewed integration points; nothing written');
if (main.includes('bridge/electron/main.cjs') || index.includes('cad-bridge:context')) throw Error('Bridge integration is already present');
main = main.replace(mainAnchor, `${mainAnchor}

// Local-shell companion for the Roblox bridge. GitHub HTML updates cannot install this module.
try {
    require('./bridge/electron/main.cjs').install({
        app, ipcMain,
        getMainWindow: () => mainWindow,
        configPath: path.join(__dirname, 'cad-bridge.local.json')
    });
} catch (error) {
    console.error('[CadBridge] Could not initialize; check the local bridge configuration.');
}
`);
index = index.replace(indexAnchor, `${indexAnchor}

// Roblox dispatch companion follows the same login/session access checks as the duty view.
React.useEffect(() => {
    const ipc = window.electron?.ipcRenderer;
    if (!ipc) return;
    const allowed = !!authenticatedUser && tokenSaved && sessionAccess[selectedUserSession] === 'allowed';
    ipc.send('cad-bridge:context', {
        session: allowed ? selectedUserSession : '',
        authenticated: allowed
    });
    return () => ipc.send('cad-bridge:context', { session: '', authenticated: false });
}, [authenticatedUser, tokenSaved, selectedUserSession, sessionAccess]);
`);
index = index.replace(componentAnchor, fs.readFileSync(path.resolve(__dirname, '../electron/RobloxFeed.jsx'), 'utf8') + '\n\n' + componentAnchor);
index = index.replace(feedAnchor, `        <RobloxFeed key={selectedUserSession} session={selectedUserSession} allowed={!!authenticatedUser && tokenSaved && sessionAccess[selectedUserSession] === 'allowed'} />\n\n${feedAnchor}`);
fs.mkdirSync(output, { recursive: true });
fs.writeFileSync(path.join(output, 'main.js'), main);
fs.writeFileSync(path.join(output, 'index.html'), index);
fs.cpSync(path.resolve(__dirname, '../electron'), path.join(output, 'bridge/electron'), { recursive: true });
const hash = value => createHash('sha256').update(value).digest('hex');
fs.writeFileSync(path.join(output, 'SOURCE-MANIFEST.json'), JSON.stringify({
  target: 'NYSP-MDT testing#1, reviewed at fef28ab',
  sourceHashes: { main: hash(fs.readFileSync(mainFile)), index: hash(fs.readFileSync(indexFile)) },
  outputHashes: { main: hash(main), index: hash(index) },
  notes: 'main.js and bridge/ require a local-shell update. index.html can be published to testing#1. No private settings or tokens copied.'
}, null, 2));
console.log('Prepared CAD update in ' + output);
