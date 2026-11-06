# Exporter

Exports record metadata from a WARC, WET, or WAT file, page text from a WET file, or page links from a WARC file, to CSV or JSON.

## Usage

```
python exporter/export_records.py <input> [-m records|text|links] [-f csv|json] [-o output]
```

- `input`: local path or remote URL (`https://`, `s3://`)
- `-m`: mode, `records` (default), `text`, or `links`
- `-f`: output format, `csv` (default) or `json`
- `-o`: output file, stdout if omitted

Example:

```
python exporter/export_records.py whirlwind.warc.gz -f json -o records.json
python exporter/export_records.py whirlwind.warc.wet.gz -m text
python exporter/export_records.py whirlwind.warc.gz -m links
```

Or export all local files into `exporter/output/`:

```
make export
```

## Fields

`records` mode, one row per record:

| Field | Source |
|---|---|
| `warc_type` | `WARC-Type` |
| `target_uri` | `WARC-Target-URI` |
| `date` | `WARC-Date` |
| `content_type` | `Content-Type` |
| `content_length` | `Content-Length` |
| `http_status` | HTTP status code (response records only) |

`text` mode, one row per WET `conversion` record:

| Field | Source |
|---|---|
| `url` | `WARC-Target-URI` |
| `language` | `WARC-Identified-Content-Language` |
| `word_count` | number of whitespace-separated words in the text |
| `preview` | first 200 characters of the text, whitespace collapsed |

`links` mode, one row per `<a href>` in each HTML WARC `response` record:

| Field | Source |
|---|---|
| `page_url` | `WARC-Target-URI` |
| `link_url` | `href`, resolved against `page_url` |
| `link_text` | text inside the `<a>` tag, whitespace collapsed |
