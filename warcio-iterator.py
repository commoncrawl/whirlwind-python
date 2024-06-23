'''Generic example iterator, similar to what's in the warcio README.'''

import sys

from warcio.archiveiterator import ArchiveIterator

for file in sys.argv[1:]:
    with open(file, 'rb') as stream:
        for record in ArchiveIterator(stream):
            print(' ', 'WARC-Type:', record.rec_type)
            if record.rec_type in {'request', 'response', 'conversion', 'metadata'}:
                print('   ', 'WARC-Target-URI', record.rec_headers.get_header('WARC-Target-URI'))
