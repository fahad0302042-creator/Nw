/**
 * Sample ANIME extension for Kurayomi.
 *
 * Returns real, publicly hosted test streams (Google's sample MP4s and an
 * Apple HLS playlist) so you can confirm the player, quality switching and
 * resume-position logic actually work end to end.
 */

const HLS =
  'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8';
const MP4 =
  'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

class SampleAnimeSource {
  constructor() {
    this.id = 'en.sampleAnime';
    this.name = 'Sample Anime (Demo)';
    this.lang = 'en';
    this.baseUrl = 'https://example.invalid';
    this.type = 'anime';
    this.supportsLatest = false;
  }

  async popular(page) {
    const items = [];
    for (let i = 1; i <= 12; i++) {
      items.push({
        url: '/anime/' + i,
        title: 'Demo Anime ' + i,
        thumbnailUrl:
          'https://placehold.co/400x600/22c55e/FFFFFF/png?text=Anime+' + i,
      });
    }
    return { items: items, hasNext: false };
  }

  async latest(page) {
    return this.popular(page);
  }

  async search(query, page) {
    const res = await this.popular(page);
    const q = (query || '').toLowerCase();
    return {
      items: res.items.filter(function (a) {
        return a.title.toLowerCase().indexOf(q) !== -1;
      }),
      hasNext: false,
    };
  }

  async details(item) {
    return {
      url: item.url,
      title: item.title,
      thumbnailUrl: item.thumbnailUrl,
      author: 'Demo Studio',
      description:
        'A demo anime entry. Episodes play real public test streams so you ' +
        'can verify playback, quality switching and resume.',
      genres: ['Demo', 'Adventure'],
      status: 'completed',
    };
  }

  async episodes(item) {
    const out = [];
    for (let i = 6; i >= 1; i--) {
      out.push({
        url: item.url + '/episode/' + i,
        name: 'Episode ' + i,
        number: i,
        dateUpload: Date.now() - i * 604800000,
      });
    }
    return out;
  }

  async videos(episode) {
    // Odd episodes use HLS, even use progressive MP4 — exercises both paths.
    const isHls = episode.url.endsWith('1') || episode.url.endsWith('3');
    if (isHls) {
      return [{ url: HLS, quality: 'Auto (HLS)' }];
    }
    return [
      { url: MP4, quality: '720p' },
      { url: MP4, quality: '480p' },
    ];
  }
}

registerSource(new SampleAnimeSource());
