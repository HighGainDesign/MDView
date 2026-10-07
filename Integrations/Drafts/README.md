# Preview in MDView

The action is bundled inside MDView. If Drafts is installed, MDView offers to install it once at startup. You can also open **MDView → Settings… → Install Drafts Action…** at any time. This opens Drafts’ import dialog so you choose where to put the action. Dragging MDView into Applications does not automatically change Drafts.

The bundled action has one macOS URL step, URL-encoded tags, and **Do Nothing** after success. It does not archive, trash, flag, tag, or save the source draft. The export is `Preview in MDView.draftsAction` in this folder.

The simplest Drafts action uses one **URL** step. On macOS:

1. Create an action called **Preview in MDView**.
2. Add a URL step with this template:

   ```text
   mdview://preview?text=[[draft]]&title=[[title]]
   ```

3. Keep **URL encode tags** enabled, **Open in Drafts** disabled, and the step enabled on macOS.
4. Set the action’s iOS visibility off until an iOS MDView app is available.
5. Launch MDView once, then run the action on a draft.

The action sends a snapshot to MDView without writing a file. Run it again after editing. File-backed documents refresh automatically; Drafts snapshots do not. Large drafts may exceed the practical limit of macOS URL handoff; export those as Markdown files and open them instead.

`Preview in MDView.js` is an equivalent Script-step alternative. Use one approach per action.

Drafts’ [URL step documentation](https://docs.getdrafts.com/docs/actions/steps/advanced) explains URL-encoded template tags.
