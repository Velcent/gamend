/**
 * The dead HTML render of four public pages, unauthenticated.
 *
 * The number this exists to produce is a ratio, not an absolute: `/groups`
 * renders the same data `GET /api/v1/groups` returns, so the gap between
 * `t_page_groups` here and the group reads in `groups.js` is what the layout,
 * the template and the page's other queries cost on top of the data. Each
 * request carries its own `name` tag so the summary keeps the four apart
 * instead of averaging a 200 KB home page with a 110 KB blog post.
 *
 * This is the first GET and nothing else. It does **not** open the LiveView
 * socket, so the `mount/3`-over-websocket half of a real page load -- and every
 * event after it -- is out of scope for this round; a page that dead-renders in
 * 20 ms and then takes a second to connect looks perfect here. `lobby_ws.js`
 * is where socket cost gets measured.
 *
 * Run this at a low `VUS` relative to the API scenarios. These responses are
 * roughly a hundred times the size of an API payload, and past a few VUs the
 * bottleneck moves into the generator's own buffers, which measures k6.
 *
 * The paths in docs/specs/load-testing.md do not all exist in this build:
 * `/lobbies` has no route (404) and the login page is `/users/log_in`, not
 * `/users/log-in`. `/groups` stands in for `/lobbies` because it is the page
 * with an API twin in this harness.
 */

import { check, sleep } from 'k6';
import { Trend } from 'k6/metrics';
import { constantVus, summaryHandler } from '../lib/config.js';
import { page } from '../lib/api.js';

const t = {
  home: new Trend('t_page_home', true),
  groups: new Trend('t_page_groups', true),
  login: new Trend('t_page_login', true),
  blog: new Trend('t_page_blog', true),
};

export const options = constantVus();
export const handleSummary = summaryHandler('web_pages');

export function setup() {
  // Which posts exist is content, not routing, so a hardcoded slug would turn
  // renaming a post into a red run. Take whatever the index actually links to.
  const index = page('/blog', 'GET /blog');
  const found = index.body && index.body.match(/href="(\/blog\/[a-z0-9-]+)"/);
  return { post: found ? found[1] : '/blog' };
}

export default function (ctx) {
  rendered(page('/', 'GET / (page)'), t.home, 'home');
  rendered(page('/groups', 'GET /groups (page)'), t.groups, 'groups');
  rendered(page('/users/log_in', 'GET /users/log_in (page)'), t.login, 'login');
  rendered(page(ctx.post, 'GET /blog/:slug (page)'), t.blog, 'blog post');

  sleep(0.5);
}

/**
 * A 200 alone would pass on an error page or an empty shell, and both are
 * plausible failure modes for a template that renders without its data.
 */
function rendered(res, trend, label) {
  trend.add(res.timings.duration);
  check(res, {
    [`${label} 200`]: (r) => r.status === 200,
    [`${label} is a full html document`]: (r) =>
      r.body !== null && r.body.length > 10000 && r.body.indexOf('<html') !== -1,
  });
}
