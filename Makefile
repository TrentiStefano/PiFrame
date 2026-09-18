.PHONY: setup codegen lint test test-e2e run-daemon run-app build-all

setup:
	pnpm run setup

codegen:
	pnpm run codegen

lint:
	pnpm run lint

test:
	pnpm run test

test-e2e:
	pnpm run test:e2e

run-daemon:
	pnpm run run:daemon

run-app:
	pnpm run run:app

build-all:
	pnpm run build:all
