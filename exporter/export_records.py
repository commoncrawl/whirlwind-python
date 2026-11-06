'''Export WARC, WET, or WAT record metadata, WET page text, or WARC page links to CSV or JSON.'''

import argparse
import contextlib
import csv
import json
import sys
from html.parser import HTMLParser
from urllib.parse import urljoin

import fsspec
from warcio.archiveiterator import ArchiveIterator

FIELDS = ('warc_type', 'target_uri', 'date', 'content_type', 'content_length', 'http_status')
TEXT_FIELDS = ('url', 'language', 'word_count', 'preview')
LINK_FIELDS = ('page_url', 'link_url', 'link_text')
PREVIEW_CHARS = 200


def iter_archive(path):
    with fsspec.open(path, 'rb') as stream:
        yield from ArchiveIterator(stream)


def read_records(path):
    for record in iter_archive(path):
        headers = record.rec_headers
        yield {
            'warc_type': record.rec_type,
            'target_uri': headers.get_header('WARC-Target-URI'),
            'date': headers.get_header('WARC-Date'),
            'content_type': headers.get_header('Content-Type'),
            'content_length': int(headers.get_header('Content-Length')),
            'http_status': int(record.http_headers.get_statuscode()) if record.rec_type == 'response' else None,
        }


def read_text(path):
    for record in iter_archive(path):
        if record.rec_type != 'conversion':
            continue
        words = record.content_stream().read().decode('utf-8', errors='replace').split()
        yield {
            'url': record.rec_headers.get_header('WARC-Target-URI'),
            'language': record.rec_headers.get_header('WARC-Identified-Content-Language'),
            'word_count': len(words),
            'preview': ' '.join(words)[:PREVIEW_CHARS],
        }


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links, self.href, self.text = [], None, []

    def handle_starttag(self, tag, attrs):
        if tag == 'a':
            self.close_link()
            self.href = dict(attrs).get('href')

    def handle_data(self, data):
        if self.href is not None:
            self.text.append(data)

    def handle_endtag(self, tag):
        if tag == 'a':
            self.close_link()

    def close_link(self):
        if self.href:
            self.links.append((self.href, ' '.join(''.join(self.text).split())))
        self.href, self.text = None, []


def read_links(path):
    for record in iter_archive(path):
        if record.rec_type != 'response' or 'html' not in (record.http_headers.get_header('Content-Type') or ''):
            continue
        page_url = record.rec_headers.get_header('WARC-Target-URI')
        parser = LinkParser()
        parser.feed(record.content_stream().read().decode('utf-8', errors='replace'))
        parser.close()
        for href, text in parser.links:
            yield {'page_url': page_url, 'link_url': urljoin(page_url, href), 'link_text': text}


def write_csv(records, fields, out):
    writer = csv.DictWriter(out, fieldnames=fields)
    writer.writeheader()
    writer.writerows(records)


def write_json(records, fields, out):
    json.dump(list(records), out, indent=2, ensure_ascii=False)
    out.write('\n')


MODES = {'records': (read_records, FIELDS), 'text': (read_text, TEXT_FIELDS), 'links': (read_links, LINK_FIELDS)}
WRITERS = {'csv': write_csv, 'json': write_json}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', help='local path or URL (https://, s3://) of a WARC, WET, or WAT file')
    parser.add_argument('-m', '--mode', choices=MODES, default='records', help='records: metadata of every record; text: page text from WET; links: page links from WARC')
    parser.add_argument('-f', '--format', choices=WRITERS, default='csv')
    parser.add_argument('-o', '--output', help='output file (default: stdout)')
    args = parser.parse_args()

    reader, fields = MODES[args.mode]
    out = open(args.output, 'w', newline='', encoding='utf-8') if args.output else contextlib.nullcontext(sys.stdout)
    with out as stream:
        WRITERS[args.format](reader(args.input), fields, stream)


if __name__ == '__main__':
    main()
