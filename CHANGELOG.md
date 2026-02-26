# Changelog

## [1.1.0](https://github.com/zerochae/dbab.nvim/compare/v1.0.0...v1.1.0) (2026-02-26)


### Features

* phase 1 isolate schema cache per connection URL ([f2d6394](https://github.com/zerochae/dbab.nvim/commit/f2d6394e081ad102a321f2e2852623c58f6e316c))
* phase 2 apply tab-aware connection context across UI and completion ([d185503](https://github.com/zerochae/dbab.nvim/commit/d185503538fd708490482b202ed91a0f2e71fbac))
* support per-tab connection context and URL-isolated cache ([938c387](https://github.com/zerochae/dbab.nvim/commit/938c3870f48a534e88a1bc469815ede6bb272cc1))


### Bug Fixes

* phase 3 avoid zsh glob expansion in cli executor ([2e0ae67](https://github.com/zerochae/dbab.nvim/commit/2e0ae677cef7da93623c02ac24e370a3a6bf6c82))

## 1.0.0 (2026-02-19)


### Features

* add blink.cmp source for SQL autocompletion ([3283bd1](https://github.com/zerochae/dbab.nvim/commit/3283bd14d0f762960e2ee86e3e0476d8fc07da7e))
* add blink.cmp source for SQL autocompletion ([bacd39e](https://github.com/zerochae/dbab.nvim/commit/bacd39eb3357096ff3dde71aff7d140287d92411))
* **config:** make keymaps fully configurable and update docs ([91082f6](https://github.com/zerochae/dbab.nvim/commit/91082f6ee986466f4b301bb67628f22e8bd1fb97))
* **connection:** add mariadb support as mysql alias ([faceaf1](https://github.com/zerochae/dbab.nvim/commit/faceaf1429e1b044808b63377c91e71aea839747))
* **grid:** add result display styles (table, json, vertical, markdown, raw) ([18f0fbc](https://github.com/zerochae/dbab.nvim/commit/18f0fbc21e05fbba76be1868409689c09a2308a3))
* **highlights:** support highlight overrides via setup config ([a4e5747](https://github.com/zerochae/dbab.nvim/commit/a4e574799009b01e7620f62565a5c0729827cc05))
* **history:** add detailed style with multi-line query display ([84ce09c](https://github.com/zerochae/dbab.nvim/commit/84ce09c62d9ec1cd34bbe81f09dd55651e447fa1))
* initial release of dbab.nvim ([a46577a](https://github.com/zerochae/dbab.nvim/commit/a46577abae09e137ccb8961aa89ea2d43cc5f69a))
* self-contained CLI executor, make vim-dadbod optional ([c2939d4](https://github.com/zerochae/dbab.nvim/commit/c2939d464ee5629e6d105e3ffcf28dfcc98be727))
* **sidebar:** centralize icons and add DB brand config ([e54c0d2](https://github.com/zerochae/dbab.nvim/commit/e54c0d2ff74e8e7db58ee40fcf3951bbd88eae5c))
* **ui:** add flexible layout system with presets ([d31dd05](https://github.com/zerochae/dbab.nvim/commit/d31dd05d232f78357715e1b4f60d0f9755711120))
* **ui:** improve result display and winbar alignment ([d4a2dcc](https://github.com/zerochae/dbab.nvim/commit/d4a2dcc8c2e706c6677baa7001d02551aa2c36d1))


### Bug Fixes

* add DbabClose command and fix No Name buffer on open ([da670a4](https://github.com/zerochae/dbab.nvim/commit/da670a418bb2f775c15d4e0faa4ddb0191316945))
* **executor:** fallback to mysql if mariadb command is missing ([78b9ab2](https://github.com/zerochae/dbab.nvim/commit/78b9ab20984dd2295b3638afe96a1a81a6a4effd))
* **executor:** robust check for mariadb executable before usage ([3a9106f](https://github.com/zerochae/dbab.nvim/commit/3a9106f1f870475c9a50c75668f9ede5243c9df7))
* **parser:** filter out mysql insecure password warning ([198c04e](https://github.com/zerochae/dbab.nvim/commit/198c04e5302f3038e87a93abf9f25265fa5a4449))
* **tests:** update config tests for flat config structure ([3c71093](https://github.com/zerochae/dbab.nvim/commit/3c710935059dbcaa7c142c16048fbbe178b6842b))
