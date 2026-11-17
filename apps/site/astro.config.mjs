import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
export default defineConfig({ site: 'https://tools.cloakyard.com', output: 'static', trailingSlash: 'always', devToolbar: { enabled: false }, integrations: [sitemap()] });
