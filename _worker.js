// LeadSniper Cloudflare Edge Worker
// Serves static assets and provides edge API endpoints

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Serve static assets via Cloudflare Assets binding
    if (env.ASSETS) {
      return await env.ASSETS.fetch(request);
    }

    return new Response('LeadSniper Edge Ready', { status: 200 });
  }
};
