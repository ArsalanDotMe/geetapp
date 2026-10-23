export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (!path.startsWith('/discover/')) return env.ASSETS.fetch(request);
    if (!['GET', 'HEAD'].includes(request.method)) {
      return new Response('Method not allowed', { status: 405, headers: { Allow: 'GET, HEAD' } });
    }
    const object = await env.DISCOVER.get(path.slice(1));
    if (!object) return new Response('Not found', { status: 404 });
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('ETag', object.httpEtag);
    headers.set('Cache-Control', 'public, max-age=300');
    headers.set('X-Content-Type-Options', 'nosniff');
    if (request.headers.get('If-None-Match')?.split(',').some(tag => tag.trim() === object.httpEtag || tag.trim() === '*')) {
      return new Response(null, { status: 304, headers });
    }
    return new Response(request.method === 'HEAD' ? null : object.body, { headers });
  }
};
