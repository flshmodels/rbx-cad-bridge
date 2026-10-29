'use strict';
const fs = require('node:fs');
const { createClient } = require('./relay-client.cjs');

// Install in the local Electron shell. main-remote.js has no CommonJS require.
function install({ app, ipcMain, getMainWindow, configPath }) {
  if (!fs.existsSync(configPath)) return;
  const request = createClient(JSON.parse(fs.readFileSync(configPath, 'utf8')));
  let context = { session: '', authenticated: false };
  let revision = 0;
  const reset = () => { context = { session: '', authenticated: false }; revision++; };
  const trusted = event => {
    const win = getMainWindow();
    return win && !win.isDestroyed() && event.sender === win.webContents && event.senderFrame === win.webContents.mainFrame;
  };
  ipcMain.on('cad-bridge:context', (event, payload) => {
    if (!trusted(event)) return;
    reset();
    context = {
      session: typeof payload?.session === 'string' && /^[A-Za-z0-9_-]{1,100}$/.test(payload.session) ? payload.session : '',
      authenticated: payload?.authenticated === true
    };
  });
  app.on('web-contents-created', (_event, contents) => {
    contents.on('did-start-navigation', (_e, _url, _inPlace, isMainFrame) => {
      if (isMainFrame && getMainWindow()?.webContents === contents) reset();
    });
    contents.on('render-process-gone', () => { if (getMainWindow()?.webContents === contents) reset(); });
  });
  ipcMain.handle('cad-bridge:snapshot', async event => {
    if (!trusted(event)) throw Error('Untrusted CAD window');
    const win = getMainWindow();
    if (!win || win.isDestroyed() || !context.authenticated || !context.session) throw Error('Log into the CAD and select an authorized session');
    const before = revision, session = context.session;
    const data = await request(session, 'snapshot');
    if (revision !== before || win.isDestroyed()) throw Error('Session changed; discard this snapshot');
    return data;
  });
}
module.exports = { install };
