SOURCES := $(wildcard src/*.h src/*.m)

.PHONY: build format lint

build:
	./build.sh

format:
	xcrun clang-format -i $(SOURCES)

lint:
	xcrun clang-format --dry-run --Werror $(SOURCES)
	./build.sh
