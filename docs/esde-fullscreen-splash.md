# ES-DE splash screen: native restrictions and fullscreen source patch

The prebuilt ES-DE 3.5.0 AppImage is installed by `retro-fetch-esde`.
The normal per-user `ES-DE/resources/graphics/splash.svg` override replaces the
image **but does not configure its display dimensions**.

ES-DE's splash rendering code in `es-core/src/Window.cpp` calls
`mSplash->setResize(...)`, constraining it to a percentage of the display
height/width. As a result, a 1920x1080 SVG renders in a smaller frame.
This is an upstream application limitation, not an SVG resolution problem.

To display the artwork edge to edge **inside the ES-DE splash screen**, a
custom ES-DE binary is required. In the version being built, change the splash
initialization to use the entire renderer area (and rebuild the AppImage):

```cpp
// Replace the initial landscape/portrait percentage-based setResize block.
mSplash->setResize(mRenderer->getScreenWidth(),
                   mRenderer->getScreenHeight());
mSplash->setImage(":/graphics/splash.svg");
mSplash->setPosition(0.0f, 0.0f);
```

Verify that this ES-DE version's ImageComponent `setResize` scales rather
than crops the artwork. With a matching 16:9 image and screen this is exact;
other display aspect ratios require a fill/crop implementation if full bleed
is desired.

**This PR does not rebuild or substitute the upstream AppImage**. As long as
`retro-fetch-esde` downloads the upstream release, there is no supported
resource-file-only fullscreen override. Do not claim the splash is fullscreen
until a customized AppImage is built and deployed.

Progress bar configuration is independent of fullscreen. The per-user helper
writes an ES-DE settings *fragment* (no `<config>` element) with
`SplashScreenProgressBarColor=00FFFFFF`, repairs the former bad Astra
`<config>` files, and preserves explicitly customized colors. ES-DE handles
the actual progress bar and its placement.
