# Changes

## Record metadata export

Added `exporter/export_records.py`, which exports record metadata to CSV or JSON.

- Reads WARC, WET, or WAT files, local or remote, using `fsspec` and `warcio`, the same way `warcio-iterator.py` does.
- Extracts one row per record: type, URI, date, content type, length, and HTTP status.
- Reads records one at a time with a generator and keeps only their headers, so page content is never loaded into memory.
- Writes with `csv.DictWriter` or `json.dump`, chosen by `-f`.
- Uses only the standard library and packages already in `requirements.txt`.

Other changes:

- `Makefile`: added `make export`, which writes the outputs to `exporter/output/`.
- `.gitignore`: ignores `exporter/output/`.
- `exporter/README.md`: usage and field reference.

## Page text export

Added a `text` mode to `exporter/export_records.py` (`-m text`), which exports one row per WET `conversion` record: URL, language, word count, and a 200-character preview.

- `iter_archive()` now holds the shared open-and-iterate code, used by both readers.
- `-m` picks a reader and its CSV fields, so the writers stay format-only.
- JSON output keeps non-ASCII characters as-is (`ensure_ascii=False`).

Other changes:

- `Makefile`: `make export` also writes `exporter/output/text.csv`.
- `exporter/README.md`: documents `-m` and the `text` fields.
- `tests/test_exporter.py`: tests for the `text` mode.

## Page links export

Added a `links` mode to `exporter/export_records.py` (`-m links`), which exports one row per link found in the HTML of each WARC `response` record: page URL, link URL, and link text.

- Links come from the WARC HTML because the sample WAT file has no link data (its only metadata record describes the crawl request).
- `LinkParser` uses the standard library's `html.parser`, so no new packages are needed.
- Relative and protocol-relative links (`/wiki/...`, `//donate...`) are resolved to absolute URLs with `urljoin`.
- Non-HTML responses are skipped.

Other changes:

- `Makefile`: `make export` also writes `exporter/output/links.csv`.
- `exporter/README.md`: documents the `links` fields.
- `tests/test_exporter.py`: tests for the `links` mode and `LinkParser`.
