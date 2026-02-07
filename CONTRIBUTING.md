# Contributing to dbab.nvim

First off, thanks for taking the time to contribute! 🎉

The following is a set of guidelines for contributing to `dbab.nvim`. These are mostly guidelines, not rules. Use your best judgment and feel free to propose changes to this document in a pull request.

## Code Style

*   We use **Lua**.
*   Please format your code using `stylua` if possible.
*   Follow the existing code style (indentation with 2 spaces).

## How to Submit a Pull Request

1.  Fork the repo and create your branch from `main`.
2.  If you've added code that should be tested, add tests.
3.  If you've changed APIs, update the documentation (`doc/dbab.txt`).
4.  Ensure the test suite passes.
5.  Make sure your code lints.
6.  Submit that pull request!

## Reporting Bugs

Bugs are tracked as GitHub issues. When filing an issue, please explain the problem and include additional details to help maintainers reproduce the problem:

*   Use a clear and descriptive title.
*   Describe the exact steps to reproduce the problem.
*   Provide your configuration setup.
*   Check if the issue persists with a minimal config.

## Running Tests

We use `plenary.nvim` for testing. You can run tests using:

```bash
make test
```

(Or directly with nvim command if you don't have make)

Thank you for your contributions!
