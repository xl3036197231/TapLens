# TapLens Analysis Context

TapLens separates observations by where they were produced so that a model's interpretation is never presented as independently observed behavior.

## Language

**Local Evidence**:
An observation produced on the phone from static decoding or preview, identified by an `Lxx` evidence ID.
_Avoid_: Cloud finding, sandbox evidence

**Cloud Static Evidence**:
An observation produced by a deterministic server-side parser in an isolated, non-executing environment, identified by a `Cxx` evidence ID.
_Avoid_: AI conclusion, device behavior

**Cloud Browser Evidence**:
An observation produced by the controlled HTTP(S) browser sandbox, identified by a `Cxx` evidence ID.
_Avoid_: QR execution, mobile sandbox evidence

**AI Interpretation**:
A schema-validated report derived only from supplied evidence; it is not an observation source and cannot create evidence.
_Avoid_: AI evidence, AI sandbox

**Fixed QR Fixture**:
A repository-owned synthetic QR sample whose canonical payload can be resolved by the server from a sample identifier and digest.
_Avoid_: Arbitrary user QR, verified real-world target

**External Action**:
An effect outside TapLens static analysis, such as launching an app, opening a fallback URL, connecting Wi-Fi, sending a message, placing a call, importing a contact, downloading a file, or installing software.
_Avoid_: Analysis, preview
