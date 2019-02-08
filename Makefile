CC ?= clang
CFLAGS ?= -std=c99 -Wall -Wextra -O2 -Isrc/c/include
WREN_CLI ?= wren_cli

SRC_C = $(wildcard src/c/*.c)
OBJ_C = $(SRC_C:.c=.o)
BIN = bin/keelson

.PHONY: all build test lint clean run-example

all: build

build: $(BIN)

$(BIN): $(SRC_C)
	@mkdir -p bin
	@if [ -d "src/c" ] && [ -n "$$(ls -A src/c/*.c 2>/dev/null)" ]; then \
		$(CC) $(CFLAGS) -o $(BIN) $(SRC_C) -lwren 2>/dev/null || \
		$(CC) $(CFLAGS) -o $(BIN) $(SRC_C) -I/opt/homebrew/include -L/opt/homebrew/lib -lwren 2>/dev/null || \
		echo "Native host will be linked once C modules are ready."; \
	fi

lint:
	@./tools/lint_em_dashes.sh

test: lint
	@echo "Running Wren test suite..."
	@$(WREN_CLI) test/test_runner.wren

run-example:
	@$(WREN_CLI) examples/e_commerce_order_saga.wren

clean:
	rm -rf bin build *.o
