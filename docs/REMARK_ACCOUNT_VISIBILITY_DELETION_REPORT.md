# Digital Share – Contact Remarks, Account Visibility & Account Deletion Implementation Report

**Document Date:** November 5, 2026  
**Application Target:** Digital Share Mobile (Flutter 3.47.7 / Android ARM64) & ASP.NET Core 8 Backend (PostgreSQL)  
**Status:** Implementation Complete & Fully Verified  
**Artifact Directory / Release APK:** `mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (93.16 MB)

---

## Executive Summary

This report documents the architectural design, backend and mobile implementation, database migration, automated testing, and release artifact verification for three core features:
1. **Feature 1: Contact Remarks** – Optional personal note (up to 2,000 characters) captured upon business card save with live character counting, "Skip & Save", dedicated "My Personal Remark" card section on contact details with Edit/Clear capabilities, complete preservation during ordinary contact field edits, and strict owner-only privacy.
2. **Feature 2: Public and Private Account Settings** – Account discovery configuration under **Profile → Preferences & Settings → Account Visibility** with Private mode as the default. Public mode exposes strictly an allowlist of public profile fields (`ShareId`, `FullName`, `Company`, `JobTitle`, `ProfilePhotoUrl`) in user directory search; Private mode completely hides the user from search while preserving direct QR/link sharing. Personal remarks, imported cards, phone numbers, and emails are never exposed.
3. **Feature 3: Delete Entire Account** – A 4-step destructive confirmation wizard under **Profile → Preferences & Settings → Delete Account** (Warning → Live Data Summary → Password Reauthentication → Final Checkbox & 'DELETE' confirmation). Backend executes a transactional cascading deletion across all user-owned records (including foreign-key restricted meeting requests) followed by safe disk/cloud storage cleanup of card scans and profile photos. The mobile client wipes all secure tokens, local contact records, and navigates immediately to the `LoginScreen`.

---

## 1. Feature 1: Contact Remarks

### 1.1 Mobile User Experience
* **Scan Save Prompt (`BusinessCardReviewScreen`):**
  * When a user taps "Save in Digital Share", a modern modal bottom sheet (`_showRemarkBottomSheet`) is presented.
  * Header displays `Icons.note_alt_outlined` with title **"Add a personal remark"** and subtitle: *"Add a nickname or a note to help you remember this person."*
  * Multiline text input with 2,000 character limit, live character counter (`X / 2000`), and contextual placeholder:  
    *`e.g., Met at Chennai conference, referred by Rajesh, follow up next Monday...`*
  * Three explicit actions:
    * **Save:** Saves the card with the personal remark attached (`SaveImportedContactRequest.PersonalRemark`).
    * **Skip & Save:** Proceeds immediately with card persistence while keeping `PersonalRemark = null`.
    * **Cancel:** Closes the modal bottom sheet without saving.
* **Contact Details Screen (`ImportedContactDetailsScreen`):**
  * Dedicated **"MY PERSONAL REMARK"** card section with private lock indicator (`Icons.lock_outline_rounded`, *"Private Note"*).
  * If a remark exists, renders the full text and an **"Edit"** button.
  * If no remark exists, displays: *"No personal remark added yet."* (italicized) and an **"Add Remark"** button.
  * Tapping Edit/Add Remark opens `_showEditRemarkDialog`:
    * Supports editing the text with live counter.
    * Offers a red **"Clear"** button if an existing remark is present (invokes `clearRemark(contact.id)`).
    * Offers **"Save"** to submit the updated note (invokes `updateRemark(contact.id, text)`).
* **Edit Contact Screen (`EditImportedContactScreen`):**
  * When editing other contact fields (Name, Phone numbers, Emails, Company, Address, Website), `PersonalRemark` is explicitly preserved. The backend update logic treats `PersonalRemark == null` in general updates as "do not alter existing remark".

### 1.2 Backend API & Database Implementation
* **Entity Update (`ImportedBusinessCard.cs`):**
  * Added `[MaxLength(2000)] public string? PersonalRemark { get; set; }`.
  * Configured in `ApplicationDbContext.cs` with maximum length 2000.
* **DTOs (`ImportedContactDtos.cs`):**
  * `SaveImportedContactRequest`: Added `[MaxLength(2000)] public string? PersonalRemark { get; set; }`.
  * `UpdateImportedContactRequest`: Added `[MaxLength(2000)] public string? PersonalRemark { get; set; }`.
  * `ImportedContactResponse`: Added `public string? PersonalRemark { get; set; }`.
  * `UpdateContactRemarkRequest`: Created with `[MaxLength(2000)] public string? Remark { get; set; }`.
* **Endpoints (`ImportedContactsController.cs`):**
  * `PUT /api/imported-contacts/{id}/remark` – Updates or adds the personal remark for the card.
  * `DELETE /api/imported-contacts/{id}/remark` – Clears the personal remark.
* **Privacy Isolation:**
  * Personal remarks are stored exclusively in `ImportedBusinessCards` scoped to `OwnerUserId`.
  * Public endpoints (`/api/share/{shareId}`, `/api/profile/search`) query `UserProfiles` and never join or reference `ImportedBusinessCards`.

---

## 2. Feature 2: Public and Private Account Settings

### 2.1 Mobile User Experience
* **Navigation:** **Profile → Preferences & Settings → Account Visibility** (`AccountVisibilityScreen`).
* **Interactive Options:**
  1. **Private Account (Default):**
     * Tagged with a **"Default"** badge.
     * Subtitle: *"Your profile is completely hidden from public searches and discovery. Only people with whom you explicitly share your QR code or direct link can view your digital business card."*
  2. **Public Account:**
     * Subtitle: *"Your profile is discoverable by other Digital Share users in search. Anyone can search by name, company, or job title and view your business card profile (Full Name, Company, Job Title, Profile Photo, and Share ID)."*
* **State Management & Feedback:**
  * Loads current state via `ProfileService.getVisibility()`.
  * Visual active state indicator with animated border and radio indicator.
  * Instant update feedback via floating `SnackBar`:
    * *"Account is now Public and discoverable."*
    * *"Account is now Private and hidden from search."*

### 2.2 Backend Search & Privacy Filtering
* **Entity Update (`UserProfile.cs`):**
  * Added `public bool IsPublic { get; set; } = false;`.
  * Configured in `ApplicationDbContext.cs` with default value `false`.
* **Endpoints (`ProfileController.cs`):**
  * `GET /api/profile/visibility` – Returns `{ "isPublic": bool }`.
  * `PUT /api/profile/visibility` – Updates visibility and returns `{ "isPublic": bool }`.
  * `GET /api/profile/search?q={query}&limit=20` – Searches public accounts.
* **Strict Allowlist Projection (`PublicProfileSearchResultDto.cs`):**
  * Backend search strictly filters:
    ```csharp
    var queryable = _dbContext.UserProfiles
        .AsNoTracking()
        .Where(p => p.IsPublic && p.UserId != currentUserId);
    ```
  * Projection allows **ONLY** 5 fields:
    ```csharp
    .Select(p => new PublicProfileSearchResultDto
    {
        ShareId = p.ShareId,
        FullName = p.FullName,
        Company = p.Company,
        JobTitle = p.JobTitle,
        ProfilePhotoUrl = p.ProfilePhotoUrl
    })
    ```
  * **Strict Data Leak Prevention:** Internal database IDs (`Id`, `UserId`), emails, phone numbers, addresses, bios, availability, scan jobs, and personal remarks are **never** projected or returned by the search endpoint.

---

## 3. Feature 3: Delete Entire Account

### 3.1 Mobile User Experience
* **Navigation:** **Profile → Preferences & Settings → Delete Account** (`DeleteAccountScreen`).
* **4-Step Wizard Flow:**
  1. **Step 1: Warning**
     * Error-themed header with `Icons.warning_amber_rounded`.
     * Explicit message: *"This action is permanent and completely irreversible. Once your account is deleted, your data cannot be recovered under any circumstances."*
     * Itemized breakdown of all assets marked for deletion.
  2. **Step 2: Data Summary**
     * Queries local and remote counts:
       * `X imported cards and personal notes will be deleted.`
       * `Y user connections will be removed.`
       * `Z scheduled meetings will be cancelled.`
  3. **Step 3: Password Reauthentication**
     * Obscured password field requiring the user's current account password.
     * Prevents proceeding with empty input.
  4. **Step 4: Final Confirmation**
     * High-visibility danger container (*"Final Warning - Point of no return"*).
     * Mandatory confirmation checkbox: *"I understand this action cannot be undone."*
     * Explicit confirmation input: requires typing `"DELETE"`.
     * Destructive button: **"Permanently Delete My Account"**.
* **Post-Deletion Cleanup:**
  * Wipes all tokens from `FlutterSecureStorage`.
  * Calls `LocalContactRepository.clearAllLocalContacts()` to purge local cached database records and stored images.
  * Navigates via `Navigator.pushAndRemoveUntil` to `LoginScreen`, clearing the entire navigation stack.
  * Displays notification: *"Your account and all associated data have been permanently deleted."*

### 3.2 Backend Deletion & Cascade Architecture
* **Endpoint (`AuthController.cs`):**
  * `POST /api/auth/delete-account` (and alias `DELETE /api/auth/account`).
  * Validates current user session and verifies password via `UserManager.CheckPasswordAsync(user, request.Password)`.
* **Transactional Cascading Deletion (`AuthService.cs`):**
  * Resolves foreign key restrict constraints:
    1. `MeetingRequests`: Deletes all records where `RequesterUserId == userId || RecipientUserId == userId` (resolving EF Core `DeleteBehavior.Restrict`).
    2. `AvailabilitySlots` & `AvailabilitySettings`: Removes all records for `userId`.
    3. `Connections`: Removes all connections owned by `userId` or referencing the user's `ProfileId`.
    4. `ImportedBusinessCards`: Removes all cards and cascading phone numbers / email addresses.
    5. `ScanJobs`: Removes all processing jobs.
    6. `RefreshTokens`: Revokes and deletes all tokens for `userId`.
    7. `UserProfiles`: Removes profile record.
    8. `AspNetUsers`: Removes Identity user.
  * In relational production environments (PostgreSQL), executes inside an execution strategy with `BeginTransactionAsync()` and `CommitAsync()`. In test environments (InMemory), executes safely without unsupported in-memory transactions.
* **Storage File Cleanup:**
  * After the database transaction commits, `IScanImageStorageService` and `IFileStorageService` clean up disk/cloud files for profile photos and scan images. File deletion is fail-soft so an inaccessible temporary file never prevents complete account deletion.

---

## 4. Database Migration

EF Core migration generated and applied to model snapshot:

* **Migration File:** `backend/DigitalShare.Api/Migrations/20261105074425_AddRemarksAndAccountVisibility.cs`
* **Schema Modifications:**
  ```csharp
  migrationBuilder.AddColumn<string>(
      name: "personal_remark",
      table: "imported_business_cards",
      type: "character varying(2000)",
      maxLength: 2000,
      nullable: true);

  migrationBuilder.AddColumn<bool>(
      name: "is_public",
      table: "user_profiles",
      type: "boolean",
      nullable: false,
      defaultValue: false);
  ```

---

## 5. Automated Verification & Test Results

### 5.1 Backend Integration & Unit Tests (`DigitalShare.Api.Tests`)
* **Test Suite:** `RemarksVisibilityAndDeletionTests.cs` (10 tests)
* **Total Backend Test Suite:** **259 Tests**
* **Result:** **259 Passed, 0 Failed, 0 Skipped** (Duration: 14 seconds)

| Test Name | Scenario Tested | Status |
|:---|:---|:---:|
| `SaveContact_WithPersonalRemark_PersistsAndReturnsRemark` | Saves contact with remark, verifies DB persistence & response | **PASSED** |
| `SaveContact_WithoutPersonalRemark_SavesSuccessfully` | Saves contact with null remark, verifies null handling | **PASSED** |
| `UpdateRemark_ExplicitEndpoint_UpdatesRemarkText` | Invokes `PUT /remark` to update existing note | **PASSED** |
| `ClearRemark_ExplicitEndpoint_RemovesRemark` | Invokes `DELETE /remark` to wipe note | **PASSED** |
| `UpdateContact_OrdinaryUpdate_DoesNotOverwriteExistingRemark` | Updates contact company/name without remark; remark persists | **PASSED** |
| `PersonalRemarks_IsolatedToOwner_NotLeakedToOtherUsers` | User B cannot view or modify User A's remark (404 Not Found) | **PASSED** |
| `ProfileVisibility_DefaultIsPrivate` | New registered user profile defaults `IsPublic = false` | **PASSED** |
| `ProfileVisibility_Toggle_UpdatesPublicPrivateState` | Toggles visibility between Public and Private via API | **PASSED** |
| `ProfileSearch_StrictlyFiltersPublicProfilesAndExcludesPrivate` | Public accounts appear in search; Private accounts are excluded | **PASSED** |
| `AccountDeletion_SuccessfulDeletion_WipesAccountAndRelatedData` | Complete cascading wipe + login rejection + 404 profile verification | **PASSED** |

### 5.2 Mobile Unit & Widget Tests (`flutter test`)
* **Test Suite 1:** `test/contact_remarks_test.dart` (5 tests)
  * `ImportedContact serializes and deserializes personalRemark` (**PASSED**)
  * `LocalContactRecord preserves personalRemark across copyWith and conversions` (**PASSED**)
  * `LocalContactRepository preserves personalRemark on ordinary update` (**PASSED**)
  * `Shows default text when no personal remark exists` (**PASSED**)
  * `Shows remark text and Edit button when remark exists` (**PASSED**)
* **Test Suite 2:** `test/visibility_and_account_deletion_test.dart` (3 tests)
  * `UserProfile defaults isPublic to false` (**PASSED**)
  * `AccountVisibilityScreen renders Private default and allows toggling to Public` (**PASSED**)
  * `DeleteAccountScreen navigates through 4 steps with validations` (**PASSED**)
* **Regression Test Suite:** `test/business_card_review_screen_test.dart` (6 tests)
  * All 6 existing card review tests (**PASSED**)
* **Static Analysis:** `flutter analyze mobile` → **No issues found! (0 errors, 0 warnings, 0 lints)**

---

## 6. Fresh Android Release APK Verification

Compiled using the isolated ARM64 target command:  
`flutter build apk --release --target-platform android-arm64 --split-per-abi`

### 6.1 APK Properties
* **File Path:** `mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
* **File Size:** **97,685,366 bytes (93.16 MB)**  *(Strictly below the 100 MB ceiling)*
* **SHA-256 Checksum:**  
  `E1AF1BBE6580E2620D35D07EE9EEE723E47D36A0B5A9C2C539C581EF9EAE4FE0`

### 6.2 Package & Manifest Verification (`aapt dump badging`)
* **Package Name:** `com.digitalshare.digital_share`
* **Version Code:** `2001`
* **Version Name:** `1.0.0`
* **Min SDK Version:** `24` (Android 7.0+)
* **Target SDK Version:** `36` (Android 16 Ready)
* **Compile SDK Version:** `36`
* **Target Native Architecture:** `arm64-v8a`

### 6.3 Signing Verification (`apksigner verify --verbose`)
* **Verification Status:** `Verifies (true)`
* **APK Signature Scheme v1 (JAR signing):** `false` (modern APK layout)
* **APK Signature Scheme v2 (Full APK Signature):** **`true`**
* **Signer #1 Certificate DN:** `C=US, O=Android, CN=Android Debug`
* **Signer #1 SHA-256 Digest:** `9b5c1b229c1f319ba122173a8554e92905bcd662d138a2c063930a912f9459cd`

---

## 7. Mandatory Constraints & Architecture Checklist

| Constraint / Requirement | Verification Result |
|:---|:---|
| Online-only architecture preserved | **Compliant** – No offline sync queues added for remarks/visibility/deletion. |
| PaddleOCR PP-OCRv5 Mobile preserved | **Compliant** – On-device OCR assets and inference pipeline untouched. |
| Google ML Kit OCR preserved | **Compliant** – Secondary fallback engine active and integrated. |
| Gemini Multimodal Extraction preserved | **Compliant** – Online scans continue to trigger full multimodal backend verification. |
| Gemini API key hidden from mobile APK | **Compliant** – Zero Gemini secrets in mobile bundle; executed strictly via backend. |
| PostgreSQL + ASP.NET Core 8 backend preserved | **Compliant** – Built on existing C# controller and EF Core service architecture. |
| ARM64 APK size strictly below 100 MB | **Compliant** – **93.16 MB** (within the 100 MB limit). |
| Zero Git commits or pushes made | **Compliant** – Working copy modified only; no git commit or push executed. |
| No production DB modifications or deployments | **Compliant** – Railway environment and production database left untouched. |

