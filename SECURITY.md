# Safety and security reports

Myohm is a research/teaching engineering candidate. Report electrical hazards, unexpected excitation, charger faults and BLE/data-integrity defects with hardware revision and firmware hash. Avoid uploading participant data or credentials. Use GitHub’s "Report a vulnerability" option in the Security tab when available. The maintainer must enable and verify this private reporting channel before the public release; it could not be verified while this repository was private. Never put exploit details, participant data or credentials in a public issue.

Do not connect the device to a person outside an ethics-approved research protocol, and read the Safety section of the README first. USB, SWD and bench instruments can create additional current paths: disconnect them before any on-body measurement. See `docs/validation.md` for the release gates and `docs/hardware-audit.md` for known blockers.

## Data and radio limitations

The current firmware GATT characteristics use plain read/write permissions and
have no application-level peer authentication requirement. A device name or
service UUID does not establish trusted identity. Do not treat BLE traffic as a
confidential or authenticated channel, or use this candidate with sensitive
participant data. Adding pairing/security requires a separate firmware/client
compatibility change and physical validation.

Native clients store measurements locally and disable automatic OS backup.
Explicit JSON exports include a device identifier and timestamps; exported files
may be sent to a cloud destination chosen in the system file picker. The web
client persists history in browser localStorage, accessible to other scripts on
the same origin. Use a dedicated origin and clear site data on shared computers.
No account, analytics or cloud measurement service is implemented in these
clients. HTTPS protects delivery of the web application; it does not authenticate
the BLE peripheral. JSON preserves raw identifiers; web CSV exports neutralize
formula-like text for spreadsheet use.
