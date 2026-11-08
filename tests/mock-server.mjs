import { appendFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';

const portFile = process.env.PORT_FILE;
const requestLog = process.env.REQUEST_LOG;

if (!portFile || !requestLog) {
  throw new Error('PORT_FILE and REQUEST_LOG are required');
}

let rolloutRequests = 0;

function serveDeployedApp(request, response) {
  if (request.url === '/app/version.json') {
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ app: { version: '1.2.3' } }));
    return true;
  }
  if (request.url === '/app/version.txt') {
    response.writeHead(200, { 'Content-Type': 'text/plain' });
    response.end('  1.2.3\r\nbuild 42\n');
    return true;
  }
  // Reports the previous version for the first two requests.
  if (request.url === '/app/rollout.json') {
    rolloutRequests += 1;
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ version: rolloutRequests > 2 ? '1.2.3' : '1.2.2' }));
    return true;
  }
  return false;
}

const server = createServer((request, response) => {
  if (request.method === 'GET' && serveDeployedApp(request, response)) return;

  const chunks = [];
  request.on('data', (chunk) => {
    chunks.push(chunk);
  });
  request.on('end', () => {
    if (request.method !== 'POST' || request.headers.authorization !== 'Bearer test-token') {
      response.writeHead(401, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ message: 'Unauthorized' }));
      return;
    }

    if (request.url === '/api/v1/integrations/sboms') {
      // Multipart: text fields are logged, the gzip file is checked by its magic bytes.
      const raw = Buffer.concat(chunks);
      const text = raw.toString('latin1');
      const field = (name) => text.match(new RegExp(`name="${name}"\\r\\n\\r\\n([^\\r]*)\\r\\n`))?.[1] ?? null;
      const fileStart = text.indexOf('\r\n\r\n', text.indexOf('name="file"')) + 4;
      const gzip = raw[fileStart] === 0x1f && raw[fileStart + 1] === 0x8b;
      const body = { alias: field('alias'), version: field('version'), part: field('part'), gzip };
      appendFileSync(requestLog, `${JSON.stringify({ path: request.url, body })}\n`);
      response.writeHead(201, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ id: 'sbom-1', componentCount: 2 }));
      return;
    }

    const rawBody = Buffer.concat(chunks).toString('utf8');
    let body;
    try {
      body = JSON.parse(rawBody);
    } catch {
      response.writeHead(400, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ message: 'Invalid JSON' }));
      return;
    }

    appendFileSync(requestLog, `${JSON.stringify({ path: request.url, body })}\n`);

    if (request.url === '/api/v1/integrations/versions') {
      response.writeHead(201, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ id: 'version-1', ...body }));
      return;
    }

    if (request.url === '/api/v1/integrations/installations') {
      response.writeHead(201, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ id: 'installation-1', ...body }));
      return;
    }

    response.writeHead(404, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify({ message: 'Not found' }));
  });
});

server.listen(0, '127.0.0.1', () => {
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Unexpected server address');
  writeFileSync(portFile, String(address.port));
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
