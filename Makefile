.PHONY: test test-file lint

# Run all tests
test:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

# Run a specific test file
# Usage: make test-file FILE=tests/core/storage_spec.lua
test-file:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile $(FILE)"

# Run tests with verbose output
test-verbose:
	nvim --headless -u tests/minimal_init.lua -c "lua require('plenary.test_harness').test_directory('tests/', {minimal_init = 'tests/minimal_init.lua', sequential = true})"
