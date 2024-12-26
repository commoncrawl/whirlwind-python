import time
import glob
import json
import os.path
import subprocess
import sys
import gzip

import duckdb


def index_download_advice(prefix, crawl):
    print('Do you need to download this index?')
    print(f' mkdir -p {prefix}/commmoncrawl/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/')
    print(f' cd {prefix}/commmoncrawl/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/')
    print(f' aws s3 sync s3://commoncrawl/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/ .')


def print_row_as_cdxj(row):
    df = row.fetchdf()
    for ro in df.itertuples(index=False):
        d = ro._asdict()
        cdxjd = {
            'url': d['url'],
            'mime': d['content_mime_type'],
            'status': str(d['fetch_status']),
            'digest': 'sha1:' + d['content_digest'],
            'length': str(d['warc_record_length']),
            'offset': str(d['warc_record_offset']),
            'filename': d['warc_filename'],
        }

        timestamp = d['fetch_time'].isoformat(sep='T')
        timestamp = timestamp.translate(str.maketrans('', '', '-T :Z')).replace('+0000', '')

        print(d['url_surtkey'], timestamp, json.dumps(cdxjd))


def print_row_as_kv_list(row):
    df = row.fetchdf()
    for ro in df.itertuples(index=False):
        d = ro._asdict()
        for k, v in d.items():
            print(' ', k, v)


all_algos = ('s3_glob', 'local_files', 'ccf_local_files', 'cloudfront_glob', 'cloudfront')


def get_files(algo, crawl):
    if algo == 's3_glob':
        # 403 errors with and without credentials. you have to be commoncrawl-pds
        files = f's3://commoncrawl/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/*.parquet'
        raise NotImplementedError('will cause a 403')
    elif algo == 'local_files':
        files = os.path.expanduser(f'~/commmoncrawl/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/*.parquet')
        files = glob.glob(files)
        # did we already download? we expect 300 files of about a gigabyte
        if len(files) < 250:
            index_download_advice('~', crawl)
            exit(1)
    elif algo == 'ccf_local_files':
        files = glob.glob(f'/home/cc-pds/commoncrawl/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/*.parquet')
        if len(files) < 250:
            index_download_advice('/home/cc-pds', crawl)
            exit(1)
    elif algo == 'cloudfront_glob':
        # duckdb can't glob this, same reason as s3_glob above
        files = f'https://data.commoncrawl.org/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/*.parquet'
        raise NotImplementedError('duckdb will throw an error because it cannot glob this')
    elif algo == 'cloudfront':
        prefix = f's3://commoncrawl/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/'
        external_prefix = f'https://data.commoncrawl.org/cc-index/table/cc-main/warc/crawl={crawl}/subset=warc/'
        file_file = f'{crawl}.warc.paths.gz'

        with gzip.open(file_file, mode='rt', encoding='utf8') as fd:
            files = fd.read().splitlines()
            files = [external_prefix+f for f in files]
    else:
        raise NotImplementedError('algo: '+algo)
    return files


def main(algo, crawl):
    files = get_files(algo, crawl)
    while True:
        try:
            ccindex = duckdb.read_parquet(files, hive_partitioning=True)
            break
        except (duckdb.HTTPException, duckdb.InvalidInputException) as e:
            # read_parquet exception seen: HTTPException("HTTP Error: HTTP GET error on 'https://...' (HTTP 403)")
            # duckdb.duckdb.InvalidInputException: Invalid Input Error: No magic bytes found at end of file 'https://...'
            print('read_parquet exception seen:', repr(e), file=sys.stderr)
            print('sleeping for 60s', file=sys.stderr)
            time.sleep(60)

    duckdb.sql('SET enable_progress_bar = true;')
    duckdb.sql('SET http_retries = 100;')
    duckdb.sql("SET enable_http_logging = true;SET http_logging_output = 'duck.http.log'")

    print('total records for crawl:', crawl)
    retries_left = 10
    while True:
        try:
            print(duckdb.sql('SELECT COUNT(*) FROM ccindex;'))
            break
        except duckdb.InvalidInputException as e:
            # duckdb.duckdb.InvalidInputException: Invalid Input Error: No magic bytes found at end of file 'https://...'
            print('duckdb exception seen:', repr(e), file=sys.stderr)
            if retries_left:
                print('sleeping for 10s', file=sys.stderr)
                time.sleep(10)
                retries_left -= 1
            else:
                raise

    sq2 = f'''
    select
      *
    from ccindex
    where subset = 'warc'
      and crawl = 'CC-MAIN-2024-22'
      and url_host_tld = 'org' -- help the query optimizer
      and url_host_registered_domain = 'wikipedia.org' -- ditto
      and url = 'https://an.wikipedia.org/wiki/Escopete'
    ;
    '''

    row2 = duckdb.sql(sq2)
    print('our one row')
    row2.show()

    print('writing our one row to a local parquet file, whirlwind.parquet')
    row2.write_parquet('whirlwind.parquet')

    cclocal = duckdb.read_parquet('whirlwind.parquet')

    print('total records for local whirlwind.parquet should be 1')
    print(duckdb.sql('SELECT COUNT(*) FROM cclocal;'))

    sq3 = sq2.replace('ccindex', 'cclocal')
    row3 = duckdb.sql(sq3)
    print('our one row, locally')
    row3.show()

    print('complete row:')
    print_row_as_kv_list(row3)
    print('')

    print('equivalent to cdxj:')
    print_row_as_cdxj(row3)


if __name__ == '__main__':
    crawl = 'CC-MAIN-2024-22'
    if len(sys.argv) > 1:
        algo = sys.argv[1]
        if algo == 'help':
            print('possible algos:', all_algos)
            exit(1)
    else:
        algo = 'cloudfront'
        print('using algo: ', algo)

    main(algo, crawl)
