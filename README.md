### `WeChat Focused`

Apache-2.0 licensed.

- Replaces Discover tab with Moments.
- Use iOS Photos picker for library selection, no needs to grant any photos permission on WeChat. (Selected videos and non-chat images are temporarily stored in the app's Caches directory.)

### `Build and install`

Run `make build` on a Mac with Xcode. Inject `build/WeChatFocused.dylib` into WeChat using Feather:

- Injection Path: `@executable_path`
- Injection Folder: `/Frameworks/`
- Extension injection: off

Then sign and install the app.

### `Development`

- `make format` formats Objective-C source.
- `make lint` checks formatting and compiles with warnings as errors.
