const { app, BrowserWindow, globalShortcut, ipcMain, screen, shell } = require('electron');
const path = require('path');

const BASE_W = 860;
const BASE_H = 600;

let win;
let scale = 1;
let opacity = 1;
let locked = false;

function applyScale(s) {
  scale = Math.min(2, Math.max(0.4, Math.round(s * 100) / 100));
  win.setContentSize(Math.round(BASE_W * scale), Math.round(BASE_H * scale));
  win.webContents.setZoomFactor(scale);
}

function setLocked(v) {
  locked = v;
  win.setIgnoreMouseEvents(locked, { forward: true });
  win.webContents.send('locked', locked);
}

let dragTimer = null;
ipcMain.on('drag-start', () => {
  clearInterval(dragTimer);
  const start = screen.getCursorScreenPoint();
  const b = win.getBounds();
  dragTimer = setInterval(() => {
    const p = screen.getCursorScreenPoint();
    win.setBounds({ x: b.x + p.x - start.x, y: b.y + p.y - start.y, width: b.width, height: b.height });
  }, 8);
});
ipcMain.on('drag-end', () => clearInterval(dragTimer));
ipcMain.on('open-external', (event, url) => {
  if (!win || event.sender !== win.webContents) return;
  try {
    const u = new URL(url);
    if (u.protocol === 'https:' || u.protocol === 'http:') shell.openExternal(u.href);
  } catch (e) {}
});

function createWindow() {
  const area = screen.getPrimaryDisplay().workArea;

  win = new BrowserWindow({
    width: BASE_W,
    height: BASE_H,
    x: area.x + 20,
    y: area.y + area.height - BASE_H - 20,
    transparent: true,
    frame: false,
    resizable: false,
    hasShadow: false,
    alwaysOnTop: true,
    backgroundColor: '#00000000',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
      webSecurity: true,
      preload: path.join(__dirname, 'preload.js'),
    },
  });

  win.setAlwaysOnTop(true, 'screen-saver');
  if (process.platform === 'darwin') {
    win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  }

  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', event => event.preventDefault());
  win.loadFile('index.html');
  win.webContents.on('did-finish-load', () => {
    win.webContents.setZoomFactor(scale);
    win.webContents.send('locked', locked);
  });

  globalShortcut.register('CommandOrControl+Shift+A', () => setLocked(!locked));

  globalShortcut.register('CommandOrControl+Shift+H', () => {
    if (win.isVisible()) win.hide();
    else win.showInactive();
  });

  globalShortcut.register('CommandOrControl+Shift+Up', () => applyScale(scale + 0.1));
  globalShortcut.register('CommandOrControl+Shift+Down', () => applyScale(scale - 0.1));

  globalShortcut.register('CommandOrControl+Shift+Left', () => {
    opacity = Math.max(0.3, Math.round((opacity - 0.1) * 10) / 10);
    win.setOpacity(opacity);
  });
  globalShortcut.register('CommandOrControl+Shift+Right', () => {
    opacity = Math.min(1, Math.round((opacity + 0.1) * 10) / 10);
    win.setOpacity(opacity);
  });

  globalShortcut.register('CommandOrControl+Shift+Q', () => app.quit());
}

app.whenReady().then(createWindow);
app.on('window-all-closed', () => app.quit());
app.on('will-quit', () => globalShortcut.unregisterAll());
