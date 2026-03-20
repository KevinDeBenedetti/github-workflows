# Changelog

## [0.4.0](https://github.com/KevinDeBenedetti/github-workflows/compare/v0.3.0...v0.4.0) (2026-03-20)


### Features

* add VitePress markdown check action and update workflows for centralized docs deployment ([62ff767](https://github.com/KevinDeBenedetti/github-workflows/commit/62ff767e90a64590a7b3c33da56119fd22049381))
* update deployment workflow to directly deploy docs to GitHub Pages ([688549d](https://github.com/KevinDeBenedetti/github-workflows/commit/688549dfd35b9913410923e6b388462788a9049d))

## [0.3.0](https://github.com/KevinDeBenedetti/github-workflows/compare/v0.2.1...v0.3.0) (2026-03-20)


### Features

* add pre-commit hook to check for unescaped Vue interpolations in markdown files ([aef16fd](https://github.com/KevinDeBenedetti/github-workflows/commit/aef16fdf6562afd3d8606bbd637297415ca133d4))


### Bug Fixes

* allow SARIF report upload to continue on error in CodeQL job ([38e2a8d](https://github.com/KevinDeBenedetti/github-workflows/commit/38e2a8d045282afe354fe402104089b844398db3))

## [0.2.1](https://github.com/KevinDeBenedetti/github-workflows/compare/v0.2.0...v0.2.1) (2026-03-19)


### Bug Fixes

* update upload-pages-artifact action to version 4 in CI workflow ([0d7ab07](https://github.com/KevinDeBenedetti/github-workflows/commit/0d7ab077785b9b11a63b051a8e4de16afb07b7a8))

## [0.2.0](https://github.com/KevinDeBenedetti/github-workflows/compare/v0.1.0...v0.2.0) (2026-03-19)


### Features

* add .vitepressrc.json for documentation site configuration ([e0875bb](https://github.com/KevinDeBenedetti/github-workflows/commit/e0875bb43d3f57357db4f0bbd3d5ca4924d8de8a))
* add actionlint for validating GitHub Actions workflow files and remove yamllint ([f1fb3d0](https://github.com/KevinDeBenedetti/github-workflows/commit/f1fb3d0809aa5e8e0d6545081583085628211f2c))
* add actions autoupdate workflow with scheduling capabilities ([a043865](https://github.com/KevinDeBenedetti/github-workflows/commit/a0438651375587c32af1d4f706dca7cebb68d5b8))
* add CI workflows for shell scripts with ShellCheck, yamllint, and Bats tests ([1c93e8e](https://github.com/KevinDeBenedetti/github-workflows/commit/1c93e8e9b7bfe166e43eeba2f9b55f362ca7bfa4))
* Add CI/CD workflows for Node.js, Python, and Docker deployments ([fa0bccf](https://github.com/KevinDeBenedetti/github-workflows/commit/fa0bccfea17c7cce6a8084de4f34ac4cc300cc2f))
* add comprehensive documentation for GitHub Actions workflows and actions ([ba46545](https://github.com/KevinDeBenedetti/github-workflows/commit/ba46545c04923807722d638cf6b08ebdcb76237f))
* add default yamllint configuration and fallback to bundled config in action ([fd816b8](https://github.com/KevinDeBenedetti/github-workflows/commit/fd816b884488a0e53c6c2c5b0acb6814041311f7))
* Add Dependabot configuration files for various package ecosystems ([6402152](https://github.com/KevinDeBenedetti/github-workflows/commit/6402152f8e904dab41387bac7d7eada4e2b60457))
* add dispatch job to CI workflow and update PAT_TOKEN secret reference in dispatch workflow ([c4e99c9](https://github.com/KevinDeBenedetti/github-workflows/commit/c4e99c99982f17d3c17fd47698ea88c74c5703a1))
* add documentation for CI workflows and deployment processes for Node.js, Python, shell, and Docker ([1ac6793](https://github.com/KevinDeBenedetti/github-workflows/commit/1ac6793af4ff9bf6948feee532eebbbaebdc8f52))
* add documentation link check action and integrate into CI workflows ([c91bedb](https://github.com/KevinDeBenedetti/github-workflows/commit/c91bedb2d28c23f8e4e42f49393ad5d2857b76c0))
* add environment variable to force JavaScript actions to Node 24 in setup-bun ([88b2a7b](https://github.com/KevinDeBenedetti/github-workflows/commit/88b2a7bb88a5be1d24bc4338e1818bf37360757a))
* Add Gitleaks secret scanning to security workflow ([ee9606c](https://github.com/KevinDeBenedetti/github-workflows/commit/ee9606c308388be4f92811e588182e60eb2c1ee5))
* add kubeconform action and CI workflow for validating Kubernetes manifests ([242770d](https://github.com/KevinDeBenedetti/github-workflows/commit/242770dd5e65ac9744308009b9ab4522ace6567a))
* add label sync workflow and update sync-todo script for label management ([0ae2be0](https://github.com/KevinDeBenedetti/github-workflows/commit/0ae2be0790d8dade6c29e731ad63967158ca9ea8))
* add link check functionality to CI workflows for markdown files ([8fb305e](https://github.com/KevinDeBenedetti/github-workflows/commit/8fb305e5013aab79c5ffc8b72ce0f0b15cf0a44e))
* add maintenance workflow for purging deployments and workflow runs ([8b92def](https://github.com/KevinDeBenedetti/github-workflows/commit/8b92def143fc8134c8e8f478a2f52cba340c7783))
* add max-age-days input for deployment purge workflow to limit deletion by age ([858bdb4](https://github.com/KevinDeBenedetti/github-workflows/commit/858bdb4f1937532f4896c4d2c501d49390719ced))
* add new workflows for CI, deployment, and security checks ([a377b76](https://github.com/KevinDeBenedetti/github-workflows/commit/a377b7670f641230744e03410f9a86169924e301))
* add optional configuration for yamllint including config file path and strict mode ([8095739](https://github.com/KevinDeBenedetti/github-workflows/commit/8095739930ba010ff65f95de605c78a0fdcfc812))
* add optional GitHub token input for private submodule checkout in CI workflow ([bfa0ca5](https://github.com/KevinDeBenedetti/github-workflows/commit/bfa0ca537a45e0d359ed3050005fe06a5ea11cbc))
* add permissions for security job in test-security workflow ([1f2f53a](https://github.com/KevinDeBenedetti/github-workflows/commit/1f2f53ac08ae96dffa0976fa87a8101e0772ef34))
* add permissions for write access in todo-sync workflow jobs ([8225ac1](https://github.com/KevinDeBenedetti/github-workflows/commit/8225ac1609ed7bc512ff69f33cf656557a45111d))
* add purge-all-repos workflow and documentation for orchestrating maintenance across repositories ([5de5162](https://github.com/KevinDeBenedetti/github-workflows/commit/5de51621ba916166fad855f5c293149c34decc60))
* add purge-caches workflow for managing Action caches ([4863437](https://github.com/KevinDeBenedetti/github-workflows/commit/4863437285238234748309bdc6109ea779964438))
* add release configuration and update CI workflow to use specific action versions ([f504af1](https://github.com/KevinDeBenedetti/github-workflows/commit/f504af1d9a68e1f0e3b2e7b97a44b9f66fbb980f))
* Add reusable workflows for GitHub Pages, Vercel deployment, and maintenance tasks ([64da0f8](https://github.com/KevinDeBenedetti/github-workflows/commit/64da0f8af68b451932aae1ebd5d99d7d64857440))
* add TODO sync and label sync jobs to CI/CD workflow ([b7ce60d](https://github.com/KevinDeBenedetti/github-workflows/commit/b7ce60deab39fe3f85612a54dca6fccb246baf44))
* add TODO.md for backlog and documentation improvements ([afdb417](https://github.com/KevinDeBenedetti/github-workflows/commit/afdb4179d4286a14a7e9282f24e17395d5c79d00))
* add workflow_dispatch inputs for CI workflows and create test workflows for shell and security ([3a3381f](https://github.com/KevinDeBenedetti/github-workflows/commit/3a3381f9f26a7cc29da83cb9f53f953abdcb5782))
* add workflow_dispatch trigger to todo-sync workflow ([5d01859](https://github.com/KevinDeBenedetti/github-workflows/commit/5d018594ed8824f6841d6f656e6b1ffdaf9dd1f9))
* add workflows for bot commit checks and dependabot auto-merge with documentation ([810a9f8](https://github.com/KevinDeBenedetti/github-workflows/commit/810a9f8930852852b0b10a4d4edc9d425cf7bf9d))
* consolidate CI/CD workflows and add reusable test workflows ([60318cc](https://github.com/KevinDeBenedetti/github-workflows/commit/60318ccb42b375896d118173eac689b2b2d513d5))
* enhance CI workflow to include link checking and update documentation ([7614fb2](https://github.com/KevinDeBenedetti/github-workflows/commit/7614fb2eeaab7aa75c27d76ebc9e1b709ae1f52f))
* enhance prek.toml configuration for improved hook management ([a043865](https://github.com/KevinDeBenedetti/github-workflows/commit/a0438651375587c32af1d4f706dca7cebb68d5b8))
* enhance workflows for prek autoupdate and renovate with improved git identity handling and scheduling ([8627f73](https://github.com/KevinDeBenedetti/github-workflows/commit/8627f73d47ac034a14c0ad261b295b78eaba765b))
* implement bidirectional sync between TODO.yml and GitHub Issues ([b473245](https://github.com/KevinDeBenedetti/github-workflows/commit/b4732459736ed325b844c722989b10122bd5c98a))
* implement label synchronization and refactor sync-todo script ([155267e](https://github.com/KevinDeBenedetti/github-workflows/commit/155267e5777271b20182f595eac676814fafd3f6))
* improve PAT_TOKEN description for clarity and usage guidance ([fe78400](https://github.com/KevinDeBenedetti/github-workflows/commit/fe784006c1ae8aed6eda433cd4ccecd242295f14))
* refactor sync-todo script into modular structure and add linting support ([f3df955](https://github.com/KevinDeBenedetti/github-workflows/commit/f3df955ff65d84fa341cef3f659c53f8be921cc3))
* refactor sync-todo script to enhance issue fetching and updating logic ([1d6a95e](https://github.com/KevinDeBenedetti/github-workflows/commit/1d6a95e268021f44a502bc6870da0e50857131d0))
* remove VitePress configuration file as it is no longer needed ([eaf751b](https://github.com/KevinDeBenedetti/github-workflows/commit/eaf751b357971642a2d84c43f7c65bbcf688d311))
* restructure README for improved clarity and organization ([ceceab0](https://github.com/KevinDeBenedetti/github-workflows/commit/ceceab02e8c670789b98a69e5c04720a08a686d6))
* update action versions and improve CI workflows for consistency ([ff91b34](https://github.com/KevinDeBenedetti/github-workflows/commit/ff91b343a2b98edb5dcd3b5427a81855a7cd14c5))
* update action versions and improve workflow configurations across multiple files ([a043865](https://github.com/KevinDeBenedetti/github-workflows/commit/a0438651375587c32af1d4f706dca7cebb68d5b8))
* update actionlint installation path and improve file handling ([d1402e5](https://github.com/KevinDeBenedetti/github-workflows/commit/d1402e5a9493e31dc512e9f41bb8877f795d1d63))
* update Bats installation command to use sudo for proper permissions ([92f3cf1](https://github.com/KevinDeBenedetti/github-workflows/commit/92f3cf1593cee3e8a906f8789f831467fbc2e455))
* update documentation links to use absolute GitHub URLs and add link checking script ([f9c9022](https://github.com/KevinDeBenedetti/github-workflows/commit/f9c90223e0cad987daaf2d1212c4bed010fffbd4))
* update README for improved structure and usage clarity ([6f377f9](https://github.com/KevinDeBenedetti/github-workflows/commit/6f377f9ea81e4923152af364cb146cf894c28cef))
* Update README with detailed structure and reusable workflows for CI/CD actions ([efae6eb](https://github.com/KevinDeBenedetti/github-workflows/commit/efae6eb8d73b399a85e31ff071916a6ff0d3e5c8))
* update release configuration and enhance CI workflow with dynamic path detection ([4669284](https://github.com/KevinDeBenedetti/github-workflows/commit/46692844dbdea72a00cc70ff6279ac281b276aff))


### Bug Fixes

* add write permissions for actions in purge job ([67f2127](https://github.com/KevinDeBenedetti/github-workflows/commit/67f212709acecb65c91206e4d1de170b87319a3c))
* add write permissions for issues in release workflow ([d3e2505](https://github.com/KevinDeBenedetti/github-workflows/commit/d3e25051d8d4920645bc976a5e98cf38fd3b0f53))
* change priority of reusable workflow to low in TODO.yml ([455e59a](https://github.com/KevinDeBenedetti/github-workflows/commit/455e59a45cf609abcf60a9ae9745dfad16350190))
* correct command for type checking in CI workflow ([07a7fc5](https://github.com/KevinDeBenedetti/github-workflows/commit/07a7fc5d6528fc26fd85c2e4e9409eef1cced234))
* disable BATS testing in CI shell workflow ([4b07dc3](https://github.com/KevinDeBenedetti/github-workflows/commit/4b07dc39f0f396cc8a2e12aae262af2745ca02e2))
* enhance maintenance workflow integration in purge-all-repos job ([5f08abf](https://github.com/KevinDeBenedetti/github-workflows/commit/5f08abfa2491dea1df810f3312606fbb807a41ad))
* enhance purge summary reporting with detailed execution parameters and results ([44bd283](https://github.com/KevinDeBenedetti/github-workflows/commit/44bd2833f09f23a0e603f596a88579bc07a24d09))
* ensure consistent formatting and newline handling across workflow files ([b509efd](https://github.com/KevinDeBenedetti/github-workflows/commit/b509efd0397ae222185b31ac56af401b7f4ec480))
* ensure consistent usage and inheritance of secrets in CI/CD workflows ([0b3c8c0](https://github.com/KevinDeBenedetti/github-workflows/commit/0b3c8c0b4476b704acf0927e10cd28fb4d58bdff))
* improve repo filtering and output format in purge-all-repos workflow ([5a8fd75](https://github.com/KevinDeBenedetti/github-workflows/commit/5a8fd7523993078856e31688f28167efb4141d92))
* improve sync mode determination logic in TODO sync workflow ([046f54f](https://github.com/KevinDeBenedetti/github-workflows/commit/046f54f94f0b059cc7aee6113c6a0e20aef12518))
* optimize repo listing and filtering in purge-all-repos workflow ([0669b81](https://github.com/KevinDeBenedetti/github-workflows/commit/0669b8196fe6b7f819d3ac729fcc5c12b158834c))
* remove deprecated renovate workflow and related documentation ([a043865](https://github.com/KevinDeBenedetti/github-workflows/commit/a0438651375587c32af1d4f706dca7cebb68d5b8))
* remove outdated reference to scripts README in todo-sync documentation ([6e63053](https://github.com/KevinDeBenedetti/github-workflows/commit/6e63053fd0aca12af04acf3bd7c82dd20be0edec))
* remove unnecessary permissions from CI/CD workflows ([fa7471d](https://github.com/KevinDeBenedetti/github-workflows/commit/fa7471d21b328b792682893b8917d10b3dbf12b7))
* replace gitleaks-action with direct binary to handle force-push rewritten history ([03cfbae](https://github.com/KevinDeBenedetti/github-workflows/commit/03cfbaeb055335568a37cfb544f2b6f0226256c2))
* trigger centralized maintenance workflow with improved parameters and logging ([0e453c4](https://github.com/KevinDeBenedetti/github-workflows/commit/0e453c440dbe90290688437ad5ada3a8744a1c97))
* update action paths in CI workflow documentation for consistency ([348149e](https://github.com/KevinDeBenedetti/github-workflows/commit/348149e41c7adf06dbd2685770ae0a55cc9c0698))
* Update action paths in workflows and README for consistency ([c7b0fe5](https://github.com/KevinDeBenedetti/github-workflows/commit/c7b0fe5ab399d861825ab567a482833ff95dd941))
* update action versions to v5 for checkout, cache, and setup actions ([2e5e34a](https://github.com/KevinDeBenedetti/github-workflows/commit/2e5e34a8ca28b083839e0c06926f1326e44fff8c))
* Update CodeQL action versions and improve SARIF report upload condition ([f9039a4](https://github.com/KevinDeBenedetti/github-workflows/commit/f9039a404a5bac36b20a1d34998f1dfa57454831))
* update command for pip-audit in Python audit job ([abd0575](https://github.com/KevinDeBenedetti/github-workflows/commit/abd05756b3a3fa64411ad0fdfcdf38b4fa024365))
* update Docker workflow to use latest action versions and improve image reference handling ([b27f6ed](https://github.com/KevinDeBenedetti/github-workflows/commit/b27f6ed3de09917514c24913ae4c2b99859a7fb0))
* update Gitleaks action version and ensure environment variable is set correctly ([d391e1a](https://github.com/KevinDeBenedetti/github-workflows/commit/d391e1a753748ab5b72ff3949a67bac1fad47869))
* update jq command for repo listing in purge-all-repos workflow ([a955b3d](https://github.com/KevinDeBenedetti/github-workflows/commit/a955b3d9763d2735937ccb05344330d7531ff651))
* update link-check-paths description and default value in CI workflows ([a53f016](https://github.com/KevinDeBenedetti/github-workflows/commit/a53f016e7baa72fd6c76bdb96475c2ac6270cfeb))
* update owner retrieval method in purge-all-repos workflow ([4e1f96d](https://github.com/KevinDeBenedetti/github-workflows/commit/4e1f96dbf70fedaf982a35058a462a8b46651f5f))
* Update permissions for secret scanning job to include pull-requests access ([360ea40](https://github.com/KevinDeBenedetti/github-workflows/commit/360ea40d7ac8c968892759bd962e59a87705b15c))
* update repo listing command to use authenticated user/org context ([80dbe1e](https://github.com/KevinDeBenedetti/github-workflows/commit/80dbe1ea3074a22fb1b5fa738ded32df766b90eb))
* update status and priority of feature branch protection workflow issue ([62b98bc](https://github.com/KevinDeBenedetti/github-workflows/commit/62b98bc83194bc4ce36b078660d5a3c0ce8fd4ab))
* update status of feature branch protection workflow to done ([dae47a3](https://github.com/KevinDeBenedetti/github-workflows/commit/dae47a32e3b50b9fadd05a1708b094c9b249ec85))
* update status of label sync workflow issue to done ([295fe40](https://github.com/KevinDeBenedetti/github-workflows/commit/295fe40353a7104445aa60813d7f681bae79fb94))
* update status of TODO item to in-progress ([b7ce60d](https://github.com/KevinDeBenedetti/github-workflows/commit/b7ce60deab39fe3f85612a54dca6fccb246baf44))
* update test command to support 'bun' package manager in CI workflow ([33a7f9a](https://github.com/KevinDeBenedetti/github-workflows/commit/33a7f9a54e431acdcc78644f0e15b984d703f8d4))
* update upload-artifact action to version 7 in CI workflow ([bfefdb5](https://github.com/KevinDeBenedetti/github-workflows/commit/bfefdb5cea417391cc0a0939d5f8e550dceb3270))
* use npm for global Vercel CLI install ([924a54e](https://github.com/KevinDeBenedetti/github-workflows/commit/924a54e3f94a19212c31fc6953cd07841b3fea4f))
