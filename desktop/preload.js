const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('rotak', {
  send: channel => {
    if (channel === 'drag-start' || channel === 'drag-end') ipcRenderer.send(channel);
  },
  onLocked: callback => {
    ipcRenderer.on('locked', (event, locked) => callback(!!locked));
  },
  openExternal: url => {
    ipcRenderer.send('open-external', String(url));
  },
});
