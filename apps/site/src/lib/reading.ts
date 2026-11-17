/** Group trusted, build-time Markdown headings into Air reading sections. */
export function readingSections(html: string): string {
  return html.replaceAll('<pre ', '<pre tabindex="0" role="region" aria-label="Code example" ').split(/(?=<h2\b)/).map(part => {
    const heading = part.match(/^<h2\b[^>]*\bid="([^"]+)"/);
    if (!heading) return part;
    return `<section aria-labelledby="${heading[1]}">${part.replace(/^<h2\b/, '<h2 tabindex="-1"')}</section>`;
  }).join('');
}
