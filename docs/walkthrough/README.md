# Bowerbird walkthrough

Index a folder, find duplicates, and rename and organize files from reviewed proposals that change nothing until you type APPLY.

> **Status: skeleton.** The screenshots below are placeholders. Zombie Admin captures them with demo data, and the Chief of Staff scans them for sensitive content before they are added (team directive 10). Until then the image links do not resolve.

## Before you start

- Windows PowerShell 5.1 (part of Windows). No administrator rights and no installer.
- Microsoft Edge or Google Chrome.
- Launch: Double-click `Start-Bowerbird.bat` (or `Start-Bowerbird.bat -Root "C:\TestWorkspace"` to pick the folder to scan).
- A disposable or approved folder to scan.

## Steps

### 1. First launch

Bowerbird Studio opens on **File Explorer** with the folder to scan.

![Bowerbird Studio File Explorer on first launch, with the demo folder in Folder to scan.](../assets/walkthrough/01-first-launch.png)

### 2. Build the index

Select **Build Index**. Files and folders appear with a preview of the selected file.

![Bowerbird File Explorer after Build Index, showing the demo files and folders with a file preview.](../assets/walkthrough/02-build-index.png)

### 3. Search

**Search** finds indexed files by name, and by content if you turned content indexing on.

![Bowerbird Search page with results for the demo search term turnover.](../assets/walkthrough/03-search.png)

### 4. Find duplicates

**Duplicates** groups identical files.

![Bowerbird Duplicate Detection page with one pair of identical demo screenshots.](../assets/walkthrough/04-duplicates.png)

### 5. Rename screenshots

**Smart Rename** proposes new names with a confidence and destination. Nothing changes until you type `APPLY`.

![Bowerbird Smart Rename page with rename proposals for the demo screenshots, showing confidence and destination before APPLY.](../assets/walkthrough/05-smart-rename.png)

### 6. Organize by rules

**Organize** turns JSON rules into a move plan you inspect before applying. **Undo Last Apply** reverses it.

![Bowerbird Rule-Based Organization page with the example rules and a proposed move plan, not yet applied.](../assets/walkthrough/06-organize-plan.png)

### 7. Check health

**Diagnostics** runs backend health checks and builds a support package.

![Bowerbird Diagnostics and Feedback page with the backend health checks passing.](../assets/walkthrough/07-diagnostics.png)

## About these images

Images live in [`docs/assets/walkthrough/`](../assets/walkthrough/), named `NN-<screen>.png` after the step they belong to. They are 1440x900 at 100% scale in the Dark (Bowerbird has one theme) theme, and show demo data only.
