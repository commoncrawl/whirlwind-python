# Whirlwind Tour of Common Crawl's Datasets using Python

Common Crawl's data storage is complicated. We use the archiving
community's standard WARC format to store crawled webpages. We use
this same format to store text extractions (WET) and metadata (WAT)
data.

We have 2 indexes of the crawled webpages, one stored as a flat file
(cdxj) and one stored in the parquet file format, which we call the
columnar index.

Finally, we have a web graph by host and domains. It is not currently
demonstrated in this tour.

## Goal of this tour

The goal of this whirlwind tour is to show you how a single webpage
appears in all of these different places. It uses python-based tools
such as [warcio](https://github.com/webrecorder/warcio),
[cdxj-indexer](https://github.com/webrecorder/cdxj-indexer),
[cdx_toolkit](https://github.com/cocrawler/cdx_toolkit),
and [duckdb](https://duckdb.org/).

That webpage is [https://an.wikipedia.org/wiki/Escopete](https://an.wikipedia.org/wiki/Escopete),
which we crawled on the date 2024-05-18T01:58:10Z.

What you need to run this? A recent version of Python. Most of the
commands in this tour are in a Makefile, so it would be nice if you
had "make" on your system.

Ready? Here we go!

## Look at the example files in an editor

WARC files are a container that holds files, similar to zip and tar files.
Open up whirlwind.warc in your favorite text editor. This is the uncompressed
version of the file -- normally we always work with these files while they
are compressed.

You'll see 4 records total, each with a set of warc headers --
metadata related to that particular record.

First is a warcinfo
record. Every warc has that at the start. Then there are 3 records
related to fetching a single webpage: the request to the webserver,
with its http headers; the response from the webserver, with its http
headers followed by the html; and finally a metadata record related to
that response.

Now let's look at whirlwind.warc.wet -- which is in WARC format, but
the thing stored in the record is the extracted text from the html.
There's a warcinfo record at the start, and then just one record
relating to the webpage. It's a "conversion" record: it does not
have any http headers, it's just the extracted text.

Finally, open up whirlwind.warc.wat -- also in WARC format. This file
contains a metadata record for each response in the warc. The metadata
is stored as json. You might want to feed this json into a
pretty-printer to read it more easily. For example, you can save just
the json into a file and use `python -m json.tool FILENAME` to
pretty-print it.

Now that we've looked at the uncompressed versions of these files,
the rest of the tour will focus on the usual software tools used
to manipulate these files.

## Operating system compatibility

This was written in Linux. We think it should run on Windows WSL
and in MacOS.

On a Mac, you'll need `make` (part of Xcode) and `awscli`, perhaps
installed with `brew install awscli`. You'll also need virtualenv,
`brew install virtualenv`.

## Set up a virtual environment

It's a good idea to set up completely separate environments for Python
project, where you can install things without either changing the
system Python environment, or any of your other Python projects.

If you already have your own favorite virtual environment scheme, you
can skip this step. But otherwise:

```make venv```

After you create this venv, you'll need to activate it. Run this
command in your shell:

```source ~/venv/whirlwind/bin/activate```

You'll need to run that command in the future if you log out and
log in again.

## Install python packages

At this point you have a very minimal Python environment, so let's install
the necessary software for this tour.

```make install```

This command will print out a screen-full of output.

## Iterate over warc, wet, wat

Now you have some tools, let's look at the compressed versions of
these files. We'll use a small python program which uses the `warcio`
package to iterate over these files. First look at the code:

```cat warcio-iterator.py```

And you will see:

```
'''Generic example iterator, similar to what's in the warcio README.'''

import sys

from warcio.archiveiterator import ArchiveIterator

for file in sys.argv[1:]:
    with open(file, 'rb') as stream:
        for record in ArchiveIterator(stream):
            print(' ', 'WARC-Type:', record.rec_type)
            if record.rec_type in {'request', 'response', 'conversion', 'metadata'}:
                print('   ', 'WARC-Target-URI', record.rec_headers.get_header('WARC-Target-URI'))
```

Now run:

```make iterate```

You should see something like:

```
iterating over all of the local warcs:

warc:
python ./warcio-iterator.py whirlwind.warc.gz
  WARC-Type: warcinfo
  WARC-Type: request
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
  WARC-Type: response
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
  WARC-Type: metadata
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete

wet:
python ./warcio-iterator.py whirlwind.warc.wet.gz
  WARC-Type: warcinfo
  WARC-Type: conversion
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete

wat:
python ./warcio-iterator.py whirlwind.warc.wat.gz
  WARC-Type: warcinfo
  WARC-Type: metadata
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
```

The output has 3 sections, one each for the warc, wet, and wat. It prints
the record types; you've seen these before. And for the record types
that have an Target-URI as part of their warc headers, it prints that URI.

## Index warc, wet, and wat

These example warc files are tiny and easy to work with. Our real warc
files are around a gigabyte in size, and have about 30,000 webpages in
them. And we have around 24 million of these files. If we'd like to
read all of them, we could iterate, but what if we wanted random
access, to just read this one record? We do that with an index. We
have two of them.

Let's start with the cdxj index.

```make cdxj```

```
creating *.cdxj index files from the local warcs
cdxj-indexer whirlwind.warc.gz > whirlwind.warc.cdxj
cdxj-indexer --records conversion whirlwind.warc.wet.gz > whirlwind.warc.wet.cdxj
cdxj-indexer whirlwind.warc.wat.gz > whirlwind.warc.wat.cdxj
```

Now look at the .cdxj files with `cat whirlwind*.cdxj`. You'll see
that each file has one entry in the index. The warc only has the
response record indexed -- by default cdxj-indexer guesses that you
won't ever want to random-access the request or metadata. wet and wat
have the conversion and metadata records indexed.

(Note: CCF doesn't publish a wet or wat index, just warc.)

For each of these records, there's one text line in the index -- yes,
it's a flat file! It starts with a string like
`org,wikipedia,an)/wiki/escopete 20240518015810` followed by a json
blob.

The starting string is the primary key of the index. The first
thing is a [SURT](http://crawler.archive.org/articles/user_manual/glossary.html#surt)
(Sort-friendly URI Reordering Transform). The big integer
is a date, in ISO-8601 format with the delimiters removed.

What is the purpose of this funky format? It's done this way because
these flat files (300 gigabytes total per crawl) can be sorted on the
primary key using any out-of-core sort utility -- like the standard
Linux `sort`, or one of the Hadoop-based out-of-core sort functions.

The json blob has enough information to extract individual records --
it says which warc file the record is in, and the offset and length of
the record. We'll use that in the next section.

## Extract the raw content from local warc, wet, wat

You usually don't expect compressed files to be random access.
But there's a trick that makes that possible with many
compression schemes -- the trick is that each record needs to be
separately compressed. gzip supports this, but it's rarely used. warc
files are written in this unusual way.

To extract one record from a warc file, all you need to know is the
filename and the offset into the file. If you're reading over the web,
then it really helps to know the exact length of the record.

Run:

```make extract```

to run a set of extractions from your local
whirlwind.*.gz files.

```
creating extraction.* from local warcs, the offset numbers are from the cdxj index
warcio extract --payload whirlwind.warc.gz 1023 > extraction.html
warcio extract --payload whirlwind.warc.wet.gz 466 > extraction.txt
warcio extract --payload whirlwind.warc.wat.gz 443 > extraction.json
hint: python -m json.tool extraction.json
```

The offset numbers in the Makefile are the same
ones as in the index. You can look at the 3 output files:
`extraction.html`, `extraction.txt`, and `extraction.json`. Again you
might want to pretty-print the json: `python -m json.tool extraction.json`

## Use cdx_toolkit to query the full cdx index and download those captures from S3

Some of our users only want to download a small subset of the crawl.
They want to run queries against an index, either the cdx index we
just talked about, or in the columnar index, which we'll talk about
later.

`cdx_toolkit` is client software that knows how to query the cdx index
across all of our crawls, and also can create warcs of just the records
you want. We will fetch the same record from wikipedia that we've been
using for this whirlwind tour:

Run

```make cdx_toolkit```

The output looks like this:

```
look up this capture in the comoncrawl cdx index
cdxt --cc --from 20240518015810 --to 20240518015810 iter an.wikipedia.org/wiki/Escopete
status 200, timestamp 20240518015810, url https://an.wikipedia.org/wiki/Escopete

extract the content from the commoncrawl s3 bucket
rm -f TEST-000000.extracted.warc.gz
cdxt --cc --from 20240518015810 --to 20240518015810 warc an.wikipedia.org/wiki/Escopete

index this new warc
cdxj-indexer TEST-000000.extracted.warc.gz  > TEST-000000.extracted.warc.cdxj
cat TEST-000000.extracted.warc.cdxj
org,wikipedia,an)/wiki/escopete 20240518015810 {"url": "https://an.wikipedia.org/wiki/Escopete", "mime": "text/html", "status": "200", "digest": "sha1:RY7PLBUFQNI2FFV5FTUQK72W6SNPXLQU", "length": "17455", "offset": "379", "filename": "TEST-000000.extracted.warc.gz"}

iterate this new warc
python ./warcio-iterator.py TEST-000000.extracted.warc.gz
  WARC-Type: warcinfo
  WARC-Type: response
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
```

The command lines for these `cdxt` commands specifies the exact URL
we've been using all along, and the particular date of its
capture, 20240518015810. The output is a warc file
TEST-000000.extracted.warc.gz, with this one record plus a warcinfo
record explaining what this warc is. The Makefile target also runs
cdxj-indexer on this new warc, and iterates over it.

If you dig into cdx_toolkit's code, you'll find that it is using the
offset and length of the warc record, returned by the cdx index query,
to make a http byte range request to S3 to download this single warc
record.

It is only downloading the response warc record, because our cdx index
only has the response records indexed. We might make wet and wat cdx
indexes public in the future.

## The columnar index

In addition to the cdx index, which is a little idiosyncratic compared
to your usual database, we also have a columnar database stored in
parquet files. This can be accessed by tools using SQL such as AWS
Athena and duckdb, and as tables in your favorite table packages
such as pandas, pyarrow, and polars.

AWS Athena is a managed service that costs money -- usually a small
amount -- to use. It reads directly from our index in our s3 bucket.
[You can read about using it here.](https://commoncrawl.org/blog/index-to-warc-files-and-urls-in-columnar-format)

This whirlwind tour will only use the free method of either fetching
data from outside of AWS (which is kind of slow), or making a local
copy of a single columnar index (300 gigabytes per monthly crawl), and
then using that.

The columnar index is divided up into a separate index per crawl,
which Athena or duckdb can stitch together. The cdx index is similarly
divided up, but cdx_toolkit hides that detail from you.

For the purposes of this whirlwind tour, we don't want to configure
all of the crawl indexes, because it would be slow. So let's start by
figuring out which crawl was ongoing on the date 20240518015810, and
then we'll work with just that one crawl.

To find the crawl name, download the file collinfo.json from
index.commoncrawl.org. It includes the dates for the the start and end
of every crawl.

Run

```make download_collinfo```

The output looks like:

```
downloading collinfo.json so we can find out the crawl name
curl -O https://index.commoncrawl.org/collinfo.json
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 30950  100 30950    0     0  75467      0 --:--:-- --:--:-- --:--:-- 75487
```

The date of our test record is 20240518015810, which is
2024-05-18T01:58:10 if you add the delimiters back in. Looking at the
from/to values in `collinfo.json`, you can see that the crawl with this
date is CC-MAIN-2024-22. Knowing the crawl name allows us to access
the correct 1% of the index without having to read the metadata of the
other 99%.

(`cdx_toolkit` hid this detail from you. AWS Athena is so fast that
you don't really need to tell it which crawl to look in if you have a
specific date. Someday we'll have a duckdb-based solution which also
hides this detail.)

### What does the SQL look like?

```
    select
      *
    from ccindex
    where subset = 'warc'
      and crawl = 'CC-MAIN-2024-22'
      and url_host_tld = 'org' -- help the query optimizer
      and url_host_registered_domain = 'wikipedia.org' -- ditto
      and url = 'https://an.wikipedia.org/wiki/Escopete'
    ;
```

### What does this demo script do?

For all of these scripts, the code runs an SQL query which should
match the single response record for our favorite url and date.
The program also then writes that one record into a local Parquet
file, does a second query that returns that one record, and shows
the full contents of the record.

To run this demo, you need to choose one of the following options
for where the index data will be.

### Columnar Index + duckdb from outside AWS

A single crawl columnar index is around 300 gigabytes. If you
don't have a lot of disk space and you do have a lot of time,
here's how you directly access the index stored on AWS S3.

Run

```make duck_cloudfront```

The output is

```
warning! this might take 1-10 minutes
python duck.py cloudfront
total records for crawl: CC-MAIN-2024-22
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│   2709877975 │
└──────────────┘

our one row
┌──────────────────────┬──────────────────────┬──────────────────┬───┬──────────────────┬─────────────────┬─────────┐
│     url_surtkey      │         url          │  url_host_name   │ … │   warc_segment   │      crawl      │ subset  │
│       varchar        │       varchar        │     varchar      │   │     varchar      │     varchar     │ varchar │
├──────────────────────┼──────────────────────┼──────────────────┼───┼──────────────────┼─────────────────┼─────────┤
│ org,wikipedia,an)/…  │ https://an.wikiped…  │ an.wikipedia.org │ … │ 1715971057216.39 │ CC-MAIN-2024-22 │ warc    │
├──────────────────────┴──────────────────────┴──────────────────┴───┴──────────────────┴─────────────────┴─────────┤
│ 1 rows                                                                                       32 columns (6 shown) │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

writing our one row to a local parquet file, whirlwind.parquet
total records for local whirlwind.parquet should be 1
┌──────────────┐
│ count_star() │
│    int64     │
├──────────────┤
│            1 │
└──────────────┘

our one row, locally
┌──────────────────────┬──────────────────────┬──────────────────┬───┬──────────────────┬─────────────────┬─────────┐
│     url_surtkey      │         url          │  url_host_name   │ … │   warc_segment   │      crawl      │ subset  │
│       varchar        │       varchar        │     varchar      │   │     varchar      │     varchar     │ varchar │
├──────────────────────┼──────────────────────┼──────────────────┼───┼──────────────────┼─────────────────┼─────────┤
│ org,wikipedia,an)/…  │ https://an.wikiped…  │ an.wikipedia.org │ … │ 1715971057216.39 │ CC-MAIN-2024-22 │ warc    │
├──────────────────────┴──────────────────────┴──────────────────┴───┴──────────────────┴─────────────────┴─────────┤
│ 1 rows                                                                                       32 columns (6 shown) │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

complete row:
  url_surtkey org,wikipedia,an)/wiki/escopete
  url https://an.wikipedia.org/wiki/Escopete
  url_host_name an.wikipedia.org
  url_host_tld org
  url_host_2nd_last_part wikipedia
  url_host_3rd_last_part an
  url_host_4th_last_part None
  url_host_5th_last_part None
  url_host_registry_suffix org
  url_host_registered_domain wikipedia.org
  url_host_private_suffix org
  url_host_private_domain wikipedia.org
  url_host_name_reversed org.wikipedia.an
  url_protocol https
  url_port nan
  url_path /wiki/Escopete
  url_query None
  fetch_time 2024-05-18 01:58:10+00:00
  fetch_status 200
  fetch_redirect None
  content_digest RY7PLBUFQNI2FFV5FTUQK72W6SNPXLQU
  content_mime_type text/html
  content_mime_detected text/html
  content_charset UTF-8
  content_languages spa
  content_truncated None
  warc_filename crawl-data/CC-MAIN-2024-22/segments/1715971057216.39/warc/CC-MAIN-20240517233122-20240518023122-00000.warc.gz
  warc_record_offset 80610731
  warc_record_length 17423
  warc_segment 1715971057216.39
  crawl CC-MAIN-2024-22
  subset warc

equivalent to cdxj:
org,wikipedia,an)/wiki/escopete 20240518015810 {"url": "https://an.wikipedia.org/wiki/Escopete", "mime": "text/html", "status": "200", "digest": "sha1:RY7PLBUFQNI2FFV5FTUQK72W6SNPXLQU", "length": "17423", "offset": "80610731", "filename": "crawl-data/CC-MAIN-2024-22/segments/1715971057216.39/warc/CC-MAIN-20240517233122-20240518023122-00000.warc.gz"}

```

On a machine with a 1 gigabit network connection, and many cores, this takes 1
minute total, and uses 8 cores.

### Download a full crawl index + duckdb

If you want to run many of these queries,
and you have a lot of disk space, you'll want to download
the 300 gigabyte index and query it repeatedly.

Run

```make duck_local_files```

If the files aren't already downloaded, this command will give you
download instructions.

### Use a previously download copy of the columnar index

And if you're using the Common Crawl Foundation development server,
we've already downloaded these files, and you can:

Run

```make duck_ccf_local_files```

## Wreck the warc

As mentioned earlier, warc/wet/wat files look like they're gzipped,
but they're actually gzipped in a particularly funny way that allows
random access. This means that you can't gunzip and then gzip a warc
without wrecking random access. This example:

* creates a copy of one of the warc files in the repo
* uncompresses it
* recompresses it the wrong way
* runs warcio-iterator over it to show that it triggers an error
* recompresses it the right way using `warcio recompress`
* shows that this compressed file works

Run

```make wreck_the_warc```

```
we will break and then fix this warc
cp whirlwind.warc.gz testing.warc.gz
rm -f testing.warc
gunzip testing.warc.gz

iterate over this uncompressed warc: works
python ./warcio-iterator.py testing.warc
  WARC-Type: warcinfo
  WARC-Type: request
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
  WARC-Type: response
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
  WARC-Type: metadata
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete

compress it the wrong way
gzip testing.warc

iterating over this compressed warc fails
python ./warcio-iterator.py testing.warc.gz || /usr/bin/true
  WARC-Type: warcinfo
Traceback (most recent call last):
  File "/home/ccgreg/github/whirlwind-python/./warcio-iterator.py", line 9, in <module>
    for record in ArchiveIterator(stream):
  File "/home/ccgreg/venv/whirlwind/lib/python3.10/site-packages/warcio/archiveiterator.py", line 112, in _iterate_records
    self._raise_invalid_gzip_err()
  File "/home/ccgreg/venv/whirlwind/lib/python3.10/site-packages/warcio/archiveiterator.py", line 153, in _raise_invalid_gzip_err
    raise ArchiveLoadFailed(msg)
warcio.exceptions.ArchiveLoadFailed:
    ERROR: non-chunked gzip file detected, gzip block continues
    beyond single record.

    This file is probably not a multi-member gzip but a single gzip file.

    To allow seek, a gzipped WARC must have each record compressed into
    a single gzip member and concatenated together.

    This file is likely still valid and can be fixed by running:

    warcio recompress <path/to/file> <path/to/new_file>



now let's do it the right way
gunzip testing.warc.gz
warcio recompress testing.warc testing.warc.gz
4 records read and recompressed to file: testing.warc.gz
No Errors Found!

and now iterating works
python ./warcio-iterator.py testing.warc.gz
  WARC-Type: warcinfo
  WARC-Type: request
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
  WARC-Type: response
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
  WARC-Type: metadata
    WARC-Target-URI https://an.wikipedia.org/wiki/Escopete
```

## Coda

You have now finished this whirlwind tutorial. If anything
didn't work, or anything wasn't clear, please open an
issue in this repo. Thank you!

