CC ?= clang
CFLAGS ?= -std=c99 -Wall -Wextra -O2 -Isrc/c/include -I/opt/homebrew/include -I/usr/local/include
LDFLAGS ?= -L/opt/homebrew/lib -L/usr/local/lib -lwren
WREN_CLI ?= wren_cli

SRC_C = $(wildcard src/c/*.c)
OBJ_C = $(SRC_C:.c=.o)
BIN = bin/keelson

.PHONY: all build test test-c test-wren test-python lint clean run-example

all: build

build: $(BIN)

$(BIN): $(SRC_C)
	@mkdir -p bin data/wal data/test_wal
	$(CC) $(CFLAGS) -o $(BIN) $(SRC_C) $(LDFLAGS)

lint:
	@./tools/lint_em_dashes.sh

test: build lint test-wren test-python

test-wren:
	@mkdir -p data/wal data/test_wal
	@echo "Running Wren test suite via native host..."
	@./$(BIN) test

test-python:
	@echo "Running Python SDK test suite..."
	@cd sdk/python && python3 -m unittest discover tests

test-cli:
	@mkdir -p data/wal data/test_wal
	@echo "Running Wren test suite via wren_cli..."
	@$(WREN_CLI) test/test_runner.wren

run-example: build
	@./$(BIN) run examples/e_commerce_order_saga.wren

clean:
	rm -rf bin build *.o data/test_wal

