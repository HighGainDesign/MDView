# MDView demo assets

These assets show MDView 1.1.0/build13, including live streaming and individual
change review.

- `live-streaming.mp4`: 24.9-second silent H.264 demo, 1920×1080 at 30 fps.
- `live-streaming.gif`: looping 960×540 README preview at 20 fps.
- `live-streaming-poster.jpg`: still from the table-rendering portion of the video.
- `viewer.jpg`: the basic viewer with tables, lists, and a checklist.
- `outline-sidebar.jpg`: persistent heading navigation.
- `change-review.jpg`: two saved changes, before/after comparison, and the
  individual **Mark This Reviewed** and **Mark All Reviewed** buttons.

All three are actual native-window JPEG captures, 1840×1584. The pointer was
outside the captured window. They use an original, disposable sample document;
no personal files, draft lists, or actions appear. No UI was fabricated.

The video uses simultaneous, continuous recordings of the actual Drafts and
MDView windows through Apple ScreenCaptureKit. Idle intervals were trimmed;
window crops and explanatory labels were added. It demonstrates typing,
Markdown table rendering, Pause while writing, and Resume catching up. Timing
is illustrative rather than a latency benchmark. The pointer and audio are
excluded. The editor shows only an original disposable sample: no private
draft lists, actions, or other windows appear. This replaces the rejected
edited-still demo.

Drafts is the tested streaming integration. Other publishers using the public
Marked-compatible channel are accepted but have not been manually verified.
Drafts may require Marked to be installed to enable streaming; Marked can stay
closed. MDView is not affiliated with Marked or Drafts.

## Suggested launch copy

> I made MDView: a small, read-only Markdown viewer for macOS. Keep it beside
> Drafts for live streaming, open documents from your coding agent, or press Space
> in Finder for Quick Look. Saved files refresh automatically, with highlights
> and a comparison panel. Review changes individually or all at once without
> modifying the Markdown file.
>
> Free and open source: https://github.com/HighGainDesign/MDView

No posts, uploads, or messages have been sent to social channels.
