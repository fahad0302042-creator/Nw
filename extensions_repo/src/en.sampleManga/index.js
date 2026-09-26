/**
 * Sample MANGA extension for Kurayomi.
 *
 * This one is fully offline (it fabricates its data) so you can verify the
 * whole pipeline — install, browse, details, chapter list, reader — without
 * depending on any website. Use it as the skeleton for a real source.
 *
 * Available globals, provided by the runtime:
 *   http.get(url, {headers})     -> {status, url, headers, body}
 *   http.getDoc(url)             -> Document  (parsed HTML)
 *   http.getJson(url)            -> parsed JSON
 *   dom.parse(html, baseUrl)     -> Document
 *   doc.select(css) / selectFirst(css) -> Element[] / Element | null
 *   el.text, el.html, el.attr(name), el.absUrl(name), el.select(css)
 *   utils.absolute(base, url), utils.sleep(ms), utils.store.get/set
 *   console.log / warn / error
 *
 * Everything that touches the host is a Promise — always `await` it.
 */

const COVERS = [
  'https://placehold.co/400x600/7C5CFF/FFFFFF/png?text=Volume+',
];

function makeItem(i) {
  return {
    url: '/series/' + i,
    title: 'Demo Series ' + i,
    thumbnailUrl: COVERS[0] + i,
  };
}

class SampleMangaSource {
  constructor() {
    this.id = 'en.sampleManga';
    this.name = 'Sample Manga (Demo)';
    this.lang = 'en';
    this.baseUrl = 'https://example.invalid';
    this.type = 'manga';
    this.supportsLatest = true;
  }

  // ------------------------------------------------------------ browsing
  async popular(page) {
    const start = (page - 1) * 20;
    const items = [];
    for (let i = start + 1; i <= start + 20; i++) items.push(makeItem(i));
    return { items: items, hasNext: page < 5 };
  }

  async latest(page) {
    const res = await this.popular(page);
    res.items.reverse();
    return res;
  }

  async search(query, page, filters) {
    const res = await this.popular(page);
    const q = (query || '').toLowerCase();
    return {
      items: res.items.filter(function (m) {
        return m.title.toLowerCase().indexOf(q) !== -1;
      }),
      hasNext: false,
    };
  }

  // Declaring filters is optional; the app renders them automatically.
  async getFilters() {
    return [
      {
        key: 'genre',
        name: 'Genre',
        type: 'select',
        options: [
          { label: 'Any', value: '' },
          { label: 'Action', value: 'action' },
          { label: 'Romance', value: 'romance' },
        ],
      },
      { key: 'completed', name: 'Completed only', type: 'checkbox' },
    ];
  }

  // ------------------------------------------------------------- details
  async details(item) {
    return {
      url: item.url,
      title: item.title,
      thumbnailUrl: item.thumbnailUrl,
      author: 'Demo Author',
      artist: 'Demo Artist',
      description:
        'This series is generated locally by the sample extension. ' +
        'If you can read this, the extension runtime, HTTP bridge and ' +
        'database cache are all working correctly.',
      genres: ['Demo', 'Action', 'Slice of Life'],
      status: 'ongoing',
    };
  }

  async chapters(item) {
    const out = [];
    for (let i = 12; i >= 1; i--) {
      out.push({
        url: item.url + '/chapter/' + i,
        name: 'Chapter ' + i,
        number: i,
        scanlator: 'Demo Scans',
        dateUpload: Date.now() - i * 86400000,
      });
    }
    return out;
  }

  async pages(chapter) {
    const pages = [];
    for (let i = 1; i <= 8; i++) {
      pages.push(
        'https://placehold.co/1000x1500/1a1a22/FFFFFF/png?text=Page+' + i
      );
    }
    return pages;
  }
}

registerSource(new SampleMangaSource());
