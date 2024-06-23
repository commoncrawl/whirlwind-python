venv:
	@echo "making a venv in ~/venv/whirlwind"
	mkdir -p ~/venv
	virtualenv -p python ~/venv/whirlwind
	@echo
	@echo "now you have to activate it:"
	@echo ". ~/venv/whirlwind/bin/activate"
	@echo

install:
	pip install -r requirements.txt

iterate:
	@echo iterating over all of the local warcs:
	@echo
	@echo warc:
	python ./warcio-iterator.py whirlwind.warc.gz
	@echo
	@echo wet:
	python ./warcio-iterator.py whirlwind.warc.wet.gz
	@echo
	@echo wat:
	python ./warcio-iterator.py whirlwind.warc.wat.gz
	@echo

cdxj:
	@echo "creating *.cdxj index files from the local warcs"
	cdxj-indexer whirlwind.warc.gz > whirlwind.warc.cdxj
	cdxj-indexer --records conversion whirlwind.warc.wet.gz > whirlwind.warc.wet.cdxj
	cdxj-indexer whirlwind.warc.wat.gz > whirlwind.warc.wat.cdxj

extract:
	@echo "creating extraction.* from local warcs, the offset numbers are from the cdxj index"
	warcio extract --payload whirlwind.warc.gz 1023 > extraction.html
	warcio extract --payload whirlwind.warc.wet.gz 466 > extraction.txt
	warcio extract --payload whirlwind.warc.wat.gz 443 > extraction.json
	@echo "hint: python -m json.tool extraction.json"

cdx_toolkit:
	@echo look up this capture in the comoncrawl cdx index
	cdxt --cc --from 20240518015810 --to 20240518015810 iter an.wikipedia.org/wiki/Escopete
	@echo
	@echo extract the content from the commoncrawl s3 bucket
	rm -f TEST-000000.extracted.warc.gz
	cdxt --cc --from 20240518015810 --to 20240518015810 warc an.wikipedia.org/wiki/Escopete
	@echo
	@echo index this new warc
	cdxj-indexer TEST-000000.extracted.warc.gz  > TEST-000000.extracted.warc.cdxj
	cat TEST-000000.extracted.warc.cdxj
	@echo
	@echo iterate this new warc
	python ./warcio-iterator.py TEST-000000.extracted.warc.gz
	@echo

download_collinfo:
	@echo downloading collinfo.json so we can find out the crawl name
	wget https://index.commoncrawl.org/collinfo.json

duck_local_files:
	@echo "warning! 300 gigabyte download"
	python duck.py local_files

duck_ccf_local_files:
	@echo "warning! only works on greg's development machine"
	python duck.py ccf_local_files

duck_s3_ls_then_cloudfront:
	@echo "warning! this might take 1-10 minutes"
	python duck.py s3_ls_then_cloudfront

wreck_the_warc:
	@echo
	@echo we will break and then fix this warc
	cp whirlwind.warc.gz testing.warc.gz
	rm -f testing.warc
	gunzip testing.warc.gz
	@echo
	@echo iterate over this uncompressed warc: works
	python ./warcio-iterator.py testing.warc
	@echo
	@echo compress it the wrong way
	gzip testing.warc
	@echo
	@echo iterating over this compressed warc fails
	python ./warcio-iterator.py testing.warc.gz || /bin/true
	@echo
	@echo "now let's do it the right way"
	gunzip testing.warc.gz
	warcio recompress testing.warc testing.warc.gz
	@echo
	@echo and now iterating works
	python ./warcio-iterator.py testing.warc.gz
	@echo
