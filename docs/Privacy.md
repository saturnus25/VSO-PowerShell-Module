# Privacy

The module has no telemetry, analytics, advertising or remote reporting endpoint. Import loads local function definitions and fingerprints runtime files. Getters read local installation metadata and process information; they do not submit those data to the maintainer.

Installation and updates contact GitHub's official release API and release-asset endpoints. Those services receive normal network request information, such as the source IP and module User-Agent, under their own privacy terms. Release downloads and local receipts are needed to validate the application. Receipts contain local paths, installation identity, scope, versions, timestamps and file hashes. UAC requests and results use a local protected temporary channel. Error output and user-created transcripts can contain local paths; review them before sharing.

PowerShell Gallery and GitHub independently process package installation and repository traffic under their service policies. The module neither collects Gallery credentials nor publishes packages at runtime. Publication credentials belong solely to separate developer tooling and are not stored in the package. No user account or API key is required by the application manager's public commands.
