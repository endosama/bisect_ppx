# Test targets:
# - test: Run standard test with rescript
# - test-rewatch: Run test with rewatch (includes path workaround)
# - test-all: Run both tests
# - full-test: Clean install and run standard test
# - full-test-all: Clean install and run all tests

.PHONY : test
test :
	rm -rf _coverage *.coverage
	npm run instrument
	npm run execute
	./node_modules/.bin/bisect-ppx-report html
	./node_modules/.bin/bisect-ppx-report summary | diff expected -
	./node_modules/.bin/bisect-ppx-report summary
	@echo "See _coverage/index.html."

.PHONY : test-rewatch
test-rewatch :
	rm -rf _coverage *.coverage lib
	@echo "Testing rewatch build..."
	@echo "Setting up rewatch path workaround..."
	mkdir -p ../../node_modules/@endosama/bisect_ppx
	cp ./package/ppx ../../node_modules/@endosama/bisect_ppx/ppx
	cp ./package/bisect-ppx-report ../../node_modules/@endosama/bisect_ppx/bisect-ppx-report
	cp ./package/package.json ../../node_modules/@endosama/bisect_ppx/package.json
	cp ./package/bsconfig.json ../../node_modules/@endosama/bisect_ppx/bsconfig.json
	cp -r ./package/lib ../../node_modules/@endosama/bisect_ppx/lib 2>/dev/null || true
	cp -r ./package/src ../../node_modules/@endosama/bisect_ppx/src 2>/dev/null || true
	npm run test-rewatch
	npm run execute
	./node_modules/.bin/bisect-ppx-report html
	./node_modules/.bin/bisect-ppx-report summary | diff expected -
	./node_modules/.bin/bisect-ppx-report summary
	@echo "Cleaning up rewatch workaround..."
	rm -rf ../../node_modules/@endosama/bisect_ppx
	@echo "Rewatch test passed! See _coverage/index.html."

.PHONY : test-all
test-all : 
	@echo "Running rescript test..."
	$(MAKE) test
	@echo "Cleaning artifacts between tests..."
	rm -rf _coverage *.coverage lib
	@echo "Running rewatch test..."
	$(MAKE) test-rewatch
	@echo "All tests passed!"

.PHONY : full-test
full-test : clean install test

.PHONY : full-test-all
full-test-all : clean install test-all

.PHONY : install
install :
	npm pack ../..
	tar xf *.tgz
	npm install
	npm list || true

.PHONY : clean
clean :
	rm -rf node_modules lib _esy *.tgz package *.coverage _coverage \
	  package-lock.json

.PHONY : clean-for-caching
clean-for-caching :
	npm uninstall --no-save bisect_ppx || true
	rm -rf node_modules/bisect_ppx
