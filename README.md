# Whirlwind Tour of Common Crawl's Datasets using Python

Common Crawl's data is complicated. We use the archiving community's
standard WARC format to store crawled webpages. We use this same
format to store text extractions (WET) and metadata (WAT) data.

We have 2 indexes of the crawled webpages, one stored as a flat file
(cdxj) and one stored in the parquet file format, which we call the
columnar index.

The object of this whirlwind tour is to show you how a single webpage
appears in all of these different places. It uses python-based tools
such as [warcio](https://github.com/webrecorder/warcio), [cdxj-indexer](https://github.com/webrecorder/cdxj-indexer), [cdx_toolkit](https://github.com/cocrawler/cdx_toolkit), and [duckdb](https://duckdb.org/).

That webpage is [https://an.wikipedia.org/wiki/Escopete](https://an.wikipedia.org/wiki/Escopete),
which we crawled on the date 2024-05-18T01:58:10Z.

What you need to run this? A recent version of Python, the
"virtualenv" command, and, most of the commands in this tour are in a
Makefile, so it would be nice if you had "make" on your system.

Ready? Here we go!

## Notes for Mac OS

```
brew install virtualenv
brew install awscli
```

## Look at the example files in an editor

warc files are a container that holds files, similar to zip and tar files.
Open up whirlwind.warc in your favorite text editor. This is the uncompressed
version of the file -- normally we always work with these files while they
are compressed.

You'll see 4 records total, each with a set of warc headers --
metadata related to that particular record. First is a warcinfo
record, every warc has that at the start. Then there are 3 records
related to fetching a single webpage: the request to the webserver,
with its http headers; the response from the webserver, with its http
headers followed by the html; and finally a metadata record related to
that response.

Now let's look at whirlwind.warc.wet -- which is in warc format, but
the thing stored in the record is the extracted text from the html.
There's a warcinfo record at the start, and then just one record
relating to the webpage. It's a "conversion" record: it does not
have any http headers, it's just the extracted text.

Finally, open up whirlwind.warc.wat -- also in warc format. This file
contains a metadata record for each response in the warc. The metadata
is stored as json. You might want to feed this json into a
pretty-printer to read it more easily. For example, you can save just
the json into a file and use `python -m json.tool FILENAME` to
pretty-print it.

Now that we've looked at the uncompressed versions of these files,
the rest of the tour will focus on the usual software tools used
to manipulate these files.

## Operating system compatibility

This was written in Linux. Todo: test it in MacOS. Todo: test in Windows
Subsystem for Linux. Todo: test in raw Windows.

## Set up a virtual environment

It's a good idea to set up completely separate environments for Python
project, where you can install things without either changing the
system Python environment, or any of your other Python projects.

If you already have your own virtual environment scheme, you can
skip this step. But otherwise:

Run: `make venv`

After this runs, you'll need to follow the instructions and run this
command in your shell:

`. ~/venv/whirlwind/bin/activate`

And you'll need to run that command in the future if you log out and
log in again.

## Install python packages

At this point you have a very minimal Python environment, so let's install
the necessary software for this tour.

Run: `make install`

## Iterate over warc, wet, wat

Now you have some tools, let's look at the compressed versions of these
files. Run: `make iterate`

The output has 3 sections, one each for the warc, wet, and wat. It prints
the record types, you've seen these before. And for the record types
that have an Target-URI as part of their warc headers, it prints that URI.

Take a look at the program `warcio-iterator.py`. It's a very simple example
of how to iterate over all of the records in a warc file.

## Index warc, wet, and wat

These warc files are tiny and easy to work with. Our real warc files
are around a gigabyte in size, and have about 30,000 webpages in them.
And we have around 24 million of these files. If we'd like to read
all of them, we could iterate, but what if we wanted random access, to
just read this one record? We do that with an index. We have two
of them, let's start with the cdxj index.

Run: `make cdxj` and then `more whirlwind*.cdxj`. You'll see that each
file has one entry in the index. The warc only has the response record
indexed -- we're guessing that you won't ever want to random-access
the request or metadata. wet and wat have the conversion and metadata
records indexed.

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

You usually don't expect compressed files to be random access, but
they are in zip files. The trick is that each record needs to be
separately compressed. gzip supports this, but it's rarely used. warc
files are written in this unusual way.

To extract one record from a warc file, all you need to know is the
filename and the offset into the file. If you're reading over the web,
then it really helps to know the exact length of the record.

Run `make extract` to run a set of extractions from your local
whirlwind.*.gz files. The offset numbers in the Makefile are the same
ones as in the index. You can look at the 3 output files:
extraction.html, extraction.txt, and extraction.json. Again you
might want to pretty-print the json: `python -m json.tool extraction.json`

## Use cdx_toolkit to query the full cdx index and download from S3

Some of our users only want to download a small subset of the crawl.
They want to run queries in an index, either the cdx index we just talked
about, or in the columnar index, which we'll talk about later.

cdx_toolkit is client software that knows how to query the cdx index
across all of our crawls, and also can create warcs of just the records
you want. We will fetch the same record from wikipedia that we've been
using for this whirlwind tour:

Run `make cdx_toolkit`

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

It is only downloading the response warc record, because our
cdx index only has the response records indexed. The public cannot
random access the wet and wat records due to lack of an index. We do
have these indexes internally though, if you need them. This may
change in future if we make the wat/wet indexes public.

## The columnar index

In addition to the cdx index, which is a little idiosyncratic compared
to your usual database, we also have a columnar database stored in
Parquet files. This can be accessed by tools using SQL such as Apache
Athena and duckdb, and as tables in your favorite table packages
such as pandas, pyarrow, and polars.

Apache Athena is a managed service that costs money -- often a small
amount -- to use. This whirlwind tour will only use the free method of
either fetching data directly from s3 (which is kind of slow), or
making a local copy of a single columnar index (300 gigabytes per
monthly crawl), and then using that.

The columnar index is divided up into a separate index per crawl,
which Athena or duckdb can stitch together. The cdx index is similarly
divided up, but cdx_toolkit hides that detail from you. In order
to use Athena or duckdb, we need to know what index to query.

This is done by downloading the file collinfo.json from
index.commoncrawl.org, which specifies the start and end of every crawl.

Run `make download_collinfo`

The date of our test record is 20240518015810, which is
2024-05-18T01:58:10 if you add the delimiters back in. Looking at the
from/to values in collinfo, you can see that the crawl with this
record is CC-MAIN-2024-22. Knowing the crawl name allows us to access
the correct 1% of the index without looking at the other 99%.

cdx_toolkit hid this detail from you. Someday we'll have a
duckdb-based solution which also hides this detail.

A single crawl columnar index is around 300 gigabytes. If you
don't have a lot of disk space and you do have a lot of time,
then here's the best choice:

Run `make duck_s3_ls_then_cloudfront`

On a machine with a 1 gigabit network connection, and many cores, this takes 1
minute total, and uses 8 cores.

If you want to run several of these queries, you'll want to download
the 300 gigabyte index and query it repeatedly:

Run `make duck_local_files`

If the files aren't already downloaded, this command will give you
download instructions.

And if you're using the Common Crawl Foundation development server,
we've already downloaded these files, and you can:

Run `make duck_ccf_local_files`

For all of these scripts, the code runs an SQL query which should
match the single response record for our favorite url and date.
The program also then writes that one record into a local Parquet
file, does a second query that returns that one record, and shows
the full contents of the record.

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

Run `make wreck_the_warc`

## Coda

You have now finished this whirlwind tutorial. If anything
didn't work, or anything wasn't clear, please open an
issue in this repo. Thank you!

