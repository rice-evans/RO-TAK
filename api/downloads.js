const out = (res, message, color, age) => {
  res.setHeader('Cache-Control', 's-maxage=' + age + ', stale-while-revalidate=86400');
  res.status(200).json({ schemaVersion: 1, label: 'downloads', message, color });
};

module.exports = async (req, res) => {
  let total = 0;
  try {
    for (let page = 1; page < 20; page++) {
      const r = await fetch('https://api.github.com/repos/rice-evans/RO-TAK/releases?per_page=100&page=' + page, { headers: { 'User-Agent': 'ro-tak', Accept: 'application/vnd.github+json' } });
      if (!r.ok) return out(res, 'unavailable', 'lightgrey', 300);
      const list = await r.json();
      for (const rel of list) for (const a of rel.assets) if (/\.(dmg|exe)$/i.test(a.name)) total += a.download_count;
      if (list.length < 100) break;
    }
  } catch (e) {
    return out(res, 'unavailable', 'lightgrey', 300);
  }
  out(res, String(total), 'brightgreen', 3600);
};
