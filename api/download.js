const PICK = {
  win: n => /\.exe$/i.test(n),
  'mac-arm': n => /arm64\.dmg$/i.test(n),
  'mac-intel': n => /\.dmg$/i.test(n) && !/arm64/i.test(n)
};
const PAGE = 'https://github.com/rice-evans/RO-TAK/releases/latest';

module.exports = async (req, res) => {
  const pick = PICK[req.query && req.query.f];
  let to = PAGE;
  if (pick) {
    try {
      const r = await fetch('https://api.github.com/repos/rice-evans/RO-TAK/releases/latest', { headers: { 'User-Agent': 'ro-tak', Accept: 'application/vnd.github+json' } });
      if (r.ok) {
        const a = ((await r.json()).assets || []).find(x => pick(x.name));
        if (a) to = a.browser_download_url;
      }
    } catch (e) {}
  }
  res.setHeader('Cache-Control', to === PAGE ? 'no-store' : 's-maxage=600, stale-while-revalidate=3600');
  res.writeHead(302, { Location: to });
  res.end();
};
