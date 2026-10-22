const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const WEB_DIR = path.resolve(__dirname, '../build/web');

const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
};

const server = http.createServer((req, res) => {
  const cleanUrl = req.url.split('?')[0];

  // Si c'est une requête API ou Health -> envoi direct au backend Node (8787)
  if (cleanUrl.startsWith('/api/') || cleanUrl === '/health' || cleanUrl === '/__backend_health') {
    const upstream = http.request({
      hostname: '127.0.0.1',
      port: 8787,
      path: cleanUrl === '/__backend_health' ? '/health' : req.url,
      method: req.method,
      headers: { ...req.headers, host: '127.0.0.1:8787' },
    }, (backendRes) => {
      res.writeHead(backendRes.statusCode, backendRes.headers);
      backendRes.pipe(res);
    });

    upstream.on('error', () => {
      res.writeHead(502, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ code: 'BACKEND_OFFLINE' }));
    });

    req.pipe(upstream);
    return;
  }

  // Sinon -> servir les fichiers de l'application Flutter Web (build/web)
  let filePath = path.join(WEB_DIR, cleanUrl === '/' ? 'index.html' : cleanUrl);
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(WEB_DIR, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(500);
      res.end('Error loading app');
      return;
    }
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(content, 'utf-8');
  });
});

server.listen(8081, '0.0.0.0', () => {
  console.log('Serveur Movera (Web + API) en ecoute sur http://0.0.0.0:8081');
});
