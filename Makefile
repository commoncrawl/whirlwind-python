EOT_IA_WARC_HTTPS = https://eotarchive.s3.amazonaws.com/crawl-data/EOT-2024/segments/IA-000/warc/EOT24PRE-20240926172119-crawl804_EOT24PRE-20240926172119-00000.warc.gz
EOT_IA_WARC_S3    = s3://eotarchive/crawl-data/EOT-2024/segments/IA-000/warc/EOT24PRE-20240926172119-crawl804_EOT24PRE-20240926172119-00000.warc.gz
EOT_CC_WARC_HTTPS = https://eotarchive.s3.amazonaws.com/crawl-data/EOT-2024/segments/CC-000/warc/EOT-2024-REPACKAGE-CC-MAIN-2024-42-GOV-000000-001.warc.gz
EOT_CC_WARC_S3    = s3://eotarchive/crawl-data/EOT-2024/segments/CC-000/warc/EOT-2024-REPACKAGE-CC-MAIN-2024-42-GOV-000000-001.warc.gz
WHIRLWIND_WARC_HTTPS = https://raw.githubusercontent.com/commoncrawl/whirlwind-python/refs/heads/main/whirlwind.warc.gz

venv:
	@echo "making a venv in ~/venv/whirlwind"
	mkdir -p ~/venv
	virtualenv -p python ~/venv/whirlwind
	@echo
	@echo "now you have to activate it:"
	@echo "source ~/venv/whirlwind/bin/activate"

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

iterate-remote:
	@echo "iterating over whirlwind.warc.gz from GitHub via HTTPS:"
	python ./warcio-iterator.py $(WHIRLWIND_WARC_HTTPS)

cdxj:
	@echo "creating *.cdxj index files from the local warcs"
	cdxj-indexer whirlwind.warc.gz > whirlwind.warc.cdxj
	cdxj-indexer --records conversion whirlwind.warc.wet.gz > whirlwind.warc.wet.cdxj
	cdxj-indexer whirlwind.warc.wat.gz > whirlwind.warc.wat.cdxj

cdxj-remote-https:
	@echo "indexing End-of-Term-2024 Internet Archive WARC over HTTPS (File size ~1GB, showing first 10 records):"
	cdxj-indexer $(EOT_IA_WARC_HTTPS) 2>/dev/null | head -n 10 | tee eot-ia.cdxj
	@echo
	@echo "indexing End-of-Term-2024 Common Crawl repackage WARC over HTTPS (File size ~1GB, showing first 10 records):"
	cdxj-indexer $(EOT_CC_WARC_HTTPS) 2>/dev/null | head -n 10 | tee eot-cc.cdxj

cdxj-remote-s3:
	@echo "!! this step requires authentication via S3 credentials (even though it is free)"
	@echo "indexing End-of-Term-2024 Internet Archive WARC over S3 (File size ~1GB, showing first 10 records):"
	cdxj-indexer $(EOT_IA_WARC_S3) 2>/dev/null | head -n 10 | tee eot-ia.cdxj
	@echo
	@echo "indexing End-of-Term-2024 Common Crawl repackage WARC over S3 (File size ~1GB, showing first 10 records):"
	cdxj-indexer $(EOT_CC_WARC_S3) 2>/dev/null | head -n 10 | tee eot-cc.cdxj

extract:
	@echo "creating extraction.* from local warcs, the offset numbers are from the cdxj index"
	warcio extract --payload whirlwind.warc.gz 1023 > extraction.html
	warcio extract --payload whirlwind.warc.wet.gz 466 > extraction.txt
	warcio extract --payload whirlwind.warc.wat.gz 443 > extraction.json
	@echo "hint: python -m json.tool extraction.json"

extract-remote-https:
	@echo "extracting hpxml.nrel.gov record from End-of-Term Internet Archive WARC over HTTPS (offset 50755):"
	warcio extract $(EOT_IA_WARC_HTTPS) 50755
	@echo
	@echo "extracting before-you-ship.18f.gov record from End-of-Term Common Crawl repackage WARC over HTTPS (offset 18595):"
	warcio extract $(EOT_CC_WARC_HTTPS) 18595

extract-remote-s3:
	@echo "!! this step requires authentication via S3 credentials (even though it is free)"
	@echo "extracting hpxml.nrel.gov record from End-of-Term Internet Archive WARC over S3 (offset 50755):"
	warcio extract $(EOT_IA_WARC_S3) 50755
	@echo
	@echo "extracting before-you-ship.18f.gov record from End-of-Term Common Crawl repackage WARC over S3 (offset 18595):"
	warcio extract $(EOT_CC_WARC_S3) 18595

cdx_toolkit:
	@echo demonstrate that we have this entry in the index
	cdxt --crawl CC-MAIN-2024-22 --from 20240518015810 --to 20240518015810 iter an.wikipedia.org/wiki/Escopete
	@echo
	@echo cleanup previous work
	rm -f TEST-000000.extracted.warc.gz
	@echo retrieve the content from the commoncrawl s3 bucket
	cdxt --crawl CC-MAIN-2024-22 --from 20240518015810 --to 20240518015810 warc an.wikipedia.org/wiki/Escopete
	@echo
	@echo index this new warc
	cdxj-indexer TEST-000000.extracted.warc.gz  > TEST-000000.extracted.warc.cdxj
	cat TEST-000000.extracted.warc.cdxj
	@echo
	@echo iterate this new warc
	python ./warcio-iterator.py TEST-000000.extracted.warc.gz
	@echo

download_collinfo:
	@echo "downloading collinfo.json so we can find out the crawl name"
	curl -O https://index.commoncrawl.org/collinfo.json

CC-MAIN-2024-22.warc.paths.gz:
	@echo "!! this step requires authentication via S3 credentials (even though it is free)"
	@echo "note that this file should already be in the repo"
	 aws s3 ls s3://commoncrawl/cc-index/table/cc-main/warc/crawl=CC-MAIN-2024-22/subset=warc/ | awk '{print $$4}' | gzip -9 > CC-MAIN-2024-22.warc.paths.gz

duck_local_files:
	@echo "warning! 300 gigabyte download"
	python duck.py local_files

duck_ccf_local_files:
	@echo "warning! only works on Common Crawl Foundadtion's development machine"
	python duck.py ccf_local_files

duck_cloudfront:
	@echo "warning! this might take 1-10 minutes"
	python duck.py cloudfront

wreck_the_warc:
	@echo
	@echo we will break and then fix this warc
	cp whirlwind.warc.gz testing.warc.gz
	rm -f testing.warc
	gzip -d testing.warc.gz  # windows gunzip no work-a
	@echo
	@echo iterate over this uncompressed warc: works
	python ./warcio-iterator.py testing.warc
	@echo
	@echo compress it the wrong way
	gzip testing.warc
	@echo
	@echo iterating over this compressed warc fails
	python ./warcio-iterator.py testing.warc.gz || /usr/bin/true
	@echo
	@echo "now let's do it the right way"
	gzip -d testing.warc.gz
	warcio recompress testing.warc testing.warc.gz
	@echo
	@echo and now iterating works
	python ./warcio-iterator.py testing.warc.gz
	@echo
