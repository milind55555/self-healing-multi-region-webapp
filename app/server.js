'use strict';

const http = require('node:http');
const os = require('node:os');

const port = Number(process.env.PORT || 3000);
const region = process.env.AWS_REGION || process.env.REGION || 'region-not-set';
const version = process.env.APP_VERSION || '1.0.0';

const server = http.createServer((req, res) => {
  const path = new URL(req.url, `http://${req.headers.host || 'localhost'}`).pathname;
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('cache-control', 'no-store');

  if (path === '/health' || path === '/ready') {
    res.writeHead(200);
    return res.end(JSON.stringify({ status: 'ok', region, version }));
  }

  if (path === '/') {
    res.writeHead(200);
    return res.end(JSON.stringify({
      service: 'self-healing-multiregion-webapp',
      status: 'running',
      region,
      version,
      instance: os.hostname(),
      endpoints: ['/health', '/ready']
    }, null, 2));
  }

  res.writeHead(404);
  res.end(JSON.stringify({ error: 'not_found' }));
});

server.listen(port, '0.0.0.0', () => {
  console.log(`web app listening on ${port}; region=${region}`);
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
