using DigitalShare.Api.DTOs.Consent;

namespace DigitalShare.Api.Services;

public class LegalDocumentService : ILegalDocumentService
{
    public const string CurrentTermsVersion = "2026.1";
    public const string CurrentPrivacyPolicyVersion = "2026.1";
    public const string CurrentCookiePolicyVersion = "2026.1";

    public LegalDocumentResponse GetLegalDocuments(string? rawJurisdiction)
    {
        var jurisdiction = NormalizeJurisdiction(rawJurisdiction);

        return jurisdiction switch
        {
            "IN" => BuildIndiaDocuments(),
            "EU" => BuildEuDocuments(),
            "GB" or "UK" => BuildUkDocuments(),
            "US" => BuildUsDocuments(),
            _ => BuildGlobalDocuments(jurisdiction)
        };
    }

    private static string NormalizeJurisdiction(string? code)
    {
        if (string.IsNullOrWhiteSpace(code)) return "IN";
        var upper = code.Trim().ToUpperInvariant();
        return upper switch
        {
            "IN" or "IND" or "INDIA" => "IN",
            "US" or "USA" or "UNITED STATES" => "US",
            "GB" or "UK" or "GBR" or "UNITED KINGDOM" => "GB",
            "DE" or "FR" or "IT" or "ES" or "NL" or "BE" or "SE" or "PL" or "AT" or "IE" or "EU" => "EU",
            _ => "GLOBAL"
        };
    }

    private static LegalDocumentResponse BuildIndiaDocuments()
    {
        return new LegalDocumentResponse
        {
            Jurisdiction = "IN",
            TermsVersion = CurrentTermsVersion,
            PrivacyPolicyVersion = CurrentPrivacyPolicyVersion,
            CookiePolicyVersion = CurrentCookiePolicyVersion,
            GrievanceOfficer = "Data Protection & Grievance Officer, Medindia4u.com",
            ContactEmail = "privacy@medindia4u.com",
            TermsAndConditionsMarkdown = """
# Digital Share — Terms and Conditions (India)
*Version 2026.1 — Powered by Medindia4u.com*
*Compliance: Digital Personal Data Protection Act, 2023 & Information Technology Act, 2000*

Welcome to Digital Share. By creating an account, registering, accessing, or using our mobile application and services, you agree to be bound by these comprehensive Terms and Conditions.

### 1. Introduction
Digital Share is a smart contact exchange, digital business card, meeting scheduler, and physical card scanner application operated and maintained by Medindia4u.com ("we", "our", or "us"). These Terms form a legally binding contract between you and Medindia4u.com.

### 2. Definitions
- **"Application" / "Service":** The Digital Share mobile software application, backend APIs, and related web interfaces.
- **"User":** Any individual or entity that registers, accesses, or uses Digital Share.
- **"Business Card":** A physical or digital credential card bearing contact, designation, and company details.
- **"OCR":** Optical Character Recognition systems used to convert card imagery into editable structured text.
- **"Personal Memory":** Searchable user-authored private contextual notes associated with a contact.
- **"QR Code":** Two-dimensional matrix barcodes generated or scanned within the Service.

### 3. Eligibility to Use the Application
You must be at least 18 years of age and possess full legal capacity to enter into binding agreements under the Indian Contract Act, 1872. Use by minors is strictly permitted only under verified parental or legal guardian supervision.

### 4. Account Creation and Registration
To access Digital Share features, you must register an account by providing accurate, truthful, and complete information, including a verified email address, a secure password, and a mandatory mobile number. You agree to keep your registration details up to date.

### 5. Mandatory Mobile Number Requirements
A valid and active mobile telephone number with country calling code is mandatory for all user accounts. The mobile number is required to authenticate user sessions, prevent fraudulent automated registrations, support account recovery, and ensure compliance with Indian telecommunication and security regulations. Users may not register using disposable, temporary, or unauthorized phone numbers.

### 6. Account Security and Password Responsibilities
You are solely responsible for maintaining the confidentiality of your account credentials, passwords, and authentication tokens. Any action performed through your account is deemed your authorized act. You agree to notify us immediately at privacy@medindia4u.com upon suspecting any unauthorized access.

### 7. Digital Business Card Functionality
Digital Share empowers you to create and maintain customized digital business cards containing your name, job title, company, bio, telephone numbers, email addresses, websites, and profile images. You represent that all information displayed on your card belongs to you or you have authority to share it.

### 8. Business Card Scanning and Optical Character Recognition (OCR)
- When capturing physical business cards with your camera or importing card images, you warrant that you lawfully acquired the business card in a professional, commercial, or social setting.
- Digital Share uses on-device machine learning (PaddleOCR, Google ML Kit) and cloud-assisted verification (Google Gemini AI) to extract text strictly on your behalf.
- OCR text extraction is probabilistic; you are responsible for reviewing, editing, and verifying the accuracy of extracted contact fields before saving.

### 9. Contact Storage and Management
Contacts saved in Digital Share—whether through physical card scanning or QR code exchange—are stored securely in your private account repository. You may organize contacts, search across names, companies, and personal memory notes, and edit or delete records at any time.

### 10. QR Code Generation
The Application enables generation of customizable QR codes for website URLs, contact vCards, WhatsApp messaging, phone numbers, email addresses, SMS, Wi-Fi configuration, and GPS locations. You are solely responsible for verifying the safety and accuracy of the content embedded in your generated QR codes.

### 11. QR Code Scanning
The built-in Universal QR Scanner decodes external QR codes. You agree to exercise caution when opening scanned URLs or executing actions prompted by third-party QR codes. Medindia4u.com does not endorse or guarantee the safety of external websites accessed through scanned QR codes.

### 12. Digital Card Sharing
You may share your digital business card via direct QR display, web link, vCard export, email, or messaging apps. You retain control over the channels through which your contact details are distributed.

### 13. Meetings and Connection Requests
Digital Share allows users to configure weekly availability hours and schedule professional meetings. Users agree to use meeting scheduling respectfully and in good faith. Medindia4u.com is not responsible for the attendance, conduct, or outcome of scheduled meetings.

### 14. User-Generated Content
You retain all intellectual property rights and ownership in your uploaded card images, profile photos, contact entries, and personal notes. You grant Medindia4u.com a limited, non-exclusive license solely to host, process, and display such content to you for the provision of the Service.

### 15. User Responsibilities
You agree to use Digital Share in compliance with all applicable laws, including the Digital Personal Data Protection Act, 2023. You must not upload or distribute illegal, defamatory, obscene, infringing, or harmful material.

### 16. Prohibited Activities
You shall not:
- Reverse engineer, decompile, disassemble, or tamper with the application or its native models.
- Introduce viruses, trojans, worms, or malicious scripts.
- Use automated bots, scrapers, or crawlers to extract data.
- Harass, stalk, or send unsolicited commercial communications (spam) to contacts.
- Impersonate any person, business, or government authority.

### 17. Data Processing and Privacy
Our collection, storage, and processing of personal data are governed by our Privacy Policy, drafted in full compliance with the DPDP Act, 2023 and the Information Technology (Reasonable Security Practices and Procedures and Sensitive Personal Data or Information) Rules, 2011.

### 18. Cookie and Token Usage
Digital Share uses essential secure authentication tokens (short-lived JWTs and rotating refresh tokens) to maintain logged-in state. Optional anonymous usage analytics are collected only when explicitly consented to and may be disabled without restricting functionality.

### 19. Third-Party Services
Certain features interface with third-party tools (such as Google Gemini AI for verification, device dialers, and mapping applications). Use of third-party services is subject to their respective terms and privacy policies.

### 20. Service Availability
We endeavor to provide uninterrupted, reliable service. However, the Service is provided on an "as is" and "as available" basis. Temporary downtime may occur for maintenance, upgrades, or factors beyond our reasonable control.

### 21. Intellectual Property
All trademarks, logos, brand names ("Digital Share", "Powered by Medindia4u.com"), software code, UI designs, and proprietary algorithms are the exclusive intellectual property of Medindia4u.com and its licensors. Unauthorized commercial exploitation is prohibited.

### 22. Suspension and Account Termination
We reserve the right to suspend or terminate accounts that engage in fraudulent activity, violate these Terms, breach third-party rights, or compromise the security of the platform.

### 23. Account Deletion
You possess the absolute right to delete your account at any time via My Profile > Delete Account. Account deletion is permanent, immediate, and irreversible.

### 24. Data Retention and Deletion
Upon confirmed account deletion, all personal data, user profiles, saved contacts, personal memory notes, calendar availability, and uploaded card images are permanently purged from active databases and cloud storage in accordance with Section 8(7) of the DPDP Act, 2023.

### 25. Limitation of Liability
To the maximum extent permitted by applicable Indian law, Medindia4u.com, its directors, employees, and affiliates shall not be liable for any indirect, incidental, consequential, special, or punitive damages arising from your use or inability to use the Service.

### 26. Disclaimer of Warranties
We disclaim all warranties, express or implied, including merchantability, fitness for a particular purpose, non-infringement, and accuracy of OCR or AI interpretations.

### 27. Indemnification
You agree to indemnify, defend, and hold harmless Medindia4u.com and its officers from any claims, losses, liabilities, and expenses arising from your violation of these Terms or third-party rights.

### 28. Changes to the Application
We continuously innovate and may update, modify, or enhance features of Digital Share at any time to deliver a superior user experience.

### 29. Changes to Terms and Conditions
We may amend these Terms periodically. Notice of material changes will be provided in-app. Continued use after the effective date constitutes acceptance of the revised Terms.

### 30. Applicable Law and Jurisdiction
These Terms are governed by the laws of India. Any dispute arising out of or in connection with these Terms shall be subject to the exclusive jurisdiction of the competent courts in Chennai / Jaipur, India.

### 31. Grievance Redressal
In compliance with Rule 3(2) of the Information Technology (Intermediary Guidelines and Digital Media Ethics Code) Rules, 2021 and Section 13 of the DPDP Act, 2023:
- **Designation:** Data Protection & Grievance Officer
- **Organization:** Medindia4u.com
- **Email:** privacy@medindia4u.com / grievance@medindia4u.com
- **Acknowledgment:** Within 24 hours of receipt.
- **Resolution:** Redressed within 15 calendar days.

### 32. Contact Information
For questions, support, or legal inquiries:
- **Service Name:** Digital Share
- **Platform Provider:** Medindia4u.com
- **Support Email:** support@medindia4u.com
- **Privacy Office:** privacy@medindia4u.com
""",
            PrivacyPolicyMarkdown = """
# Digital Share — Privacy Policy (India)
*Compliance: Digital Personal Data Protection Act, 2023 (DPDP Act) & IT Rules*

Medindia4u.com and Digital Share ("we", "our", or "us") are dedicated to safeguarding your personal data and respecting your privacy rights.

### 1. Categories of Personal Data Collected
- **Account Data:** Email address, password hash, full name, phone number, job title, company, bio, website, and profile image.
- **Business Card & Contact Data:** Photos of business cards captured by camera or imported from gallery, extracted names, phone numbers, email addresses, physical addresses, job titles, companies, and personal memory notes.
- **Calendar & Availability Data:** Working hours, scheduled meeting slots, timezone, and meeting requests.
- **Device & Technical Data:** Device OS, application version, secure storage identifiers, network status, and camera hardware authorization state.

### 2. Legal Grounds & Purposes of Processing
Under the DPDP Act, 2023, data is processed on the basis of your explicit consent and for specific lawful purposes:
- Enabling digital business card exchange and QR code generation.
- Optical Character Recognition (OCR) extraction from business card photos.
- Facilitating meeting scheduling between consenting professionals.
- Synchronizing your contacts across your authenticated devices.

### 3. Data Processing Architecture (Edge-First & Cloud AI)
- Image processing and OCR detection occur primarily on your local device (PaddleOCR / Google ML Kit).
- Cloud AI analysis (Google Gemini) is utilized solely for complex parsing and is governed by enterprise confidentiality agreements that strictly prohibit using your data to train public AI models.

### 4. Data Retention & Erasure
- Your data is retained only for as long as your account is active or as required by applicable laws.
- When you delete your account, your data is erased immediately from production databases.

### 5. Your Rights as a Data Principal under DPDP Act 2023
- **Right to Access:** Obtain a summary of personal data processed.
- **Right to Correction & Erasure:** Update inaccurate data or request deletion.
- **Right of Grievance Redressal:** Lodge complaints with our Grievance Officer.
- **Right to Nominate:** Nominate a representative in the event of death or incapacity.

### 6. Contact Information
For privacy inquiries or exercising your rights:
- **Email:** privacy@medindia4u.com
- **Organization:** Medindia4u.com Data Protection Office
""",
            CookiePolicyMarkdown = """
# Digital Share — Cookie & Local Storage Policy
*Essential Sessions & Preference Management*

Digital Share uses essential local tokens and storage mechanisms to provide a secure, seamless user experience.

### 1. Essential Authentication Tokens
- **JWT Access Tokens:** Short-lived security tokens used to authenticate API requests securely.
- **Rotating Refresh Tokens:** High-entropy hashed tokens stored in Android Keystore / iOS Keychain via Flutter Secure Storage to maintain authenticated sessions without re-entering credentials.
- These tokens are strictly necessary for core application functionality.

### 2. Local Database & Cache Storage
- **SQLite / Local Storage:** Used for offline-first business card storage, scan queues, and recent scans.
- **Appearance Preferences:** Light/Dark theme selection and completed tutorial state stored in local preferences.

### 3. Optional Analytics & Telemetry
- Optional performance and diagnostics analytics may be enabled or declined by the user.
- Declining optional analytics does not restrict access to any core features, business card scanning, or contact storage.
"""
        };
    }

    private static LegalDocumentResponse BuildEuDocuments()
    {
        return new LegalDocumentResponse
        {
            Jurisdiction = "EU",
            TermsVersion = CurrentTermsVersion,
            PrivacyPolicyVersion = CurrentPrivacyPolicyVersion,
            CookiePolicyVersion = CurrentCookiePolicyVersion,
            GrievanceOfficer = "EU Data Protection Officer, Medindia4u.com",
            ContactEmail = "privacy@medindia4u.com",
            TermsAndConditionsMarkdown = """
# Digital Share — Terms and Conditions (European Union)
*Version 2026.1 — In compliance with EU Law*

Welcome to Digital Share. By using our application, you agree to these Terms. Digital Share is provided by Medindia4u.com.

### 1. Use of Service
Digital Share provides digital business card management, OCR scanning, and professional meeting coordination. You agree to use the service in compliance with all applicable European and national regulations.

### 2. User Content & Intellectual Property
You retain ownership of the contact data and business cards you store. You grant us a limited license strictly necessary to store, synchronize, and display your data on your devices.

### 3. Termination & Account Deletion
You may delete your account at any time via My Profile > Delete Account. All personal data associated with your profile will be permanently deleted from our systems.
""",
            PrivacyPolicyMarkdown = """
# Digital Share — Privacy Policy (EU / GDPR)
*Compliance: Regulation (EU) 2016/679 (General Data Protection Regulation)*

### 1. Data Controller
Medindia4u.com acts as the Data Controller for your account information and Data Processor for contacts you store on your behalf.

### 2. Legal Basis for Processing (Article 6 GDPR)
- **Contractual Necessity (Art. 6(1)(b)):** Providing account authentication, digital business cards, and contact management.
- **Consent (Art. 6(1)(a)):** For optional telemetry and processing user-directed AI features.
- **Legitimate Interests (Art. 6(1)(f)):** Preventing fraud and securing platform integrity.

### 3. Data Subject Rights
Under Chapter III of GDPR, you have the right to:
- Access your personal data (Art. 15).
- Rectify inaccurate data (Art. 16).
- Erasure / Right to be forgotten (Art. 17).
- Restrict processing (Art. 18).
- Data portability (Art. 20).
- Object to processing (Art. 21).

### 4. International Data Transfers
Where data is transferred outside the European Economic Area (EEA), appropriate safeguards including Standard Contractual Clauses (SCCs) are implemented.
""",
            CookiePolicyMarkdown = """
# Digital Share — Cookie & Tracking Policy (ePrivacy / GDPR)

We respect your privacy. Digital Share utilizes only essential tokens for authentication and session management. Any optional analytics require your affirmative opt-in consent and can be revoked at any time.
"""
        };
    }

    private static LegalDocumentResponse BuildUkDocuments()
    {
        return new LegalDocumentResponse
        {
            Jurisdiction = "GB",
            TermsVersion = CurrentTermsVersion,
            PrivacyPolicyVersion = CurrentPrivacyPolicyVersion,
            CookiePolicyVersion = CurrentCookiePolicyVersion,
            GrievanceOfficer = "UK Data Protection Representative, Medindia4u.com",
            ContactEmail = "privacy@medindia4u.com",
            TermsAndConditionsMarkdown = """
# Digital Share — Terms and Conditions (United Kingdom)
*Version 2026.1 — UK Law & Consumer Rights*

These terms govern your use of the Digital Share mobile application and services in the United Kingdom, operated by Medindia4u.com.
""",
            PrivacyPolicyMarkdown = """
# Digital Share — Privacy Policy (United Kingdom)
*Compliance: UK GDPR and Data Protection Act 2018*

We comply with the UK General Data Protection Regulation (UK GDPR) and Data Protection Act 2018. UK Data subjects enjoy statutory rights including access, rectification, erasure, and lodging complaints with the Information Commissioner's Office (ICO).
""",
            CookiePolicyMarkdown = """
# Digital Share — Cookies & Local Storage (UK PECR)

In accordance with the Privacy and Electronic Communications Regulations (PECR), strictly necessary authentication tokens are stored securely to maintain your login session.
"""
        };
    }

    private static LegalDocumentResponse BuildUsDocuments()
    {
        return new LegalDocumentResponse
        {
            Jurisdiction = "US",
            TermsVersion = CurrentTermsVersion,
            PrivacyPolicyVersion = CurrentPrivacyPolicyVersion,
            CookiePolicyVersion = CurrentCookiePolicyVersion,
            GrievanceOfficer = "Privacy Officer, Medindia4u.com",
            ContactEmail = "privacy@medindia4u.com",
            TermsAndConditionsMarkdown = """
# Digital Share — Terms and Conditions (United States)
*Version 2026.1 — Powered by Medindia4u.com*

Please read these Terms carefully before using Digital Share. By accessing or using the platform, you agree to be bound by these terms.
""",
            PrivacyPolicyMarkdown = """
# Digital Share — Privacy Notice for US Residents
*Compliance: California Consumer Privacy Act (CCPA/CPRA) & State Privacy Laws*

### Notice at Collection
We collect personal information for account management, business card digitization, and contact exchange.

### We Do Not Sell or Share Personal Information
Digital Share does not sell your personal information or share it with third parties for cross-context behavioral advertising.

### Your Rights under CCPA/CPRA
- Right to know what personal information is collected.
- Right to delete personal information.
- Right to correct inaccurate personal information.
- Right to non-discrimination for exercising privacy rights.
""",
            CookiePolicyMarkdown = """
# Digital Share — Cookie & Storage Notice (United States)

Digital Share uses essential secure device storage and authorization tokens to provide you with secure account access.
"""
        };
    }

    private static LegalDocumentResponse BuildGlobalDocuments(string jurisdiction)
    {
        return new LegalDocumentResponse
        {
            Jurisdiction = jurisdiction,
            TermsVersion = CurrentTermsVersion,
            PrivacyPolicyVersion = CurrentPrivacyPolicyVersion,
            CookiePolicyVersion = CurrentCookiePolicyVersion,
            GrievanceOfficer = "Global Privacy Officer, Medindia4u.com",
            ContactEmail = "privacy@medindia4u.com",
            TermsAndConditionsMarkdown = """
# Digital Share — Global Terms and Conditions
*Version 2026.1 — Powered by Medindia4u.com*

Welcome to Digital Share. By using our application, you agree to these terms and conditions. Digital Share provides digital business card management, OCR scanning, and professional meeting coordination.
""",
            PrivacyPolicyMarkdown = """
# Digital Share — Global Privacy Policy
*International Data Protection Standard*

Medindia4u.com respects your privacy. We process personal data transparently, securely, and in accordance with international privacy principles. You retain full control over your contacts and may delete your account and personal data at any time.
""",
            CookiePolicyMarkdown = """
# Digital Share — Cookie & Local Storage Policy

Digital Share utilizes essential local tokens to maintain authenticated sessions securely. Optional analytics may be disabled without affecting core functionality.
"""
        };
    }
}

