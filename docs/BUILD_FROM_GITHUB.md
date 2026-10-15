# Build FlowTV from GitHub

This project intentionally lets CI generate the Android and Windows runner scaffolding with the current stable Flutter SDK (Flutter 3.38 or newer). The repository contains the UI/application source, Android PiP patcher, assets, and workflows.

1. Create an empty GitHub repository.
2. Extract `FlowTV-Source.zip` and upload the extracted files/folders to the repo root (including `.github/workflows`). Commit to `main`.
3. Open the repo's **Actions** tab and wait for the two workflows to finish, or run each with **Run workflow**.
4. From the completed Android workflow, download the `FlowTV-Android-APKs` artifact. From the Windows workflow, download `FlowTV-Windows-x64`.
5. Install the correct APK for your device ABI. On most recent Android devices that is `arm64-v8a`. For Windows, extract the whole ZIP and run `FlowTV.exe`/`flowtv.exe` from the extracted folder; keep the supporting DLLs beside it.

The APK is a CI-built release APK intended for direct testing and is not signed with a Play Store upload key. The Windows build is not code-signed.
