# Oracle OS v2 - MCP Agent Instructions

You have Oracle OS, a tool that lets you see and operate any macOS application
through the accessibility tree AND visual perception. Every button, text field,
link, and label is available -- either through the AX tree (native apps) or
vision-based grounding (web apps where Chrome exposes everything as AXGroup).

## Rule 1: Always Check Recipes First

Before doing ANY multi-step task manually, call `oracle_recipes`.

If a recipe exists for what you need, use `oracle_run` with the recipe name
and parameters. Recipes are tested, reliable, and faster than manual steps.

## Rule 2: Orient Before Acting

Before interacting with any app, call `oracle_context` with the app name.

This tells you: which app/window is active, the current URL (for browsers),
what element is focused, what interactive elements are visible, and the
canonical fused observation snapshot Oracle is using internally.

**If you skip this, you will click the wrong thing.**

## Rule 3: How to Find Elements

Use `oracle_find` with the most specific identifier available:
- `dom_id` for web apps (most reliable, bypasses depth limits)
- `identifier` for native apps with developer IDs
- `query` + `role` for general searches (e.g., query:"Compose", role:"AXButton")
- `query` alone as a fallback

Use `oracle_inspect` to examine an element before acting on it.
Use `oracle_element_at` to identify elements from screenshots.

## Rule 4: How Focus Works

**Perception tools work from background** (no focus needed):
- oracle_context, oracle_state, oracle_find, oracle_read, oracle_inspect,
  oracle_element_at, oracle_screenshot

Note: `oracle_screenshot` captures windows even when they are behind other
windows or in another Space. It does NOT need the app to be focused. If all of
an app's windows are closed (not just minimized), screenshot will return an
error -- you cannot capture what does not exist.

**Click and type try AX-native first** (no focus), then synthetic fallback (auto-focuses):
- oracle_click, oracle_type

**Press, hotkey, scroll need focus** - always pass the `app` parameter:
- oracle_press, oracle_hotkey, oracle_scroll

Focus is restored for click/type wrappers. Press, hotkey, and scroll target the
frontmost app directly and should be treated as live input.

## Rule 5: Key Patterns

### Navigate Chrome to a URL
```
oracle_hotkey keys:["cmd","l"] app:"Chrome"  -> address bar focused
oracle_type text:"https://example.com"       -> URL entered
oracle_press key:"return" app:"Chrome"       -> navigate
oracle_wait condition:"urlContains" value:"example.com" app:"Chrome"
```

### Fill a form
```
oracle_click query:"Compose" app:"Chrome"    -> click button
oracle_type text:"hello@example.com" into:"To" app:"Chrome"
oracle_press key:"tab" app:"Chrome"          -> move to next field
oracle_type text:"Subject line" into:"Subject" app:"Chrome"
```

### Wait instead of guessing
```
oracle_wait condition:"elementExists" value:"Send" app:"Chrome"
oracle_wait condition:"urlContains" value:"inbox" timeout:15 app:"Chrome"
oracle_wait condition:"elementGone" value:"Loading" app:"Chrome"
```

## Rule 6: Vision Fallback for Web Apps

When `oracle_find` or `oracle_click` can't locate an element (common in web apps
like Gmail, Slack, etc. where Chrome exposes everything as AXGroup), Oracle OS
automatically falls back to VLM-based vision grounding if the vision sidecar
is running.

You can also use vision tools directly:

### oracle_ground - Find element by visual description
```
oracle_ground description:"Compose button" app:"Chrome"
-> Returns: {x: 86, y: 223, confidence: 0.8, method: "full-screen"}
```

For overlapping UI panels (e.g., compose popup over inbox), use crop_box
to narrow the search area for dramatically better accuracy:
```
oracle_ground description:"Send button" app:"Chrome" crop_box:[510, 168, 840, 390]
-> Returns: {x: 620, y: 350, confidence: 0.95, method: "crop-based"}
```

Then click at the returned coordinates:
```
oracle_click x:86 y:223 app:"Chrome"
```

### oracle_parse_screen - Experimental full-screen parser
```
oracle_parse_screen app:"Chrome"
-> Returns experimental full-screen parse output from the vision sidecar
```
Note: `oracle_parse_screen` is sidecar-backed, but its output is still
experimental. Use `oracle_find` for AX-based element search when you need the
most stable runtime behavior, and `oracle_ground` for visual disambiguation.

## Rule 7: Handle Failures

If an action fails:
1. Call `oracle_context` to see current state
2. Call `oracle_screenshot` for visual confirmation
3. Try `oracle_ground` with a description of what you need to click
4. Try a different approach (different query, coordinates, etc.)

Don't retry the same thing 5 times. If oracle_click fails, it already tried
AX-native, synthetic, AND VLM vision grounding. The element might not exist,
might be hidden, or might be blocked by a modal.

If `oracle_screenshot` fails for a background app, the window may be minimized
or in another Space. Oracle OS will attempt to capture it off-screen first. If
that fails, it will briefly activate the app to bring it on-screen. If the app
has no open windows at all, screenshot will return a specific error telling you.

## Rule 8: Web App Interaction (Chrome/Electron)

Chrome exposes most web elements as AXGroup -- `oracle_find` may not locate
buttons or inputs by name. **Always prefer `dom_id` for web apps.**

Pattern:
```
oracle_find query:"Send" role:AXButton app:"Chrome"  -> get dom_id from result
oracle_click dom_id:":oq" app:"Chrome"               -> click by dom_id
```

`dom_id` clicks are the MORACLE reliable method for any web app button.

If `oracle_find` returns nothing, use `oracle_ground` with `crop_box` for
visual grounding.

For text input in web apps, click the field first (by dom_id or coordinates),
then use `oracle_type`.

## Rule 9: Gmail / Email Pattern

Gmail's popup compose window does not reliably accept keyboard input from
synthetic events. Use URL-based compose instead:

```
Navigate to: https://mail.google.com/mail/?view=cm&fs=1&to=EMAIL&su=SUBJECT&body=BODY
```

Wait for the page to load, then find and click the Send button using dom_id.
The Send button's dom_id changes between sessions -- always `oracle_find` it
first rather than hardcoding.

## Rule 10: Coordinate Mapping

Screenshots are downsampled to 1280px max width. Pixel coordinates in the
screenshot image are NOT the same as screen coordinates.

- Use `oracle_ground` for visual-to-screen coordinate translation
- Use `oracle_find` to get element positions (always in screen coordinates)
- The screenshot response includes `window_frame` with the actual screen
  position and size of the captured window

## Rule 11: Vision Grounding Best Practices

**ALWAYS use `crop_box` with `oracle_ground`** when you know the approximate
area. It is 10x faster (250ms vs 3s) and much more accurate.

- `crop_box` format: `[x1, y1, x2, y2]` in logical screen points
- For overlapping UI (popups, dropdowns, compose windows), `crop_box` is
  ESSENTIAL to prevent the VLM from grounding to the wrong layer
- Get crop coordinates from `oracle_find` element positions or `oracle_state`
  window positions

## Rule 12: Wait Between Actions

Web apps need time to react to clicks. Always use `oracle_wait` after clicking
buttons before proceeding:

```
oracle_click query:"Submit" app:"Chrome"
oracle_wait condition:"elementExists" value:"Success" app:"Chrome"
```

Common wait conditions:
- `urlContains` -- wait for navigation
- `titleContains` -- wait for page title change
- `elementExists` -- wait for an element to appear
- `elementGone` -- wait for a loading indicator to disappear
- `focusEquals` -- wait for a field or control to become focused
- `valueEquals` -- wait for the focused element value to match expected text

## Tool Reference

| Tool | Purpose | Needs Focus? |
|------|---------|-------------|
| oracle_context | Where am I? URL, focused element, actions | No |
| oracle_state | All running apps and windows | No |
| oracle_find | Find elements by text, role, DOM id | No |
| oracle_read | Read text content from screen | No |
| oracle_inspect | Full element metadata | No |
| oracle_element_at | What's at these coordinates? | No |
| oracle_screenshot | Visual capture for debugging | No |
| oracle_click | Click element or coordinates | Auto |
| oracle_type | Type text, optionally into a field | Auto |
| oracle_press | Press single key | Yes - use `app` |
| oracle_hotkey | Key combo (cmd+s, etc.) | Yes - use `app` |
| oracle_scroll | Scroll content | Yes - use `app` |
| oracle_focus | Bring app to front | N/A |
| oracle_window | Window management | No |
| oracle_wait | Wait for condition | No |
| oracle_recipes | List recipes | No |
| oracle_run | Execute recipe | Auto |
| oracle_recipe_show | View recipe details | No |
| oracle_recipe_save | Save new recipe | No |
| oracle_recipe_delete | Delete recipe | No |
| oracle_parse_screen | Experimental full-screen parsing via the vision sidecar | No |
| oracle_ground | Find element coordinates via VLM | No |
