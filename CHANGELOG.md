# Changelog

## [1.5.1](https://github.com/TrentiStefano/PiFrame/compare/v1.5.0...v1.5.1) (2026-11-20)


### Bug Fixes

* **web:** keep dart:ffi out of the web build so release installers build ([fe66104](https://github.com/TrentiStefano/PiFrame/commit/fe6610480344184277e133c2df2bcffccafdbde7))
* **web:** keep dart:ffi out of the web build so release installers build ([02f556c](https://github.com/TrentiStefano/PiFrame/commit/02f556cc39e7f132c595421b7185267f424d602d))

## [1.5.0](https://github.com/TrentiStefano/PiFrame/compare/v1.4.1...v1.5.0) (2026-11-20)


### Features

* add verified package updates and update-all controls ([a111a50](https://github.com/TrentiStefano/PiFrame/commit/a111a5096958da156e57d3f571f4693cf141a196))
* **agentd:** session list carries firstUserPrompt for provisional titles (task 5.1) ([29965e9](https://github.com/TrentiStefano/PiFrame/commit/29965e909e7f0fe9cfbf7393a9273111025b6f85))
* **app:** stage Pi slash commands as a chip, never as text ([611075f](https://github.com/TrentiStefano/PiFrame/commit/611075ff6a24bd93e90541a60a490331aaaf8aed))
* **chat:** move the agent's tasks into a Tasks tab of the side panel ([959d9c2](https://github.com/TrentiStefano/PiFrame/commit/959d9c2bad190bd0990e37c32bc75a665518f1e0))
* **dev:** log daemon output and event-loop stalls to runtime/daemon.log ([30dd399](https://github.com/TrentiStefano/PiFrame/commit/30dd39934f719df676ef926623798003866cea82))
* **dev:** log slow app commands to daemon.log ([685fd9f](https://github.com/TrentiStefano/PiFrame/commit/685fd9f20b9d8d1bf79d89245bfc43d2dc850a0d))
* **dev:** optional CPU profile of the daemon for stall analysis ([696d318](https://github.com/TrentiStefano/PiFrame/commit/696d31892d01cf7ee0b181029bd29d703cd91ba9))
* **dev:** run dev builds with their own state folder ([1225d2d](https://github.com/TrentiStefano/PiFrame/commit/1225d2d2d6f7436b65934106e48643679fa88bf3))
* **git:** add fetch, pull, push and sync buttons to Git Changes ([f39924d](https://github.com/TrentiStefano/PiFrame/commit/f39924d16474aed8a1752da0c9885507e2a72029))
* **harness:** add off-screen UI harness for agent-driven PiFrame testing ([5f40624](https://github.com/TrentiStefano/PiFrame/commit/5f406242d37a223394381b016df7c96405e25d92))
* **harness:** default to a 1920x1032 app area and size the content, not the window ([810d7a1](https://github.com/TrentiStefano/PiFrame/commit/810d7a1d8b55899b0e2b68522389262d6538a220))
* **harness:** make PiFrame UI states verifiable offline ([fb7fdbd](https://github.com/TrentiStefano/PiFrame/commit/fb7fdbdac1884cf6e883acde4cf74d75d636c709))
* **harness:** run with animations on and record animations as frame sequences ([c6dd441](https://github.com/TrentiStefano/PiFrame/commit/c6dd4415d091b5826c8b6a318665e35fe7b896f6))
* **notifications:** add safe Win32 COM taskbar loading animation on Windows ([456fdfc](https://github.com/TrentiStefano/PiFrame/commit/456fdfc197be70d405510ffd718b6432f4101c7d))
* **notifications:** add taskbar working animation and unread notification dot ([4e6f69f](https://github.com/TrentiStefano/PiFrame/commit/4e6f69f618b21edf85a2f36e1b56029a81d36672))
* **settings:** display model provider as subtitle in model dropdowns ([de5ece3](https://github.com/TrentiStefano/PiFrame/commit/de5ece3f2337580de54538d967455b0588435456))
* **tasks:** remove status badges, add text shimmer for in-progress tasks, and move add task to bottom ([80e56e4](https://github.com/TrentiStefano/PiFrame/commit/80e56e4d9575dc1a012368dfa90ca0ef0f53a9a0))
* **ui:** add Full step grouping mode with animated live step switcher ([06bc848](https://github.com/TrentiStefano/PiFrame/commit/06bc848aad73550fe66e6c7792120118f7f62233))
* **ui:** add text shimmer to working step group header and smooth step fade transition ([725eec4](https://github.com/TrentiStefano/PiFrame/commit/725eec4fd04ffb551afffe25460a5e96b79e4ee5))
* **ui:** add three dots progress indicator to shimmering step group header ([b99d9d2](https://github.com/TrentiStefano/PiFrame/commit/b99d9d25f8afbb577c8aecf696db83a3fa238e64))
* **ui:** animated pane show, hide and collapse (task 7.3, P1-16 Spec A) ([868d295](https://github.com/TrentiStefano/PiFrame/commit/868d29593708d7566954156f5e95e1d82d61ee3b))
* **ui:** code-grade editor, save/dirty state, tree and header (tasks 9.1-9.3) ([8a62e85](https://github.com/TrentiStefano/PiFrame/commit/8a62e851b0e07022f9673e498a2598e8d7d8cbbd))
* **ui:** command palette key caps, groups and applicable commands (task 6.5) ([a5e2557](https://github.com/TrentiStefano/PiFrame/commit/a5e255798a6ba5ffbdf2ab505da7c2a7078806ea))
* **ui:** composer controls, chip budget and review state (task 4.4) ([ed692c1](https://github.com/TrentiStefano/PiFrame/commit/ed692c1e62ecde753697e72e57ad8a12da4b1464))
* **ui:** composer stays visible while streaming (task 4.3) ([7ffaf46](https://github.com/TrentiStefano/PiFrame/commit/7ffaf46b8fb41d736c70ea9fda9298563bf9db96))
* **ui:** context drawer as one heading and three sections (task 5.5) ([91c25a9](https://github.com/TrentiStefano/PiFrame/commit/91c25a9769821f097818784d23279d7c1228a061))
* **ui:** empty chat focuses the composer on appear (task 4.6) ([5ab0a95](https://github.com/TrentiStefano/PiFrame/commit/5ab0a9511e983aa57e9494a710dfd1c2acf3561d))
* **ui:** FrameListRow minHeight, 32 px for rail session rows (task 5.1) ([589109e](https://github.com/TrentiStefano/PiFrame/commit/589109ecf7529866caeddbfc4583d47d748062d2))
* **ui:** FrameSwitcher preset and FrameExpandable collapse timing (task 7.2) ([5313465](https://github.com/TrentiStefano/PiFrame/commit/53134656c45b093800dd9625f1604de4bc7f1faa))
* **ui:** Git diff opens inside the companion pane (task 3.2) ([c23e406](https://github.com/TrentiStefano/PiFrame/commit/c23e4067006fc0ac9a64392353dc2ab38a518292))
* **ui:** inline commit form in the Git pane (task 3.5) ([2980e09](https://github.com/TrentiStefano/PiFrame/commit/2980e095d41d396a42bce79149d385c4fc05b1b4))
* **ui:** keyboard access for every pane divider (task 6.7) ([92818d5](https://github.com/TrentiStefano/PiFrame/commit/92818d5d1f1aa7f0ec377afe7c221fca575bdf75))
* **ui:** neutral Interrotto tag on aborted assistant turns (task 4.7, R5) ([249ab75](https://github.com/TrentiStefano/PiFrame/commit/249ab75f4f18948674ceae9ab43913bc48b52196))
* **ui:** ordered Tab traversal, F6 and Ctrl+1..4 between panes (task 6.2) ([3e85fa7](https://github.com/TrentiStefano/PiFrame/commit/3e85fa7b2d335f42eb7a5d354b6476f889967125))
* **ui:** persist pane weights, collapsed panes and companion tabs (task 6.6) ([99486f9](https://github.com/TrentiStefano/PiFrame/commit/99486f92c0ee47438bf6aba94c4e80de88a5a111))
* **ui:** session tree dialog on FrameDialog with branch connectors (task 5.6) ([fbbbb5f](https://github.com/TrentiStefano/PiFrame/commit/fbbbb5f8aca84ad334cf8058c16c5ddff355e012))
* **ui:** sessions rail one-click switching, provisional titles, keyboard (task 5.1) ([82eca49](https://github.com/TrentiStefano/PiFrame/commit/82eca498f0a778a5bad95b4a8fdabbc032691b23))
* **ui:** shared primitives FrameSection, FrameCallout, FrameEmptyState, FrameSearchField, FrameDialog (task 2.3 group B) ([32dabcf](https://github.com/TrentiStefano/PiFrame/commit/32dabcf243d2786b133eb2f4c57c7543e7c468f5))
* **ui:** shared primitives group A (task 2.3) ([6ad2a67](https://github.com/TrentiStefano/PiFrame/commit/6ad2a678ef2ff5014f2767128aa31cbb40831b21))
* **ui:** shell shortcuts for new session, settings, rail and previous session (task 6.4) ([4a42ad7](https://github.com/TrentiStefano/PiFrame/commit/4a42ad7273f811e3052e8f1fd14cd964ab8aff7c))
* **ui:** side conversation splits the chat pane (task 10.1) ([01ae8be](https://github.com/TrentiStefano/PiFrame/commit/01ae8bef3c11f80aa6372d89f7922caeeeda46c4))
* **ui:** snackbar motion, timing and focusable card (task 7.6, Spec G) ([4716527](https://github.com/TrentiStefano/PiFrame/commit/4716527db861afc2b9c3940a7cc155ac62a2527c))
* **ui:** spacing, type, size, motion and inputBorder tokens (task 2.1) ([eded40e](https://github.com/TrentiStefano/PiFrame/commit/eded40e13eec3323e812a8f527f35b9f31900480))
* **ui:** stage and unstage rows travel between groups (task 7.4, Spec F) ([0bb34ff](https://github.com/TrentiStefano/PiFrame/commit/0bb34ff5ee8bfa55f302b89776dcf0ee1ea0ecf2))
* **ui:** title bar groups, Sessione label and connection to Diagnostics (task 5.4) ([26e7d20](https://github.com/TrentiStefano/PiFrame/commit/26e7d20c24af7a4440c0e130979dce70aaf23858))
* **ui:** uniform Escape closes the topmost layer (task 6.3) ([74dc840](https://github.com/TrentiStefano/PiFrame/commit/74dc840b5246586d9a14f4a10d393d10cb26b89c))
* **ui:** visible keyboard focus ring for controls (task 2.2) ([8c74f58](https://github.com/TrentiStefano/PiFrame/commit/8c74f58f856a0e84027088404fc6e0412ec00fa0))
* **ui:** welcome as a resume surface and new-session dialog (tasks 5.2, 5.3) ([e90c1ce](https://github.com/TrentiStefano/PiFrame/commit/e90c1cea017262e3684bc3a54ca0100781ec73a8))
* **updates:** show changelog popup on post-update first launch ([191e1cc](https://github.com/TrentiStefano/PiFrame/commit/191e1ccdb9c4ae274a74c2d2244793c0fc64dd55))


### Bug Fixes

* **agentd:** wake the WSL distro before starting a Pi worker ([6edba33](https://github.com/TrentiStefano/PiFrame/commit/6edba338d3ac4b2a6a47dbbbddd4cf4a0b418435))
* **agents:** apply subagent model/thinking overrides under @tintinweb/pi-subagents ([6ed4c0f](https://github.com/TrentiStefano/PiFrame/commit/6ed4c0feed5dc4389794d8216a66fe9f72d7ce71))
* **agents:** keep the Agents pane closed while subagents run and settle orphaned runs ([71fd988](https://github.com/TrentiStefano/PiFrame/commit/71fd9889a1871c46edd19d9d03f3ca05412f24c0))
* **agents:** list running agents first, then settled, newest launch on top ([bd0945c](https://github.com/TrentiStefano/PiFrame/commit/bd0945c7a0f0362feb8c72c93210ca1875298c84))
* **agents:** stop horizontal jitter on agent rows built while scrolling ([dff38a6](https://github.com/TrentiStefano/PiFrame/commit/dff38a63aaeb8cb14dab4fd16df93acd82e3b369))
* **app:** render subagent notifications whose result has a code fence ([6b72928](https://github.com/TrentiStefano/PiFrame/commit/6b72928485f29599739fa8dda18d18ebba54239e))
* **app:** respect reduced motion in the command chip and slash menu ([afe012f](https://github.com/TrentiStefano/PiFrame/commit/afe012fa732f9c5fd318a3efacef0be6261569cf))
* **app:** tight text selection, keep last 5 prompts in transcript ([4a69b1b](https://github.com/TrentiStefano/PiFrame/commit/4a69b1bf420f61ad5d15be47312e23b85d0492a1))
* **app:** wait longer for the daemon health check before treating it as dead ([bba158c](https://github.com/TrentiStefano/PiFrame/commit/bba158c290a623a263e2d116e1ae1dad6a7c05a7))
* **chat:** one hide button for the plugins pane, and a visible resize line ([5146713](https://github.com/TrentiStefano/PiFrame/commit/51467138bf05f2cdbfb511b4a8c06e2914d1f64c))
* **composer:** keep the chat input expanded while a steer is queued ([885af6a](https://github.com/TrentiStefano/PiFrame/commit/885af6ab6ae4b4af19b8ccd2f4647c84491c9eb7))
* **composer:** restore ring glow animation around active chat input box ([5f5ca0a](https://github.com/TrentiStefano/PiFrame/commit/5f5ca0a06d01ecb82c6dddf968e2b1e057aeecd7))
* **daemon:** queue a prompt as follow-up when Pi is still busy ([8450f17](https://github.com/TrentiStefano/PiFrame/commit/8450f17a412ac2da0418a6a86ca266f394fdabbe))
* **daemon:** start the Pi worker on session.create to avoid a multi-second stall on the first prompt ([5086f10](https://github.com/TrentiStefano/PiFrame/commit/5086f10c35c4ef221a130f45d61468c74ff6de69))
* **harness:** create run home before writing fake-pi shims ([ee7611f](https://github.com/TrentiStefano/PiFrame/commit/ee7611f2a933e2b7a0b3e88407cf571146e1f233))
* **harness:** name the resize polling timers for the design-literal ratchet ([c60acca](https://github.com/TrentiStefano/PiFrame/commit/c60acca65504d00ecc50a6ad28f3a1efa4973d25))
* **layout:** readable half-width window: docked Agents panel, wrapping pane headers ([1ed14ee](https://github.com/TrentiStefano/PiFrame/commit/1ed14eee75eb189997a2665b9fce275b5785cbdd))
* **notifications:** avoid native setProgressBar crash on Windows in window_manager ([77c2b5d](https://github.com/TrentiStefano/PiFrame/commit/77c2b5d6503b979c4a972296f3aaab6d51178d56))
* **notifications:** notify only for the agent's final answer ([13a5db7](https://github.com/TrentiStefano/PiFrame/commit/13a5db73939cfbb839d732c44e5e25d35c7fbb9f))
* **pins:** keep test pin notifiers in memory ([536c1e3](https://github.com/TrentiStefano/PiFrame/commit/536c1e3af7f7b9527023ddac4b518c685e69b1c9))
* **remote-e2e:** isolate Pi sessions and support device profiles ([b6ef109](https://github.com/TrentiStefano/PiFrame/commit/b6ef109ae89431d665d32d619d71a2bf34149c7d))
* **server:** do not drop a connection whose pong or hello is waiting to be read ([ba168c1](https://github.com/TrentiStefano/PiFrame/commit/ba168c1c5d7db3572301245b837e36d28f4258d8))
* **sessions:** add a visible separator between pinned sessions and repositories ([b3d3c2c](https://github.com/TrentiStefano/PiFrame/commit/b3d3c2c522ac265174845a8854143e741acaacb3))
* **sessions:** notification dot, working spinner and a keyboard-only cursor in the sessions rail ([5a91cc8](https://github.com/TrentiStefano/PiFrame/commit/5a91cc8c89d6b925040e2a730f6ccc8cc0da3261))
* **sessions:** remove redundant loading animation from pinned sessions title ([3c56521](https://github.com/TrentiStefano/PiFrame/commit/3c5652122ef95914ec75b14f72aea94eee52d382))
* **sessions:** remove shimmering from session cards, keeping static circular border ([4dbd6a2](https://github.com/TrentiStefano/PiFrame/commit/4dbd6a2c3076dde974373554ff17667b4cb796d9))
* **sessions:** visible working border, steady repository rows, and recorder fixes ([de50218](https://github.com/TrentiStefano/PiFrame/commit/de502182e83929e111d0a946982f8c910c59b3c5))
* **settings:** stack the MCP row buttons under the text in narrow cards ([f32108e](https://github.com/TrentiStefano/PiFrame/commit/f32108e74e4d090eb72cc7980e341e9797b00f0f))
* **side:** let the read-only badge shrink so the side header never overflows ([771899f](https://github.com/TrentiStefano/PiFrame/commit/771899f4f42a3e98b499e33cd957a056188a66db))
* **side:** open side conversations in companion sidecar with session history ([f09db1b](https://github.com/TrentiStefano/PiFrame/commit/f09db1b5ed1829a120a7f8d343149b1e3a874c06))
* steer during compaction and accurate context after model switch ([808c6ab](https://github.com/TrentiStefano/PiFrame/commit/808c6abf5df754ec80ddaee68ac85f6d44276a43))
* **subagents:** read pi-subagents' live state and stop agents for real ([2f9a4ad](https://github.com/TrentiStefano/PiFrame/commit/2f9a4ad58c19ae387815cb087145345f84bb2469))
* **tools:** drop pnpm's -- separator before forwarding gh args ([7d0e55a](https://github.com/TrentiStefano/PiFrame/commit/7d0e55af0791cf3db50b108be6ab04ddff976321))
* **tools:** pass gh arguments without a shell on Windows ([a2c7e50](https://github.com/TrentiStefano/PiFrame/commit/a2c7e5005e295087986af6209403fadef9e78ea4))
* **transcript:** drop the duplicate "Processing…" spinner under a running step group ([fc4e6f4](https://github.com/TrentiStefano/PiFrame/commit/fc4e6f413abc44a0b447e73b93caef8ba602e4f6))
* **transcript:** show a direct answer in the final-answer card ([bd5b3cf](https://github.com/TrentiStefano/PiFrame/commit/bd5b3cf2ba2554e883dc7264dc2ba507596372a5))
* **transcript:** stop assuming a hardcoded WSL distro when opening Linux paths ([692d963](https://github.com/TrentiStefano/PiFrame/commit/692d9633a0bcd0f1b37408901d98a5ee899e8044))
* **transcript:** stop pulling a scrolled-up reader to the bottom while the agent answers ([047c3c9](https://github.com/TrentiStefano/PiFrame/commit/047c3c9f60b4c28df62b764c0c409e3096b25cc4))
* **transcript:** window by last 10 agent answers and avoid premature card borders ([c1441b2](https://github.com/TrentiStefano/PiFrame/commit/c1441b243815ba061f58566fecda7a34b039ffbe))
* **ui:** 28 px hit target for the copy action on a 24 px meta line (task 4.1) ([b705ea7](https://github.com/TrentiStefano/PiFrame/commit/b705ea74b65f8a779de37e48aa413b70cf77f05e))
* **ui:** 28 px rail hit targets and a non-GestureDetector folder row (task 2.6) ([fc56339](https://github.com/TrentiStefano/PiFrame/commit/fc563396ec76cb346663ffa933679cc2eaddacf2))
* **ui:** Agents overlay sheet stops above the composer (task 1.2d) ([de2b5d7](https://github.com/TrentiStefano/PiFrame/commit/de2b5d7d0220cbcdce62a421c4bc44efc772dfa8))
* **ui:** Agents sidecar floats over a narrow chat pane (task 1.2d) ([2c11ad4](https://github.com/TrentiStefano/PiFrame/commit/2c11ad471ac3144036cfa220a0441fcde186de50))
* **ui:** agents tab empty state, dirty-only save bar and model defaults (task 8.3) ([58d2578](https://github.com/TrentiStefano/PiFrame/commit/58d257816ea460482da604db135a379ab62b4395))
* **ui:** analyzer infos in diff_block; localize Git Changes headers ([a68d0e0](https://github.com/TrentiStefano/PiFrame/commit/a68d0e0dee963ee7fd01721a43cd9094d05bf332))
* **ui:** anchor startup update banner top-right, flat (task 1.4) ([45063e5](https://github.com/TrentiStefano/PiFrame/commit/45063e51a632054374f26ac1124b00acdcb14b1a))
* **ui:** borderless step group with a 28 px summary row (task 4.2) ([59548b5](https://github.com/TrentiStefano/PiFrame/commit/59548b50e027b3eb1f7aa3e90454a97d97fe3c96))
* **ui:** branch picker no-match state offers one action (plan §13 item 7) ([27ab7f4](https://github.com/TrentiStefano/PiFrame/commit/27ab7f41f3d648a5c8b778fcc7f91993c32cc028))
* **ui:** branch picker sizing and fixed column grid (task 6.5) ([ec8bc38](https://github.com/TrentiStefano/PiFrame/commit/ec8bc38b0e97f04e7110db4a8b6bafb4c6b6a3c1))
* **ui:** browser tab strip moves into the companion title bar (task 10.2) ([5dc0d07](https://github.com/TrentiStefano/PiFrame/commit/5dc0d0746190b3ef6c52a956f223b9ee31a27ccc))
* **ui:** chat geometry, flat session header, empty chat, focusable file links (tasks 4.1, 4.5, 4.6, 6.1, 2.5) ([175cd8c](https://github.com/TrentiStefano/PiFrame/commit/175cd8c40f3f63d8294b806049755d40e51c0cc2))
* **ui:** click-launched dialogs use the frame dialog route ([1947137](https://github.com/TrentiStefano/PiFrame/commit/1947137598d9ed93ae64aa389498bbd922d82286))
* **ui:** clip Git list so group headers never overlap summary (task 1.3) ([cfc4dc3](https://github.com/TrentiStefano/PiFrame/commit/cfc4dc37b24341cb698ba703763b136d82e7af1d))
* **ui:** commit form keeps a gap above the remote buttons (task 3.5) ([4a93c42](https://github.com/TrentiStefano/PiFrame/commit/4a93c42d977f7edbd6b76f4b0669a8b4f6366200))
* **ui:** compact companion tabs show accent, underline and run status (task 10.3) ([2ef7e42](https://github.com/TrentiStefano/PiFrame/commit/2ef7e42a03c0e4f1d9e8f4527cf56394adbbcc01))
* **ui:** compact Git action bar puts Commit full width (task 3.7) ([c991ef4](https://github.com/TrentiStefano/PiFrame/commit/c991ef4e4d4c29fd7ce9d1549aeb8b5fd18c1e48))
* **ui:** compact tab underline uses the chassis token, not Colors.transparent (task 10.3) ([0a3f004](https://github.com/TrentiStefano/PiFrame/commit/0a3f004200c9098a31800af299150d33ae931e76))
* **ui:** companion panes collapse to their tab below 320 px (task 1.2f) ([7207dbd](https://github.com/TrentiStefano/PiFrame/commit/7207dbdde9dcff03337e0c540f44715b22a6531a))
* **ui:** companion strip expands and restores above the minimum (task 1.2f) ([d21ca42](https://github.com/TrentiStefano/PiFrame/commit/d21ca42fc8f94d633d204d997fed96f061e62b68))
* **ui:** companion tab localization, overflow, lint baselines, settings sections (task 6.1 finish) ([62a4e2d](https://github.com/TrentiStefano/PiFrame/commit/62a4e2db28f4ea2220e9689b16d60bafa2ccdb9e))
* **ui:** companion tabs are focusable buttons with arrow-key navigation (task 6.1) ([c29d348](https://github.com/TrentiStefano/PiFrame/commit/c29d348f544e1fd5b1d3577b6cf7fbc242303c9c))
* **ui:** composer carry-over, focusable chip removes and literal ratchet (tasks 2.4, 2.5, 2.6, 6.1) ([c9324e4](https://github.com/TrentiStefano/PiFrame/commit/c9324e40206d0f467411fa9fab48eb36728870e3))
* **ui:** composer chip row steps labels down as it narrows (task 1.2e) ([654b2d7](https://github.com/TrentiStefano/PiFrame/commit/654b2d749fe2f4c3470e4eeeca47e63347cd9daa))
* **ui:** composer, side and browser follow the motion, dialog, icon and error rules (task 2.5 / 7.5 / P3-1 lane B) ([8085371](https://github.com/TrentiStefano/PiFrame/commit/80853712730dc4e3684b23ac7d6f8492d695970c))
* **ui:** crash-recovery composer hides run controls and wraps banner (task 1.9) ([fc20fd2](https://github.com/TrentiStefano/PiFrame/commit/fc20fd2b1cec864659f2d3fd60fcd1b4e38360a6))
* **ui:** Dettagli for remote, updates and extension inline errors (task 1.6) ([9aa2144](https://github.com/TrentiStefano/PiFrame/commit/9aa214430ef22b83108309ab30883e1290e0d77e))
* **ui:** discard-file tooltip says Scarta, not Annulla (task 1.1 follow-up) ([b4f36ff](https://github.com/TrentiStefano/PiFrame/commit/b4f36ffec67f42c3d987d057143fe44679dd5e6d))
* **ui:** drop the shell heading and close button above the context drawer (task 5.4 follow-up) ([dcc0cf2](https://github.com/TrentiStefano/PiFrame/commit/dcc0cf2f664f604e3b1e090bd9b4d576f38ea4db))
* **ui:** editor gutter, no-wrap width, dirty dot and folder add-to-chat (task 9.1-9.3) ([11524ef](https://github.com/TrentiStefano/PiFrame/commit/11524ef61f517d14406ed843a964f63c0052e61f))
* **ui:** elapsed chip skips non-message predecessors and caps gaps at 24 h (task 4.7, R6) ([eab39f8](https://github.com/TrentiStefano/PiFrame/commit/eab39f8c4a5842307645fc1301aee84522e934f4))
* **ui:** file icon comment, neutral git icon, outlined glyphs (P3-1, P3-8) ([554d8f8](https://github.com/TrentiStefano/PiFrame/commit/554d8f844785891d40b5a716fe825481186cc095))
* **ui:** filename-first single-line Git rows (task 3.1) ([f4393e5](https://github.com/TrentiStefano/PiFrame/commit/f4393e5275ac3e8d4a6fd0b94edb68c1fa83b90e))
* **ui:** flat sessions rail, no glow on working and pinned dots (task 2.4) ([02ee31d](https://github.com/TrentiStefano/PiFrame/commit/02ee31d68148cbad2aea9a4171e055673c6bf37c))
* **ui:** FrameDialog actions end-aligned; header action slot ([26a2183](https://github.com/TrentiStefano/PiFrame/commit/26a2183c0b74caeb069b3642b65f765fbf8fc06e))
* **ui:** FrameSize.iconSm for dense icons, brace context_panel ifs (final) ([fdc5103](https://github.com/TrentiStefano/PiFrame/commit/fdc510370f3c2b8e33237c2dc198987768d8d4db))
* **ui:** Git context menu and keyboard navigation (task 3.6) ([2a27076](https://github.com/TrentiStefano/PiFrame/commit/2a27076170ee086fd85f80accb0254ef9ecf688c))
* **ui:** Git discard dialog wording and danger style (task 1.1) ([2767f64](https://github.com/TrentiStefano/PiFrame/commit/2767f64192df78384e44b8f2ce11c4b798ea1336))
* **ui:** Git empty and loading states (task 3.3) ([d5f24f4](https://github.com/TrentiStefano/PiFrame/commit/d5f24f4709930a7b9eb2e062eeed383f44825133))
* **ui:** git fetch, pull, push and sync confirm success (plan §13 item 6) ([0258ee2](https://github.com/TrentiStefano/PiFrame/commit/0258ee255d0a5a6ca23e7a2134a604be6d1283a6))
* **ui:** git header Browser chip and commit form row fit at text scale 1.4 (plan §13 item 10) ([d54e55d](https://github.com/TrentiStefano/PiFrame/commit/d54e55d7eb384813c2f26a792d77cc6b9fa5788e))
* **ui:** Git row actions always visible without a hover pointer (touch decision) ([3c8e591](https://github.com/TrentiStefano/PiFrame/commit/3c8e591d6429014fdb07a00d1a49e74069347af6))
* **ui:** icons use FrameSize tokens and outlined glyphs in owned folders ([82423a3](https://github.com/TrentiStefano/PiFrame/commit/82423a37dec1287d9571eb933a4274b3abb18ae1))
* **ui:** improve overlays for tooltips, settings switch tiles, and composer glow border ([827dc5c](https://github.com/TrentiStefano/PiFrame/commit/827dc5c3f32c391a0f49f8c7e643eb6a15e0c096))
* **ui:** keep tool and thinking chevrons at 15 px (tool_timeline_test) ([c2620ec](https://github.com/TrentiStefano/PiFrame/commit/c2620ec69c07af159b1912c0d27b678f8c9129af))
* **ui:** keyboard path to session rename and failed-message restore (task 12.x-3) ([72d8446](https://github.com/TrentiStefano/PiFrame/commit/72d8446eb311b93a564f44ddce91744c21ef132e))
* **ui:** labelled loading, timeout and error for Packages tab (task 1.5) ([0108db7](https://github.com/TrentiStefano/PiFrame/commit/0108db78e1f5875b8262664afa51399a9b4b317b))
* **ui:** localize the load-older-messages banner (task 2.5) ([2ab6490](https://github.com/TrentiStefano/PiFrame/commit/2ab64905138e6ea0ac1b8963429677380bb2f205))
* **ui:** map raw exceptions to user messages (task 1.6) ([ebb0534](https://github.com/TrentiStefano/PiFrame/commit/ebb053426dd7054651cc7c196d046157c4164d66))
* **ui:** mobile web unpaired and offline screens (task 10.4) ([52d52b2](https://github.com/TrentiStefano/PiFrame/commit/52d52b2e8960c88046d149bc6de90322f2d211f4))
* **ui:** motion uses FrameMotion tokens with reduced-motion variants (plan §13 item 9) ([1c97508](https://github.com/TrentiStefano/PiFrame/commit/1c97508febf1becb666fbffcc5161482e8bb0cb8))
* **ui:** move last sub-11px font literals to FrameText roles (plan §13 item 2) ([1202e9d](https://github.com/TrentiStefano/PiFrame/commit/1202e9ddc6ff7c79389c62733bda296298a8c018))
* **ui:** move new-session debounce to a motion token after phase merges (task 5.3) ([46579fc](https://github.com/TrentiStefano/PiFrame/commit/46579fcf9efd575f739da51e71e5a1d6b6cffa6b))
* **ui:** named motion tokens and fewer literals in owned folders ([bdb04f6](https://github.com/TrentiStefano/PiFrame/commit/bdb04f6dfd7189d2b8f2241592b1acae42fa8324))
* **ui:** palette focus ring, Italian copy, key cap and literal tokens (task 6.5) ([c95b224](https://github.com/TrentiStefano/PiFrame/commit/c95b2240d6a46f959734991bd07c532ff0f4a1eb))
* **ui:** pane reduced-motion token and GestureDetector ratchet (tasks 7.3, 7.6) ([adbd00f](https://github.com/TrentiStefano/PiFrame/commit/adbd00fd81837eb28e36c2bef12aee50856f93a5))
* **ui:** Phase 8 settings integration fixes (task 8 carryover) ([6b2228a](https://github.com/TrentiStefano/PiFrame/commit/6b2228a22e52494d4eb7fe3cfaea0e9382515f3e))
* **ui:** polish git header switcher, composer stop button, and branch picker esc layout ([16943da](https://github.com/TrentiStefano/PiFrame/commit/16943dac1cbaaf0a484b3bec3fe21643ec21922c))
* **ui:** polish overlays for buttons, mcp card, toggle splash, and dropdown menus ([5264d0f](https://github.com/TrentiStefano/PiFrame/commit/5264d0f1fdbf14386e1e1ed7c1838c43709e6d31))
* **ui:** polish tasks popup, step grouping, pane transitions, and settings view ([9c6fc4c](https://github.com/TrentiStefano/PiFrame/commit/9c6fc4cc3fb7ec066da2ce9511b5fcfa83e4f0bd))
* **ui:** press feedback on filled and outlined buttons in owned folders ([8ba137b](https://github.com/TrentiStefano/PiFrame/commit/8ba137b8950bc9846b03800b5c3b13b6274a866c))
* **ui:** quieter off-state switch outline (task 2.4) ([278a4f5](https://github.com/TrentiStefano/PiFrame/commit/278a4f51215ec52d1e56799754b9a63231dd13d6))
* **ui:** rail and pane fixes at large text scale; concentric pane radius (P3-2) ([92057b0](https://github.com/TrentiStefano/PiFrame/commit/92057b0f5b01a42f4b4aa10ca3b5532aa8c9b2e6))
* **ui:** reduced motion for settings progress bars ([fb65f6e](https://github.com/TrentiStefano/PiFrame/commit/fb65f6e6cfefb61d92166850ab1d72a15cd9ebf7))
* **ui:** remove internal jargon and finish Italian localization (task 1.7) ([552c1b9](https://github.com/TrentiStefano/PiFrame/commit/552c1b9f39d45ae948508580c23c464057611f3b))
* **ui:** render Markdown tables as tables (task 4.7, R4) ([03b545f](https://github.com/TrentiStefano/PiFrame/commit/03b545fe6f7af5de1e01616a07fe13c6871150c1))
* **ui:** reserve warning and danger colours for real warnings and errors (plan §13 item 5) ([7a7c570](https://github.com/TrentiStefano/PiFrame/commit/7a7c5706f7e8bd4e1c77f7b99567f79d184ccec6))
* **ui:** resolve UI rework regressions across chat, sidebars, and settings ([c255a95](https://github.com/TrentiStefano/PiFrame/commit/c255a95b197245085ebb47bc6bac36996c410613))
* **ui:** search field and icon actions hold up at text scale 2.0 ([8e850c4](https://github.com/TrentiStefano/PiFrame/commit/8e850c4c563a2944e0f83092e518c84ba4075050))
* **ui:** semantic colour corrections (task 1.8) ([c4cfeda](https://github.com/TrentiStefano/PiFrame/commit/c4cfeda09b9e9e1b5396f782e68fd1e2e7a82d41))
* **ui:** session create without an id shows an error (checklist item 6) ([0b528f6](https://github.com/TrentiStefano/PiFrame/commit/0b528f696b9c08263502b7b1dd408fa886481789))
* **ui:** session header chips start after the status pill (task 12.x-1) ([82d44b4](https://github.com/TrentiStefano/PiFrame/commit/82d44b47b9531def149e9670629903f0f0f93e03))
* **ui:** session header on FramePaneHeader with a titleWidget slot (task 4.5) ([0faae21](https://github.com/TrentiStefano/PiFrame/commit/0faae21e68a7e6787a7b2961d60b52dcfdd8c2cd))
* **ui:** session header status tag no longer overlaps title or cwd (phase 11 lane A) ([e34e28b](https://github.com/TrentiStefano/PiFrame/commit/e34e28b77406ccf1355d01ab4648a6d6b02aa679))
* **ui:** sessions footer search, ESC key cap, 680x560 minimum, startup intro on first run (tasks 5.1, 7.8, 8) ([0c990d1](https://github.com/TrentiStefano/PiFrame/commit/0c990d175d4d0398df945a911c3c040fae29da97))
* **ui:** sessions sidebar empty state has one action (checklist item 7) ([b5c5934](https://github.com/TrentiStefano/PiFrame/commit/b5c59341ccdacc593b7e381339f2557868633103))
* **ui:** settings dialogs, spinners, error snackbars and icons (phase 11 lane E) ([3456f66](https://github.com/TrentiStefano/PiFrame/commit/3456f6613ba94a9b012d4c2e76bc19cbffab3348))
* **ui:** shared dialog, buttons, icons and snack text (phase 11 lane E) ([43cecc7](https://github.com/TrentiStefano/PiFrame/commit/43cecc746f3b798d45c4c4f6ac7f77d1bc12c091))
* **ui:** Shift+F10 and the Menu key open the focused row's context menu (task 12.x-2) ([ee35ec8](https://github.com/TrentiStefano/PiFrame/commit/ee35ec8f7b88174b920612f3a2da2f415c36274f))
* **ui:** show daemon and Pi messages again, keep raw Dart errors hidden (task 1.6) ([9857037](https://github.com/TrentiStefano/PiFrame/commit/985703783b00b87856d64ab1c302e8b18ffd6ed2))
* **ui:** single-row browser companion toolbar, overflow menu below 360 px (task 1.2a) ([d6de563](https://github.com/TrentiStefano/PiFrame/commit/d6de5636609d953afa03827a5489a83637a5377b))
* **ui:** size transitions use a cross-fade under reduced motion, not zero (plan §13 item 9) ([21ee566](https://github.com/TrentiStefano/PiFrame/commit/21ee56692569e312fe38cde106a10cc31e53a154))
* **ui:** startup update banner is inline, not overlaid (task 1.4) ([d15f424](https://github.com/TrentiStefano/PiFrame/commit/d15f424a403c48e7378e541da7490db3e2db7353))
* **ui:** static activity indicators under reduced motion (composer, transcript, tools) ([71268f8](https://github.com/TrentiStefano/PiFrame/commit/71268f8fa2aa71643033f9282d05fad501ba96b5))
* **ui:** surface provider errors and respect reduced motion ([19b17b8](https://github.com/TrentiStefano/PiFrame/commit/19b17b854d2436ffcb1fd925eb725984ff7f3215))
* **ui:** Tab sweep and Escape-everywhere checks (plan 13 items 3-4) ([ad930c1](https://github.com/TrentiStefano/PiFrame/commit/ad930c1bb8b633b6125d2a9a48eee056143c290c))
* **ui:** task-notification card and assistant header fit narrow chat (task 1.2c) ([c6deeb8](https://github.com/TrentiStefano/PiFrame/commit/c6deeb8899bfbc6d6999d19f8e09ed29505b7588))
* **ui:** todo panel header fits narrow chat widths (task 1.2b) ([d73112d](https://github.com/TrentiStefano/PiFrame/commit/d73112d7b481a3ce4f7465176f30d2f8dbdfaeff))
* **ui:** valid fixture PNG and graceful invalid-image fallback (task 4.7, R4) ([7f3c756](https://github.com/TrentiStefano/PiFrame/commit/7f3c756e3ace5f3ccfa59986463f158720fe742b))
* **ui:** workspace duties: indicators, error snackbars, font floor, focusable tabs (lane C) ([3ea6d6b](https://github.com/TrentiStefano/PiFrame/commit/3ea6d6bfaabe7e54814db7d027db9e6b60a2a8e6))
* **ui:** workspace leftovers, press feedback, outlined icons and icon tokens (tasks 12.x-4..6) ([23e900d](https://github.com/TrentiStefano/PiFrame/commit/23e900d231c4f359bba8d884aeb2e9c92a97acd7))
* **ui:** workspace small-font literals use FrameText caption (task 9.x) ([c1698ce](https://github.com/TrentiStefano/PiFrame/commit/c1698ce35a6de6423b550daaf07bed763493930a))
* **ui:** writes-disabled as an inline line in the Git action bar (task 3.4) ([e2e7608](https://github.com/TrentiStefano/PiFrame/commit/e2e7608fba9247a054356b35a079687c61000c04))
* **workspace:** count untracked lines in-process instead of spawning git per file ([9a7be98](https://github.com/TrentiStefano/PiFrame/commit/9a7be989791297a777750979338d2e7b0a576022))
* **workspace:** do not collapse git changes when opening agents sidecar ([0724323](https://github.com/TrentiStefano/PiFrame/commit/072432336fc40422633561a9fa01a00214b7614b))
* **workspace:** enlarge branch picker dialog and improve branch name layout readability ([54ccc6d](https://github.com/TrentiStefano/PiFrame/commit/54ccc6d23c225ba8c6f774b7af03bb464d98219f))


### Performance Improvements

* **app:** collapse repeated workspace refreshes while one is running ([2d9bc62](https://github.com/TrentiStefano/PiFrame/commit/2d9bc620dbe596b276cd128826fb5b4751b70ace))
* **daemon:** share identical in-flight read commands per connection ([5d01796](https://github.com/TrentiStefano/PiFrame/commit/5d01796e93a85c48568cfae3c6ef7c43a1c415ea))
* **sessions:** read a session file once and asynchronously when opening it ([53f3ec3](https://github.com/TrentiStefano/PiFrame/commit/53f3ec37f7eb0c2c2226f43567aa1940feeec6ac))
* **sessions:** reuse a Pi terminal scan finished less than 2 s ago ([de8bd91](https://github.com/TrentiStefano/PiFrame/commit/de8bd91d9f4d88fffb89511c1e58ec1c9c2f88a0))
* **sessions:** share in-flight Pi terminal scans between concurrent checks ([04342e1](https://github.com/TrentiStefano/PiFrame/commit/04342e1dde4feef071dc176fc16e41ad53c55cce))
* **workspace:** read branch and HEAD state from the git status header ([57a4be2](https://github.com/TrentiStefano/PiFrame/commit/57a4be23c14e16b9d3b981917080f7e8bef7e07c))
* **workspace:** remember the repository root of a session folder for 10 s ([7ccf284](https://github.com/TrentiStefano/PiFrame/commit/7ccf2844a2fd8a9ccc4d332a481c51b69b940008))

## [1.4.1](https://github.com/TrentiStefano/PiFrame/compare/v1.4.0...v1.4.1) (2026-11-08)


### Bug Fixes

* **agentd:** reliable remote web delivery, phone uploads and boot retry ([67eb888](https://github.com/TrentiStefano/PiFrame/commit/67eb8882b6cfebf4c6568c858724ae42237c343b))
* **ci:** run verify in a worktree outside the OS temp dir ([2cd9c7d](https://github.com/TrentiStefano/PiFrame/commit/2cd9c7d3286aade4fb233a84e49a029c3a23f69c))
* **test:** decouple update tests from the current app version ([6bdf73b](https://github.com/TrentiStefano/PiFrame/commit/6bdf73b85370db48c265cd6bf3798e5af48d460a))
* **transcript:** ignore nested scroll metrics in the compact step list ([4eb0b2d](https://github.com/TrentiStefano/PiFrame/commit/4eb0b2d36b49b53c68876feae27903ace52a2242))
* **transcript:** stop compact step list jitter while thinking streams ([20776e4](https://github.com/TrentiStefano/PiFrame/commit/20776e481993ab7841ffa5eecc2d5264176b3ecb))
* **web:** make the phone web app fast, aligned and usable on iPhone ([6fa857e](https://github.com/TrentiStefano/PiFrame/commit/6fa857e453e16b74c36fa38524b56ba0a8861c53))

## [1.4.0](https://github.com/TrentiStefano/PiFrame/compare/v1.3.1...v1.4.0) (2026-11-08)


### Features

* add agents and workflows side panel ([6d84723](https://github.com/TrentiStefano/PiFrame/commit/6d847237f0310caa2ce77fc9eca7177ad043e6c2))
* **chat:** add read-only /side conversations ([2e48ed2](https://github.com/TrentiStefano/PiFrame/commit/2e48ed29c27ac0983747de48c3a71dfdd9a2faff))
* **chat:** cap expanded step groups with a scrollable list ([8964cdd](https://github.com/TrentiStefano/PiFrame/commit/8964cddd37136e29b464c09d23b32fe759f8ac38))
* **chat:** group intermediate turn steps into collapsible blocks ([f87ab9c](https://github.com/TrentiStefano/PiFrame/commit/f87ab9c7384de87d40853f78030ec6be98e533ea))
* **git:** add branch browser with safe daemon-side switching ([4e4c5d1](https://github.com/TrentiStefano/PiFrame/commit/4e4c5d1254829ad0b6bfdc53c7c7acef11673782))
* **i18n:** translate the UI into Italian, fix terminal line endings ([ce483c0](https://github.com/TrentiStefano/PiFrame/commit/ce483c00569988d854e9c376c254c4352890a3b7))
* **metrics:** add opt-in nerd stats with daemon system metrics ([0739e2f](https://github.com/TrentiStefano/PiFrame/commit/0739e2f44de602dbbddcfad1efa668c64a0f8407))
* **settings:** add Agents page for subagent and session defaults ([5534ea9](https://github.com/TrentiStefano/PiFrame/commit/5534ea96b6e4da169f47759b214f98c8bea82eff))
* **settings:** add Enter-to-send toggle ([4a2217a](https://github.com/TrentiStefano/PiFrame/commit/4a2217a05173ad0d63f252f0f2a3a0cefb27c111))
* show agents and workflows as a live tree ([3a41e08](https://github.com/TrentiStefano/PiFrame/commit/3a41e081b418bd68037e8afd5e5b1196b69747a3))
* show sessions waiting on background agents as running ([5b127fb](https://github.com/TrentiStefano/PiFrame/commit/5b127fb3bdd6f40ee9d29d3bbd05c600029648ee))
* **website:** rework the site with real captures, dark mode, new copy ([fd34cbb](https://github.com/TrentiStefano/PiFrame/commit/fd34cbb64b7c713c388f642b3f4e51063e3644eb))


### Bug Fixes

* **agentd:** report real subagent status and live activity ([bc9b24e](https://github.com/TrentiStefano/PiFrame/commit/bc9b24e8994a2e528de404a586a1fbd418280e74))
* **chat:** keep final answers out of step groups and fix turn status ([c08b2e0](https://github.com/TrentiStefano/PiFrame/commit/c08b2e0122761ca467a5b53591e930eae49a8530))
* **daemon:** sync bundle on build and improve daemon restart and process resolution ([ae118f7](https://github.com/TrentiStefano/PiFrame/commit/ae118f7b59ca1dc1a480c77296cb1ad2e35fc090))
* disambiguate models by provider ([f1e5831](https://github.com/TrentiStefano/PiFrame/commit/f1e5831dda083bfa47d22d163ea5fb89b8c1747e))
* keep transcript links selectable ([086aa36](https://github.com/TrentiStefano/PiFrame/commit/086aa3661af41a93ab43f736cd0e5488770dbd83))
* **metrics:** restart sampling on every resubscribe ([bce3831](https://github.com/TrentiStefano/PiFrame/commit/bce3831c5db65074282a4f7bb3eee9d8aa8b64c3))
* open PiFrame workflows panel from /agents ([e487f62](https://github.com/TrentiStefano/PiFrame/commit/e487f628ae8ff4fdb69b3fd0bee322e67a9bcced))
* prevent duplicate terminal input ([ffda10d](https://github.com/TrentiStefano/PiFrame/commit/ffda10dd52a49c9c6cdd8981180d578d0825ecb5))
* speed up repository and git panels ([133c0c1](https://github.com/TrentiStefano/PiFrame/commit/133c0c102fe88777d4f3d42dc23782a4e49beb06))
* suppress PowerShell terminal input echo ([567b77d](https://github.com/TrentiStefano/PiFrame/commit/567b77df183d340f42e92b2019d531f5f24bd4f0))
* **ui:** dynamic question preview pane and bounded dialog layout ([a5610c1](https://github.com/TrentiStefano/PiFrame/commit/a5610c1500ccf0ffe78a50cb9f75d545ab198d0b))
* **ui:** stable pinned sessions order with drag-and-drop and accurate response notifications ([cf5c83c](https://github.com/TrentiStefano/PiFrame/commit/cf5c83c84c632590d8d0df9b97662fb8efecf686))

## [1.3.1](https://github.com/TrentiStefano/PiFrame/compare/v1.3.0...v1.3.1) (2026-11-05)


### Bug Fixes

* **packaging:** bundle Visual C++ CRT runtime and fix nested web assets ([8aed40a](https://github.com/TrentiStefano/PiFrame/commit/8aed40a0ab82bdd7a2c340e126945c894581470b))
* **packaging:** handle locked node.exe and clean WebView2 cache in windows installer ([5f3326e](https://github.com/TrentiStefano/PiFrame/commit/5f3326ece3a696663a726f38befc9e66a16191ea))
* **questions:** keep custom answers inline ([179a109](https://github.com/TrentiStefano/PiFrame/commit/179a109fcab256dd023a0813be5a0e9eed679149))
* **subagents:** clear analyzer diagnostics ([8f74eb1](https://github.com/TrentiStefano/PiFrame/commit/8f74eb15087349569adec127a1e2e43fe60f0493))
* **subagents:** clear analyzer diagnostics ([9f7ba1b](https://github.com/TrentiStefano/PiFrame/commit/9f7ba1bf5ea4a50852e03f04c8763d20a41fa931))
* **subagents:** keep background runs active until termination ([3715288](https://github.com/TrentiStefano/PiFrame/commit/3715288f35a37704392e75986eedc0e989b728ce))
* **subagents:** reconcile cards with child sessions ([14165f4](https://github.com/TrentiStefano/PiFrame/commit/14165f43c4ea5b1007ce1056424912d153ed37d9))

## [1.3.0](https://github.com/TrentiStefano/PiFrame/compare/v1.2.0...v1.3.0) (2026-10-31)


### Features

* **macos:** add macOS DMG packaging script and Gatekeeper instructions ([b56ea63](https://github.com/TrentiStefano/PiFrame/commit/b56ea63371ef4fb5a12f781a89f8eb9f4b110219))
* **macos:** add package:macos offline DMG generation script and docs ([895939e](https://github.com/TrentiStefano/PiFrame/commit/895939e15a722060a717afd342e38490dbfefb7a))
* **macos:** include DMG installation and first-run guide in installer ([9296412](https://github.com/TrentiStefano/PiFrame/commit/92964120edf610b93f4f05feef7b4ddfb7c898aa))
* **macos:** integrate native custom title bar with window traffic lights ([54ee14c](https://github.com/TrentiStefano/PiFrame/commit/54ee14cd25771c6f23b2460df0362b0590bc780f))


### Bug Fixes

* **cli:** resolve macOS environment PATH and support official curl installer with prerequisites ([9bbadbc](https://github.com/TrentiStefano/PiFrame/commit/9bbadbc3796dad33cb5bc18fc8b9bfa63a9e0129))
* **packaging:** probe login shell PATH and standard Flutter paths in macOS packager ([c3e02b5](https://github.com/TrentiStefano/PiFrame/commit/c3e02b5a3031d4e2fa316034c5b8149ca4c65031))

## [1.2.0](https://github.com/TrentiStefano/PiFrame/compare/v1.1.1...v1.2.0) (2026-10-30)


### Features

* **auth:** support Pi login and logout in chat ([da96003](https://github.com/TrentiStefano/PiFrame/commit/da9600301c6d4e047471d1f5ce46db4eec86fff4))
* **commands:** expose Pi built-ins in the chat composer ([c067e4c](https://github.com/TrentiStefano/PiFrame/commit/c067e4cc77e15576a5e6668d0f77603e4f53f84e))
* **packaging:** add windows installer build script and documentation ([7cce387](https://github.com/TrentiStefano/PiFrame/commit/7cce38707ed1d20d3ab9d41e037782b32f3fbcfc))


### Bug Fixes

* **build:** reject stale agentd bundles ([4f53162](https://github.com/TrentiStefano/PiFrame/commit/4f5316201cbf48075c9ce5e3f2337d5c4b5fcc54))
* **commands:** run /reload as a Pi resource reload, not model text ([f4af324](https://github.com/TrentiStefano/PiFrame/commit/f4af324277f7a9c9ef507e3ef61d3ba6da1d785c))
* **composer:** follow pane divider drags without trailing ([52459fa](https://github.com/TrentiStefano/PiFrame/commit/52459fab874dd963edcc4bf0ad277ebdc4eeae3d))
* **dialogs:** accept free text from select questions ([1f8de24](https://github.com/TrentiStefano/PiFrame/commit/1f8de24b39640c76865373cdc62838b57210230f))
* **interrupt:** return before agent becomes idle ([19255a9](https://github.com/TrentiStefano/PiFrame/commit/19255a986905b4af6e84c1f046df21887e21c64e))
* **layout:** keep hidden panes and sessions bar state across restarts ([aee7c3d](https://github.com/TrentiStefano/PiFrame/commit/aee7c3d2c7363b289eb2ab512f8fe895a28746cc))
* **review:** show real net line counts and no fabricated diffs ([2a57609](https://github.com/TrentiStefano/PiFrame/commit/2a57609ee69f350e446419a2a27e332f9d427ca0))
* **session:** resolve disconnect loops on large journals, add on-demand history pagination, and stabilize transcript scrollbar ([496c7ce](https://github.com/TrentiStefano/PiFrame/commit/496c7ce4cf3df43cd907e6af6f9ac73fe172a70f))
* **sessions:** preserve refreshes during indexing ([e04df0c](https://github.com/TrentiStefano/PiFrame/commit/e04df0c9f3b5fa54d97ba102c30f794959f6c8b6))
* **sessions:** prevent startup index timeouts ([77a9d12](https://github.com/TrentiStefano/PiFrame/commit/77a9d12a6d731d4d9d0b4b8199e9afe26e01fdab))
* **sessions:** remove glow from repository rows ([9bd7ddd](https://github.com/TrentiStefano/PiFrame/commit/9bd7dddda8cc3a6020e8f0d7a766bc48f6e470a7))
* **sessions:** reply from cached snapshot during refresh ([9805e99](https://github.com/TrentiStefano/PiFrame/commit/9805e9938fca02347e967c12bc499fda182effaa))
* **subagents:** avoid duplicate cards and false zero costs ([656b8cd](https://github.com/TrentiStefano/PiFrame/commit/656b8cdefe4f096ba609912f2dc3c29267ee0f53))
* **subagents:** restore recorded costs and keep cost displays live ([0de92ab](https://github.com/TrentiStefano/PiFrame/commit/0de92ab653a4168e55504263f5e7d63c05021bc6))
* **test:** resolve workspace root dynamically in UI capture tests and ignore misplaced dumps ([3bedbc8](https://github.com/TrentiStefano/PiFrame/commit/3bedbc8b79a6b0870e506ef81d09ad599e34eb61))
* **transcript:** align tool controls with reasoning ([6460093](https://github.com/TrentiStefano/PiFrame/commit/64600932d2b7519e0dd87cb574fcda6fc57ddb1b))
* **transcript:** eliminate chat vibration when expanding or minimizing activity and subagent cards ([6385a05](https://github.com/TrentiStefano/PiFrame/commit/6385a051fe3259e07387ec6af6d4f84f5cf7c0ce))
* **transcript:** keep activity and subagent cards minimized on session open and switch ([a4d1bbf](https://github.com/TrentiStefano/PiFrame/commit/a4d1bbf1b53db03e970f61d4b6554881013c9d77))
* **transcript:** keep book tab bar height stable ([6203d06](https://github.com/TrentiStefano/PiFrame/commit/6203d06b1ef3c9b8a31b9c5ae7fdb7f3a79f6cc2))
* **transcript:** preserve execution timers across session switches ([786b4ac](https://github.com/TrentiStefano/PiFrame/commit/786b4ac5319f10781a2cfedd911e8fdd31e03e80))
* **transcript:** preserve Pi tool actions after interruption and reopen ([90ea79a](https://github.com/TrentiStefano/PiFrame/commit/90ea79ac7208b4faf5f65ce9e6ccfe5f64ec05f7))
* **transcript:** prevent chat jumps when expanding cards ([f481373](https://github.com/TrentiStefano/PiFrame/commit/f481373d704cd40c412cadba4ea419c5bffca062))
* **transcript:** prevent duplicate tool cards ([b1c0aa3](https://github.com/TrentiStefano/PiFrame/commit/b1c0aa3c415345b00a2ba38de26bc72757630752))
* **transcript:** refresh height estimates after card toggles ([406e358](https://github.com/TrentiStefano/PiFrame/commit/406e35821f4a61a019c61951a34b4ac59ff6e6ab))
* **ui:** prevent duplicate menus and blocked agent prompts ([598f266](https://github.com/TrentiStefano/PiFrame/commit/598f266802fae4ac92ccf477759e9e85fed2f358))
* **window:** open centered and restore maximized state ([b5c177f](https://github.com/TrentiStefano/PiFrame/commit/b5c177f3bf799343ca7d1441fe59da6d6d237ee4))

## [1.1.1](https://github.com/TrentiStefano/PiFrame/compare/v1.1.0...v1.1.1) (2026-10-27)


### Bug Fixes

* **context:** enforce model tiers and compaction limits ([cc7c965](https://github.com/TrentiStefano/PiFrame/commit/cc7c965c537b25b4f780d28e75d53d084161dbcf))
* **linux:** declare required WebKitGTK dependencies ([f7f27f1](https://github.com/TrentiStefano/PiFrame/commit/f7f27f1a9927d393f8ea58333c1941e1aeed29b6))

## [1.1.0](https://github.com/TrentiStefano/PiFrame/compare/v1.0.0...v1.1.0) (2026-10-26)


### Features

* add code syntax highlighting, search, steer queue editing, and showcase ([0cbbd2e](https://github.com/TrentiStefano/PiFrame/commit/0cbbd2e95a19903bd5b15202a92001f5807ef5b6))
* add Pi CLI controls in settings, collapsible workspace panes, and integrated terminal ([ca6f420](https://github.com/TrentiStefano/PiFrame/commit/ca6f4208b1b0cd3205fe8c8a412601509700ba58))
* **app:** startup animation with logo assembly, framing audio and window size persistence ([e819f44](https://github.com/TrentiStefano/PiFrame/commit/e819f44f5782281bd5cb301026c97c02f7ea4b68))
* automatic update from the settings (check for updates button) ([a219053](https://github.com/TrentiStefano/PiFrame/commit/a219053540d0636ff9d5ae385b9e9ceecad4c053))
* **branding:** redesign app icon to 3d pie slice with cohesive crust and centered pi glyph ([59a9708](https://github.com/TrentiStefano/PiFrame/commit/59a97080a377c2fff16bfb796cc788c572ef5fd9))
* **browser:** add integrated web browser pane, fix nullability in session reducer, and resolve release diagnostics ([22d6524](https://github.com/TrentiStefano/PiFrame/commit/22d6524ba77334504e1248aae3e2f33f4ab4af85))
* **browser:** embed native Chromium WebView2 for live browsing ([50dd2db](https://github.com/TrentiStefano/PiFrame/commit/50dd2db3224030cae34cdf53e86a25d27a8205ea))
* **chat:** add attachment options, transcript chips with image lightbox, and drag-and-drop support ([31bd627](https://github.com/TrentiStefano/PiFrame/commit/31bd627bc326eb8719e136062d727d1ea0da205a))
* **composer:** add button and toggle to enlarge chat input window on long prompt ([b948b32](https://github.com/TrentiStefano/PiFrame/commit/b948b32522c5345bb6f047622370949738fabe72))
* **composer:** animate minimize chat input while agent is answering ([71db799](https://github.com/TrentiStefano/PiFrame/commit/71db799ba8423ec1896aae4424df1e7a1abe86b4))
* **composer:** dock model interaction card on input and improve file mentions ([7eb52d6](https://github.com/TrentiStefano/PiFrame/commit/7eb52d66a142512bdbf66cd1f45ffd9e00715c2a))
* **context:** pick context size for models with variable context pricing (luna, haiku) ([7fc73ec](https://github.com/TrentiStefano/PiFrame/commit/7fc73ec555ae6d8d438feff837a2bc700c7129e1))
* **daemon:** add session.delete command to agentd and pcp protocol ([0200da0](https://github.com/TrentiStefano/PiFrame/commit/0200da032b8abff3dab9258c605ad76b8e5a1a9b))
* **docs:** replace slideshow with live application run video and animated GIF showcase inspired by pi-gui ([6afa453](https://github.com/TrentiStefano/PiFrame/commit/6afa453951c41fdeba1a7b1a39f195166cec8200))
* **icon:** add application icons and design assets for branding and UI ([ce5fa9a](https://github.com/TrentiStefano/PiFrame/commit/ce5fa9a5364a412df0778bbf9e433491c5a7d44e))
* **instructions:** generate instruction files with Pi agent from popup dialog ([7013646](https://github.com/TrentiStefano/PiFrame/commit/701364655abeede595706916cff1de083aa083b7))
* **landing:** show latest 5 active sessions as quick launch in welcome page ([05e24ea](https://github.com/TrentiStefano/PiFrame/commit/05e24ea7993479d0a8c7e6072ec5ccdc8afc6f8b))
* **mcp:** click on mcp card to view available servers and toggle them with checkboxes ([f724dfd](https://github.com/TrentiStefano/PiFrame/commit/f724dfd0a2a82eb17c6d3e22c762b8ad952268f4))
* **notifications:** add system notifications when agent finishes or requires attention while unfocused ([292d046](https://github.com/TrentiStefano/PiFrame/commit/292d0464ef6a07ae7e38484778ed2e82080ce064))
* release stabilization fixes (fixes 1-10 complete with multi-model cost breakdown, desktop snackbars, and handoff doc) ([263ff97](https://github.com/TrentiStefano/PiFrame/commit/263ff977b125cc1f04f296c40a9baa9123f4576c))
* **release:** automate semantic desktop releases ([e6a3f97](https://github.com/TrentiStefano/PiFrame/commit/e6a3f971d90236a732eecb290a6c801aecddc291))
* **release:** chat message types, iPhone layout and remote fixes ([d54dc77](https://github.com/TrentiStefano/PiFrame/commit/d54dc7739b26869fee7d49e259f1e8ec6611194d))
* **remote:** add secure remote access via Tailscale and Cloudflare ([ca4b5e6](https://github.com/TrentiStefano/PiFrame/commit/ca4b5e6d87135f6e72eb6eb9734c3a13debdde29))
* **session:** add Review Changes pane with diff viewing and 50/50 layout split ([6973882](https://github.com/TrentiStefano/PiFrame/commit/69738823e88bb5cc124f05b599b7ed5bdccdeb58))
* **sessions:** add quick session creation, folder activity glow, and pinned sessions ([eaf86b1](https://github.com/TrentiStefano/PiFrame/commit/eaf86b1ce9c1b83bd9cc6047e1c8fa6680740cc0))
* **sessions:** edit repository instruction files directly from sessions sidebar ([ec559b3](https://github.com/TrentiStefano/PiFrame/commit/ec559b3277b47b5e93c85b91b9602baf2a1a54d1))
* **settings:** language dropdown in appearance tab to choose application language ([b01a7ae](https://github.com/TrentiStefano/PiFrame/commit/b01a7ae23dadedffee2ccbf6e292ad5a02c5a471))
* **setup:** prompt to install pi-coding-agent on first run if not found ([fb190a6](https://github.com/TrentiStefano/PiFrame/commit/fb190a6e867bcb013963ba793e27ff1413bfc26f))
* **subagents:** add popdown subagents panel with expandable progress windows, steering and stop controls ([69dd31e](https://github.com/TrentiStefano/PiFrame/commit/69dd31e255f034b1253dde50e112442cdee1c657))
* **terminal:** direct in-terminal typing and native OS terminal integration ([85c9f4c](https://github.com/TrentiStefano/PiFrame/commit/85c9f4cb2edcdbc09af5201b08a9a4f10d0aad36))
* **theme:** add configurable default light and dark themes with system theme tracking ([76f684d](https://github.com/TrentiStefano/PiFrame/commit/76f684d29cec9b3c2787a6ffce253df769a22988))
* **theme:** import VSCode JSON themes, persist selected theme, and improve composer interactions ([71bd4a2](https://github.com/TrentiStefano/PiFrame/commit/71bd4a2b4fa3fdf2da27febda14b0deedbede556))
* **themes:** custom theme editor with base selection, color customization and live preview ([c7ca619](https://github.com/TrentiStefano/PiFrame/commit/c7ca619ae9feafc64a0150457555fcc60f7fe80b))
* **todos:** UI to show agent todo list with interactive checkboxes in real time ([92a86a8](https://github.com/TrentiStefano/PiFrame/commit/92a86a88e720d9a68b19c767e443fc2b2d89b8c5))
* **transcript:** double click session name in chat header to rename ([83ccf2a](https://github.com/TrentiStefano/PiFrame/commit/83ccf2a590d6fe6b459b9af5cd93a6249f6f2b2a))
* **transcript:** support CTRL+click on file mentions to open in OS file explorer ([abbbc8f](https://github.com/TrentiStefano/PiFrame/commit/abbbc8f52c7979840be08e97d0558cbeda896893))
* **ui:** Bento workbench density, Catppuccin surfaces and companion tabs ([2447bb2](https://github.com/TrentiStefano/PiFrame/commit/2447bb2ae4507e81665b802426fc750493b7d1ab))
* **ui:** harden transcript scrolling, add VS Code treeview explorer, and optimize workspace layout ([cdeaf1a](https://github.com/TrentiStefano/PiFrame/commit/cdeaf1a9fb7135a17e2d1826cae3e262386a527b))
* **ui:** redesign Flutter client with Precision identity ([5aac5c3](https://github.com/TrentiStefano/PiFrame/commit/5aac5c31d29849ef9962b578cc608e8ddb8f95af))
* **UI:** UI redesign with pi-design-director, new UI layout and themes ([1035790](https://github.com/TrentiStefano/PiFrame/commit/10357908658d9a32834ea6deaa6e1ddc7828fe5e))
* **ui:** unified side-by-side book tabs bar with exclusive tab control and remove subagents card from header ([a467991](https://github.com/TrentiStefano/PiFrame/commit/a46799197e01c7094beb01959c5bdf0eca13fe39))
* **updates:** startup notification banner for Pi CLI and package updates ([a9edff0](https://github.com/TrentiStefano/PiFrame/commit/a9edff0f7d92d61333d24ce13744ee1a602533f5))
* **website:** update landing page, design docs, and UI screenshots for PiFrame Dark & Light themes ([fc4c185](https://github.com/TrentiStefano/PiFrame/commit/fc4c185353e457623a49d9861cd383dcaf07df0a))
* **workspace:** add repository file search, add-to-chat actions, and start trees collapsed ([eab673a](https://github.com/TrentiStefano/PiFrame/commit/eab673a585bfd737acc07567c1e91980e51f98e5))
* **workspace:** support WSL repositories and terminal, evict stale daemons ([e4ffaab](https://github.com/TrentiStefano/PiFrame/commit/e4ffaabdb2bbc5b3143f7bcb2f69c328797edb5a))


### Bug Fixes

* **app:** repair Pi session workflows ([3364069](https://github.com/TrentiStefano/PiFrame/commit/336406919300b67374d08c5326128c4f77c1dde7))
* **chat:** reconcile and recover failed prompts ([4f27df9](https://github.com/TrentiStefano/PiFrame/commit/4f27df9edb1c1dc408e4fdfdb0259ad365c4a747))
* **chat:** reconcile and recover failed prompts ([43625ca](https://github.com/TrentiStefano/PiFrame/commit/43625caf9acc0c72cef4f5535adbb4d5bee35bf2))
* **ci:** repair main-only release workflows ([d635b11](https://github.com/TrentiStefano/PiFrame/commit/d635b1105fb378c62603546f7a988b5472b3f07c))
* **composer,agentd:** prevent steer queue double-send on agent stop, model change, and resend (Item 11) ([4059c94](https://github.com/TrentiStefano/PiFrame/commit/4059c94ffb00529f65516b8fe8d2959fc0f992d8))
* **composer:** add pointer glow to minimized chat input card and expand after 5s or click ([73b296f](https://github.com/TrentiStefano/PiFrame/commit/73b296f6569ddc40004ba64df9d6a352cd99713a))
* **composer:** match minimized interrupt button and label color with maximized stop button ([91f9e93](https://github.com/TrentiStefano/PiFrame/commit/91f9e930af46fd8fb8c1314c98bd615ff9c4cf2c))
* **daemon,transcript:** resolve daemon disconnect loop, stuck thinking/todos, and settings loader ([fc867ae](https://github.com/TrentiStefano/PiFrame/commit/fc867ae6b3b8594115414053ca103bd84a026664))
* **desktop:** split startup audio behind platform stubs and keep forks listed ([a48dab8](https://github.com/TrentiStefano/PiFrame/commit/a48dab87a97a244c96f8a773f98388e1108825e7))
* release workflow for automated builds and publishing improvements ([c486e3e](https://github.com/TrentiStefano/PiFrame/commit/c486e3e2bd4062e6ccc499f21f7904fd751c98d6))
* **release:** re-sign macOS app bundle after injecting daemon and node binaries ([eefb6ae](https://github.com/TrentiStefano/PiFrame/commit/eefb6ae11e2b6b0a6f98f661346219c83faa656e))
* **remote:** preserve remote enabled on restart and fix host allowlist ([e979f02](https://github.com/TrentiStefano/PiFrame/commit/e979f027a0f8ca7bdb45d121316f8b07331f40a6))
* **session:** index subsessions and maintain cumulative session cost across turns ([72f5a20](https://github.com/TrentiStefano/PiFrame/commit/72f5a2006935ea026877789ee0847ad3fc7afb04))
* **session:** persistenza del costo e metadati alla riapertura e avvio ([0d713d8](https://github.com/TrentiStefano/PiFrame/commit/0d713d872e8c75b61f70eb05b4639e223e8a2c70))
* **sessions:** filter out subagent subsessions from sessions sidebar and daemon index ([69a927e](https://github.com/TrentiStefano/PiFrame/commit/69a927e8543e7a6fd395e9c31a1c40e98f6bbc18))
* **sessions:** separate generating glow from active semaphore, add delete confirmation and repo removal ([3979fed](https://github.com/TrentiStefano/PiFrame/commit/3979fedb22dc13d72f9f9b0722e778ed6de07c4e))
* **sidebar:** show working indication and animation on pinned sessions ([e0e9782](https://github.com/TrentiStefano/PiFrame/commit/e0e978246a6ddca9d30879c12f779be168b7cb20))
* **stats:** update context usage and session cost in real time like TUI ([3c40887](https://github.com/TrentiStefano/PiFrame/commit/3c4088772eaa89ef15ee844a01463eaed59b276f))
* **subagents:** fix individual card collapse, fallback pricing, and running status reconciliation ([3e081fd](https://github.com/TrentiStefano/PiFrame/commit/3e081fd5e7a0e24cfba0831525f205c45ed35fe3))
* **subagents:** visualizzazione in tempo reale con costo e booktab dedicato ([3a90660](https://github.com/TrentiStefano/PiFrame/commit/3a90660dc858c89987a983cb509a15224f76890a))
* **terminal:** enable hardware typing in integrated terminal ([ea6998b](https://github.com/TrentiStefano/PiFrame/commit/ea6998b63e6d6dcf86b7b61be666587a91092e17))
* **themes:** improved readability for default dark and light themes ([2eb246e](https://github.com/TrentiStefano/PiFrame/commit/2eb246e198cf1d9eb346748072281758f2b19826))
* **timeline:** show full terminal command when expanded and add duration counter with timeout ([c545694](https://github.com/TrentiStefano/PiFrame/commit/c5456941939e950114c1445ba27b204993cc147a))
* **todos:** parsing robusto di oggetti non quotati e sincronizzazione stato completato ([1dfab15](https://github.com/TrentiStefano/PiFrame/commit/1dfab15657d60ba6135b2c6bd7a1eb43c5062a85))
* **todos:** prevent task counter runaway and duplicate creation during streaming ([f0843e4](https://github.com/TrentiStefano/PiFrame/commit/f0843e47271725760064755691bcfba7f8db0323))
* **todo:** support chat transition notifications and direct id/status updates ([0b6fd43](https://github.com/TrentiStefano/PiFrame/commit/0b6fd437ad520ff8de2ee7cfbad9da5b9fa68721))
* **transcript:** enable multi-paragraph mouse selection, clickable markdown links, and filter internal noise ([3eebf7b](https://github.com/TrentiStefano/PiFrame/commit/3eebf7b39ce469dc07da9aebde6bf3ba2734e289))
* **transcript:** persist thinking and tool timelines, fix stream auto-scroll and collapse tool cards by default ([ba52923](https://github.com/TrentiStefano/PiFrame/commit/ba529235f4d9d56dd786f5bcbdc753fe65ce92c0))
* **transcript:** right-align task timestamps and normalize spacing between intermediate blocks ([0acd6b4](https://github.com/TrentiStefano/PiFrame/commit/0acd6b4c69cd7e6b4b5c15a00f9a10717b804b5b))
* **transcript:** save session rename on enter and preserve expanded thinking blocks ([e7eab61](https://github.com/TrentiStefano/PiFrame/commit/e7eab61480f3e3cf979248d27fc86dd888a6de0a))
* **ui:** improve activities panel, subagents popup, multi-tier cost breakdown, and task notifications ([64e1c1a](https://github.com/TrentiStefano/PiFrame/commit/64e1c1a61a5713101e5124362c53f2b147989d2d))
* **ui:** polish subagent & todo panels, fix inline code wrap and timer ([7a0f745](https://github.com/TrentiStefano/PiFrame/commit/7a0f745c583c1cbffcfef1706de730d1b2b26f91))
* **ui:** rimossa card attivita dalla lista info chip nella session title card e migliorata gestione espansione subagenti ([16601af](https://github.com/TrentiStefano/PiFrame/commit/16601af5b4da097689fbb4b748a7baa087ef7b21))
* **ui:** update CrustMark to official 3D pie slice icon and record real Flutter app run for showcase ([3b83e6c](https://github.com/TrentiStefano/PiFrame/commit/3b83e6c618f35a7c035fe1c21ebeb5003f6445bc))
* **web:** make remote web client usable and drop the in-app browser on web ([972ab29](https://github.com/TrentiStefano/PiFrame/commit/972ab29e7f6d5f9ccb5761f62375d2285ca4a8b2))
* **workspace:** include untracked new files in git changes tab and add .md preview toggle ([9ba1aeb](https://github.com/TrentiStefano/PiFrame/commit/9ba1aebe1a3e391e4d5f31217a0e0bd3f1a50364))
* **workspace:** use null-aware element for trailing widget in git section header ([0bac8cc](https://github.com/TrentiStefano/PiFrame/commit/0bac8ccc69b09f010d57c536bf5a9b6098e99324))

## [1.3.0](https://github.com/TrentiStefano/piframe/compare/v1.2.0...v1.3.0) (2026-10-12)


### Features

* **composer:** dock model interaction card on input and improve file mentions ([7eb52d6](https://github.com/TrentiStefano/piframe/commit/7eb52d66a142512bdbf66cd1f45ffd9e00715c2a))
* **sessions:** add quick session creation, folder activity glow, and pinned sessions ([eaf86b1](https://github.com/TrentiStefano/piframe/commit/eaf86b1ce9c1b83bd9cc6047e1c8fa6680740cc0))
* **transcript:** double click session name in chat header to rename ([83ccf2a](https://github.com/TrentiStefano/piframe/commit/83ccf2a590d6fe6b459b9af5cd93a6249f6f2b2a))
* **workspace:** add repository file search, add-to-chat actions, and start trees collapsed ([eab673a](https://github.com/TrentiStefano/piframe/commit/eab673a585bfd737acc07567c1e91980e51f98e5))


### Bug Fixes

* **release:** re-sign macOS app bundle after injecting daemon and node binaries ([eefb6ae](https://github.com/TrentiStefano/piframe/commit/eefb6ae11e2b6b0a6f98f661346219c83faa656e))
* **transcript:** enable multi-paragraph mouse selection, clickable markdown links, and filter internal noise ([3eebf7b](https://github.com/TrentiStefano/piframe/commit/3eebf7b39ce469dc07da9aebde6bf3ba2734e289))
* **workspace:** use null-aware element for trailing widget in git section header ([0bac8cc](https://github.com/TrentiStefano/piframe/commit/0bac8ccc69b09f010d57c536bf5a9b6098e99324))

## [1.2.0](https://github.com/TrentiStefano/piframe/compare/v1.1.0...v1.2.0) (2026-10-12)


### Features

* **icon:** add application icons and design assets for branding and UI ([ce5fa9a](https://github.com/TrentiStefano/piframe/commit/ce5fa9a5364a412df0778bbf9e433491c5a7d44e))


### Bug Fixes

* release workflow for automated builds and publishing improvements ([c486e3e](https://github.com/TrentiStefano/piframe/commit/c486e3e2bd4062e6ccc499f21f7904fd751c98d6))

## [1.1.0](https://github.com/TrentiStefano/piframe/compare/v1.0.0...v1.1.0) (2026-10-12)


### Features

* **release:** automate semantic desktop releases ([e6a3f97](https://github.com/TrentiStefano/piframe/commit/e6a3f971d90236a732eecb290a6c801aecddc291))
* **ui:** harden transcript scrolling, add VS Code treeview explorer, and optimize workspace layout ([cdeaf1a](https://github.com/TrentiStefano/piframe/commit/cdeaf1a9fb7135a17e2d1826cae3e262386a527b))
* **ui:** redesign Flutter client with Precision identity ([5aac5c3](https://github.com/TrentiStefano/piframe/commit/5aac5c31d29849ef9962b578cc608e8ddb8f95af))
* **UI:** UI redesign with pi-design-director, new UI layout and themes ([1035790](https://github.com/TrentiStefano/piframe/commit/10357908658d9a32834ea6deaa6e1ddc7828fe5e))


### Bug Fixes

* **app:** repair Pi session workflows ([3364069](https://github.com/TrentiStefano/piframe/commit/336406919300b67374d08c5326128c4f77c1dde7))
* **ci:** repair main-only release workflows ([d635b11](https://github.com/TrentiStefano/piframe/commit/d635b1105fb378c62603546f7a988b5472b3f07c))
