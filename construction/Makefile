construct-paths:
	@echo download the names of all of the warc/wet/wat files in CC-MAIN-2024-22
	aws s3 cp s3://commoncrawl/crawl-data/CC-MAIN-2024-22/warc.paths.gz .
	aws s3 cp s3://commoncrawl/crawl-data/CC-MAIN-2024-22/wet.paths.gz .
	aws s3 cp s3://commoncrawl/crawl-data/CC-MAIN-2024-22/wat.paths.gz .

construct-warcs:
	@echo download a coordinated set of a single warc/wet/wat
	wget https://data.commoncrawl.org/crawl-data/CC-MAIN-2024-22/segments/1715971057216.39/warc/CC-MAIN-20240517233122-20240518023122-00000.warc.gz
	wget https://data.commoncrawl.org/crawl-data/CC-MAIN-2024-22/segments/1715971057216.39/wat/CC-MAIN-20240517233122-20240518023122-00000.warc.wat.gz
	wget https://data.commoncrawl.org/crawl-data/CC-MAIN-2024-22/segments/1715971057216.39/wet/CC-MAIN-20240517233122-20240518023122-00000.warc.wet.gz

construct-extract:
	@echo Greg picked records out of this warc/wet/wat trio related to a single web capture
