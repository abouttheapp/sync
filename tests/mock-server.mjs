import { appendFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';

const portFile = process.env.PORT_FILE;
const requestLog = process.env.REQUEST_LOG;

if (!portFile || !requestLog) {
  throw new Error('PORT_FILE and REQUEST_LOG are required');
}

const server = createServer((request, response) => {
  let rawBody = '';
  request.setEncoding('utf8');
  request.on('data', (chunk) => {
    rawBody += chunk;
  });
  request.on('end', () => {
    if (request.method !== 'POST' || request.headers.authorization !== 'Bearer test-token') {
      response.writeHead(401, { 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ message: 'Unauthorized' }));
      return;
    }

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
