// LeadSniper Cloudflare Edge Worker
// Serves static assets and provides REAL LIVE Reddit & HackerNews streaming APIs

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // 1. Live Reddit Feed API
    if (url.pathname === '/api/reddit') {
      const sub = url.searchParams.get('sub') || 'SaaS+SideProject+startups';
      const cleanSub = sub.replace(/^r\//, '');
      const redditUrl = `https://www.reddit.com/r/${cleanSub}/new.json?limit=25`;

      try {
        const resp = await fetch(redditUrl, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 LeadSniper/2.0'
          }
        });

        if (!resp.ok) {
          return new Response(JSON.stringify({ error: `Reddit returned status ${resp.status}`, fallback: true }), {
            status: 200,
            headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
          });
        }

        const data = await resp.json();
        const children = (data && data.data && data.data.children) || [];

        const posts = children.map(c => {
          const p = c.data;
          return {
            sub: `r/${p.subreddit}`,
            title: p.title,
            body: p.selftext || p.title,
            author: `u/${p.author}`,
            score: p.score || 1,
            num_comments: p.num_comments || 0,
            created_utc: p.created_utc,
            permalink: `https://www.reddit.com${p.permalink}`,
            url: p.url,
            is_self: p.is_self
          };
        });

        return new Response(JSON.stringify({ success: true, count: posts.length, posts }), {
          status: 200,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Cache-Control': 'public, max-age=30'
          }
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message, fallback: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      }
    }

    // 2. Live HackerNews Feed API
    if (url.pathname === '/api/hn') {
      try {
        const hnIdsResp = await fetch('https://hacker-news.firebaseio.com/v0/askstories.json');
        const ids = (await hnIdsResp.json()).slice(0, 15);

        const items = await Promise.all(
          ids.map(async id => {
            const itemResp = await fetch(`https://hacker-news.firebaseio.com/v0/item/${id}.json`);
            return await itemResp.json();
          })
        );

        const posts = items.filter(Boolean).map(item => ({
          sub: 'Ask HN',
          title: item.title,
          body: (item.text || item.title).replace(/<[^>]*>?/gm, ''), // strip HTML tags
          author: `@${item.by}`,
          score: item.score || 1,
          num_comments: item.descendants || 0,
          created_utc: item.time,
          permalink: `https://news.ycombinator.com/item?id=${item.id}`,
          url: item.url || `https://news.ycombinator.com/item?id=${item.id}`
        }));

        return new Response(JSON.stringify({ success: true, count: posts.length, posts }), {
          status: 200,
          headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Cache-Control': 'public, max-age=60'
          }
        });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message, fallback: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' }
        });
      }
    }

    // 3. Serve static assets via Cloudflare Assets binding
    if (env.ASSETS) {
      return await env.ASSETS.fetch(request);
    }

    return new Response('LeadSniper Edge Ready', { status: 200 });
  }
};
