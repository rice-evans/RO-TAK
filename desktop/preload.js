const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('rotak', {
  send: channel => {
    if (channel === 'drag-start' || channel === 'drag-end') ipcRenderer.send(channel);
  },
  onLocked: callback => {
    ipcRenderer.on('locked', (event, locked) => callback(!!locked));
  },
  onUpdate: callback => {
    ipcRenderer.on('update', (event, u) => {
      if (u && (u.state === 'ready' || u.state === 'available') && typeof u.version === 'string') callback({ state: u.state, version: u.version.slice(0, 20), url: typeof u.url === 'string' ? u.url : '' });
    });
  },
  installUpdate: () => {
    ipcRenderer.send('update-install');
  },
  openExternal: url => {
    ipcRenderer.send('open-external', String(url));
  },
});
