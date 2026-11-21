using System.ComponentModel.DataAnnotations;
using System.Text.RegularExpressions;
using DigitalShare.Api.DTOs.CardAnalysis;

namespace DigitalShare.Api.Services.Gemini;

/// <summary>
/// Evidence-based non-destructive semantic validator for Gemini business card interpretations.
/// Enforces syntax rules, checks source observation grounding, flags suspicious overlaps,
/// and never silently discards recognized text.
/// </summary>
public class CardAnalysisSemanticValidator
{
    private static readonly Regex YearRangeRegex = new(
        @"\b(?:19|20)\d{2}\s*[-–/]\s*(?:19|20)?\d{2}\b",
        RegexOptions.Compiled);

    private static readonly Regex RegistrationOrTaxIdRegex = new(
        @"\b(?:GSTIN|CIN|PAN|REG(?:\.|\s*NO)?|IEC|TIN|MSME)\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex CorporateEntitySuffixRegex = new(
        @"\b(?:pvt\.?\s*ltd\.?|private\s+limited|ltd\.?|limited|llc|llp|inc\.?|corp\.?|corporation|gmbh|healthcare|technologies|technology|solutions|services|enterprises|consulting|consultancy|industries|foundation|hospital|hospitals|clinic|clinics|university|college|school|institute|chambers|bank|group|holdings|associates|partners|realty|media|digital|ventures|capital|logistics|systems|labs|interactive|dynamics|innovations|design|designs|studios|agency)\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex HonorificPrefixRegex = new(
        @"^(?:Dr\.|Dr|Prof\.|Prof|Mr\.|Mr|Mrs\.|Mrs|Ms\.|Ms|Adv\.|Adv|Er\.|Er|CA|Rtn\.|Rtn|Shri|Smt)\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex StrictLegalOrgSuffixRegex = new(
        @"\b(?:pvt\.?\s*ltd\.?|private\s+limited|ltd\.?|limited|llc|llp|inc\.?|corp\.?|corporation|gmbh)\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex JobTitleRoleRegex = new(
        @"\b(?:head\s+of|director\s+of|vice\s+president|managing\s+director|chief\s+executive|engineer|developer|consultant|manager|director|officer|specialist|analyst|coordinator|architect|advocate|partner|founder|co-founder|cbo|proprietor|president|chairperson|ceo|cto|cfo|coo|vp)\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex AddressLineIndicatorsRegex = new(
        @"\b(?:street|st\b|road|rd\b|avenue|ave\b|boulevard|blvd\b|lane|drive|dr\b|floor|suite|ste\b|block|building|bldg\b|nagar|colony|sector|cross|main|post|po\s*box|zip|pin(?:\s*code)?|\d{5,6})\b",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private readonly EmailAddressAttribute _emailValidator = new();

    /// <summary>
    /// Validates and normalizes the parsed response from Gemini against input OCR observations.
    /// </summary>
    public AnalyzeBusinessCardResponse ValidateAndNormalize(
        AnalyzeBusinessCardResponse rawResponse,
        AnalyzeBusinessCardRequest originalRequest)
    {
        var validated = rawResponse;
        var warnings = new List<string>(rawResponse.ReviewWarnings);
        var inputObservationMap = originalRequest.OcrObservations
            .ToDictionary(o => o.Id, o => o, StringComparer.OrdinalIgnoreCase);

        // 1. Validate FullName (Enforce Rule 2: Never assign company to personal name; Rule 7: Confidence check)
        ValidateField(
            validated.FullName,
            fieldName: "FullName",
            inputObservationMap,
            warnings,
            originalRequest,
            validated.VisualVerificationPerformed,
            minLength: 2,
            maxLength: 100);

        if (!string.IsNullOrWhiteSpace(validated.FullName.Value))
        {
            var fnValue = validated.FullName.Value;

            // Rule 2: Company in FullName — if the FullName field contains corporate entity suffixes
            // (e.g. LLP, Ltd, Inc, Corp, Healthcare, Technologies, Systems, Solutions, Enterprises, etc.),
            // it is an organization or company name, NEVER a person name. Demote to review.
            if (CorporateEntitySuffixRegex.IsMatch(fnValue))
            {
                validated.FullName.ReviewRequired = true;
                validated.FullName.Confidence = Math.Min(validated.FullName.Confidence, 0.30);
                warnings.Add($"Rule 2 violation: FullName '{fnValue}' contains corporate or organizational entity suffixes. Demoted to review.");
            }
            else if (JobTitleRoleRegex.IsMatch(fnValue))
            {
                // If it is purely a job title (e.g. "Managing Director", "Partner", "Chairperson")
                // without any personal name part or honorific, demote it.
                var hasNameBeforeRole = Regex.IsMatch(fnValue, @"^[A-Z][a-z]+\s+[A-Z]", RegexOptions.None) ||
                                        fnValue.Contains(',') ||
                                        HonorificPrefixRegex.IsMatch(fnValue) ||
                                        Regex.IsMatch(fnValue, @"\b(?:Rtn\.|Rtn|Retd\.?|Col\.?|Maj\.?|Gen\.?|F\.C\.A\.?|FCA|M\.B\.A\.?|Ph\.D\.?)\b", RegexOptions.IgnoreCase);
                if (!hasNameBeforeRole)
                {
                    validated.FullName.ReviewRequired = true;
                    validated.FullName.Confidence = Math.Min(validated.FullName.Confidence, 0.30);
                    warnings.Add($"FullName '{fnValue}' appears to be a job title with no personal name component.");
                }
            }
        }

        // 2. Validate Company (Enforce Rule 3: Never assign designation to company; Rule 4: Never assign address to company)
        ValidateField(
            validated.Company,
            fieldName: "Company",
            inputObservationMap,
            warnings,
            originalRequest,
            validated.VisualVerificationPerformed,
            minLength: 2,
            maxLength: 100);

        if (!string.IsNullOrWhiteSpace(validated.Company.Value))
        {
            if (HonorificPrefixRegex.IsMatch(validated.Company.Value))
            {
                validated.Company.ReviewRequired = true;
                validated.Company.Confidence = Math.Min(validated.Company.Confidence, 0.25);
                warnings.Add($"Rule 3 violation: Company '{validated.Company.Value}' begins with a personal honorific title. Suspected person name.");
            }
            else if (JobTitleRoleRegex.IsMatch(validated.Company.Value) && !StrictLegalOrgSuffixRegex.IsMatch(validated.Company.Value))
            {
                validated.Company.ReviewRequired = true;
                validated.Company.Confidence = Math.Min(validated.Company.Confidence, 0.30);
                warnings.Add($"Rule 3 violation: Company '{validated.Company.Value}' appears to be a job title or occupational role. Demoted to review.");
            }
            else if (AddressLineIndicatorsRegex.IsMatch(validated.Company.Value) && !StrictLegalOrgSuffixRegex.IsMatch(validated.Company.Value))
            {
                validated.Company.ReviewRequired = true;
                validated.Company.Confidence = Math.Min(validated.Company.Confidence, 0.30);
                warnings.Add($"Rule 4 violation: Company '{validated.Company.Value}' appears to be an address line. Demoted to review.");
            }
        }

        // 3. Validate JobTitle
        ValidateField(
            validated.JobTitle,
            fieldName: "JobTitle",
            inputObservationMap,
            warnings,
            originalRequest,
            validated.VisualVerificationPerformed,
            minLength: 2,
            maxLength: 100);

        if (!string.IsNullOrWhiteSpace(validated.JobTitle.Value) &&
            StrictLegalOrgSuffixRegex.IsMatch(validated.JobTitle.Value))
        {
            validated.JobTitle.ReviewRequired = true;
            warnings.Add($"JobTitle '{validated.JobTitle.Value}' contains strict corporate suffix.");
        }

        // 4. Validate Phone Numbers
        var sanitizedPhones = new List<ExtractedPhoneDto>();
        foreach (var phone in validated.PhoneNumbers)
        {
            if (string.IsNullOrWhiteSpace(phone.Number)) continue;

            // Reject tenure ranges e.g. "2025-2027" mistakenly parsed as phone
            if (YearRangeRegex.IsMatch(phone.Number) || RegistrationOrTaxIdRegex.IsMatch(phone.Number))
            {
                warnings.Add($"Rejected numeric identifier or year range '{phone.Number}' from phone numbers.");
                continue;
            }

            var digitsOnly = Regex.Replace(phone.Number, @"\D", "");
            if (digitsOnly.Length < 7 || digitsOnly.Length > 15)
            {
                phone.ReviewRequired = true;
                warnings.Add($"Phone number '{phone.Number}' has irregular digit count ({digitsOnly.Length}). Marked for review.");
            }

            phone.NormalizedNumber = ContactNormalizationHelper.NormalizePhone(phone.Number);
            if (!VerifyObservationGrounding(phone.SourceObservationIds, inputObservationMap, "Phone", warnings, phone.SupportingCardSide, phone.IsVisuallyVerified))
            {
                phone.ReviewRequired = true;
            }

            if (!validated.VisualVerificationPerformed)
            {
                phone.IsVisuallyVerified = false;
                if (phone.VerificationStatus == "verified")
                {
                    phone.VerificationStatus = "probable";
                }
            }

            sanitizedPhones.Add(phone);
        }
        validated.PhoneNumbers = sanitizedPhones;

        // 5. Validate Email Addresses
        var sanitizedEmails = new List<ExtractedEmailDto>();
        var seenEmails = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var email in validated.EmailAddresses)
        {
            if (string.IsNullOrWhiteSpace(email.Email)) continue;

            var trimmedEmail = email.Email.Trim().ToLowerInvariant();
            if (!_emailValidator.IsValid(trimmedEmail) || !trimmedEmail.Contains('.') || !trimmedEmail.Contains('@'))
            {
                email.ReviewRequired = true;
                warnings.Add($"Email '{email.Email}' does not conform to RFC email format. Marked for review.");
            }

            var norm = ContactNormalizationHelper.NormalizeEmail(trimmedEmail);
            if (!seenEmails.Add(norm))
            {
                // Drop exact duplicate email
                continue;
            }

            email.NormalizedEmail = norm;
            if (!VerifyObservationGrounding(email.SourceObservationIds, inputObservationMap, "Email", warnings, email.SupportingCardSide, email.IsVisuallyVerified))
            {
                email.ReviewRequired = true;
            }

            if (!validated.VisualVerificationPerformed)
            {
                email.IsVisuallyVerified = false;
                if (email.VerificationStatus == "verified")
                {
                    email.VerificationStatus = "probable";
                }
            }

            sanitizedEmails.Add(email);
        }
        validated.EmailAddresses = sanitizedEmails;

        // 6. Validate Websites
        var sanitizedWebsites = new List<ExtractedWebsiteDto>();
        var seenWebsites = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var site in validated.Websites)
        {
            if (string.IsNullOrWhiteSpace(site.Url)) continue;

            var trimmed = site.Url.Trim().TrimEnd(',', '.', ';', ':');
            if (seenWebsites.Add(trimmed.ToLowerInvariant()))
            {
                site.Url = trimmed;
                if (!VerifyObservationGrounding(site.SourceObservationIds, inputObservationMap, "Website", warnings, site.SupportingCardSide, site.IsVisuallyVerified))
                {
                    warnings.Add($"Website '{trimmed}' has ungrounded observations.");
                }

                if (!validated.VisualVerificationPerformed)
                {
                    site.IsVisuallyVerified = false;
                    if (site.VerificationStatus == "verified")
                    {
                        site.VerificationStatus = "probable";
                    }
                }

                sanitizedWebsites.Add(site);
            }
        }
        validated.Websites = sanitizedWebsites;

        // 7. Non-Destructive Address Validation
        if (!string.IsNullOrWhiteSpace(validated.Address.FullAddress))
        {
            var addr = validated.Address.FullAddress.Trim();
            validated.Address.FullAddress = addr;

            // Check user-approved protection for address
            if (originalRequest.LocalFieldEvidence != null &&
                (originalRequest.LocalFieldEvidence.TryGetValue("address", out var addrEv) ||
                 originalRequest.LocalFieldEvidence.TryGetValue("Address", out addrEv)) &&
                !string.IsNullOrWhiteSpace(addrEv.UserApprovedValue))
            {
                validated.Address.FullAddress = addrEv.UserApprovedValue;
                validated.Address.ProposedValue = addrEv.UserApprovedValue;
                validated.Address.WasCorrected = false;
                validated.Address.ReviewRequired = false;
                warnings.Add($"Protected user-approved value for Address ('{addrEv.UserApprovedValue}') against AI override.");
            }

            // Check if address appears contaminated with person name or company name
            if (!string.IsNullOrWhiteSpace(validated.FullName.Value) &&
                validated.FullName.Value.Length > 3 &&
                addr.Contains(validated.FullName.Value, StringComparison.OrdinalIgnoreCase))
            {
                validated.Address.ReviewRequired = true;
                warnings.Add($"Address contains person's name '{validated.FullName.Value}'. User verification recommended.");
            }

            if (!string.IsNullOrWhiteSpace(validated.Company.Value) &&
                validated.Company.Value.Length > 3 &&
                addr.Contains(validated.Company.Value, StringComparison.OrdinalIgnoreCase))
            {
                validated.Address.ReviewRequired = true;
                warnings.Add($"Address contains company name '{validated.Company.Value}'. User verification recommended.");
            }

            if (!VerifyObservationGrounding(validated.Address.SourceObservationIds, inputObservationMap, "Address", warnings, validated.Address.SupportingCardSide, validated.Address.IsVisuallyVerified))
            {
                validated.Address.ReviewRequired = true;
            }

            if (!validated.VisualVerificationPerformed)
            {
                validated.Address.IsVisuallyVerified = false;
                if (validated.Address.VerificationStatus == "verified")
                {
                    validated.Address.VerificationStatus = "probable";
                }
            }
        }

        // 8. Overall Confidence & Review Gating
        validated.ReviewWarnings = warnings.Distinct().ToList();
        var requiresReview = validated.RequiresManualReview ||
                             validated.ReviewWarnings.Any() ||
                             validated.FullName.ReviewRequired ||
                             validated.Company.ReviewRequired ||
                             validated.JobTitle.ReviewRequired ||
                             validated.Address.ReviewRequired ||
                             validated.PhoneNumbers.Any(p => p.ReviewRequired) ||
                             validated.EmailAddresses.Any(e => e.ReviewRequired) ||
                             validated.OverallConfidence < 0.75;

        validated.RequiresManualReview = requiresReview;

        // Synchronize FieldVerifications dictionary with validated entities
        SyncFieldVerifications(validated);

        return validated;
    }

    private void ValidateField(
        ExtractedFieldDto field,
        string fieldName,
        Dictionary<string, OcrObservationDto> observationMap,
        List<string> warnings,
        AnalyzeBusinessCardRequest originalRequest,
        bool visualVerificationPerformed,
        int minLength,
        int maxLength)
    {
        if (!visualVerificationPerformed)
        {
            field.IsVisuallyVerified = false;
            if (field.VerificationStatus == "verified")
            {
                field.VerificationStatus = "probable";
                warnings.Add($"Field {fieldName} was marked verified but visual verification was not performed. Downgraded.");
            }
        }

        // 1. User-approved value protection: User manual edits are 100% authoritative
        if (originalRequest.LocalFieldEvidence != null)
        {
            var matchKey = originalRequest.LocalFieldEvidence.Keys
                .FirstOrDefault(k => string.Equals(k, fieldName, StringComparison.OrdinalIgnoreCase));

            if (matchKey != null &&
                originalRequest.LocalFieldEvidence.TryGetValue(matchKey, out var userEv) &&
                !string.IsNullOrWhiteSpace(userEv.UserApprovedValue))
            {
                field.Value = userEv.UserApprovedValue;
                field.ProposedValue = userEv.UserApprovedValue;
                field.WasCorrected = false;
                field.ReviewRequired = false;
                field.Confidence = 1.0;
                field.VerificationStatus = "verified";
                warnings.Add($"Protected user-approved value for {fieldName} ('{userEv.UserApprovedValue}') against AI override.");
                return;
            }
        }

        if (string.IsNullOrWhiteSpace(field.Value))
        {
            field.Value = null;
            field.VerificationStatus = "notFound";
            return;
        }

        var trimmed = field.Value.Trim();
        if (trimmed.Length < minLength || trimmed.Length > maxLength)
        {
            field.ReviewRequired = true;
            warnings.Add($"{fieldName} length ({trimmed.Length}) is outside expected range ({minLength}-{maxLength}).");
        }

        field.Value = trimmed;

        // Grounding check with cross-side reference and coordinate boundaries validation
        var isGrounded = VerifyObservationGrounding(field.SourceObservationIds, observationMap, fieldName, warnings, field.SupportingCardSide, field.IsVisuallyVerified);
        if (!isGrounded)
        {
            field.ReviewRequired = true;

            // KEY FIX: If this field was read directly from the image (visual verification),
            // the image is the ground truth — do NOT revert to local baseline.
            // Local OCR may simply have missed this text; that is not a reason to discard it.
            if (field.IsVisuallyVerified)
            {
                warnings.Add($"{fieldName} extracted visually from image but lacks matching OCR observation ID. Retained visual value '{field.Value}' and marked for review.");
                // Keep field.Value as-is; just mark for review so the user can confirm.
            }
            else
            {
                // If Gemini proposed a correction but it lacks grounding, reject the correction for this field
                var localBaselineVal = field.OriginalLocalParserValue ?? GetLocalBaselineValue(originalRequest, fieldName);
                if (field.WasCorrected || (!string.IsNullOrEmpty(localBaselineVal) && !string.Equals(field.Value, localBaselineVal, StringComparison.Ordinal)))
                {
                    warnings.Add($"Unsupported correction for {fieldName} ('{field.Value}') was rejected due to ungrounded observations; reverted to local candidate '{localBaselineVal}'.");
                    field.Value = localBaselineVal;
                    field.WasCorrected = false;
                }
            }
        }

        // Check if value was modified from raw evidence
        if (!string.IsNullOrWhiteSpace(field.RawEvidence) &&
            !string.Equals(field.Value, field.RawEvidence.Trim(), StringComparison.Ordinal))
        {
            field.WasCorrected = true;
        }

        // Visual verification enforcement
        if (field.IsGenuinelyReadable == false)
        {
            field.ReviewRequired = true;
            field.Confidence = Math.Min(field.Confidence, 0.45);
            warnings.Add($"Field {fieldName} was flagged as unreadable in visual evidence.");
        }
    }

    private bool VerifyObservationGrounding(
        List<string> sourceObservationIds,
        Dictionary<string, OcrObservationDto> observationMap,
        string fieldName,
        List<string> warnings,
        string? supportingCardSide = null,
        bool isVisuallyVerified = false)
    {
        // KEY FIX: When visual verification was performed and the field is visually verified,
        // Gemini read the value directly from image pixels. It may not have a matching OCR
        // observation ID (because on-device OCR may have missed this text entirely).
        // In this case, skip the grounding check — the image IS the ground truth.
        if (isVisuallyVerified && sourceObservationIds.Count == 0)
        {
            return true; // Visually grounded in image pixels, no OCR observation needed
        }

        if (sourceObservationIds.Count == 0)
        {
            warnings.Add($"{fieldName} has no linked source observation IDs from OCR.");
            return false;
        }

        var allGrounded = true;
        var targetSide = supportingCardSide?.Trim().ToLowerInvariant();

        foreach (var id in sourceObservationIds)
        {
            if (!observationMap.TryGetValue(id, out var obs))
            {
                // If visually verified, an unmatched observation ID is a warning not a rejection
                if (isVisuallyVerified)
                {
                    warnings.Add($"{fieldName} references observation ID '{id}' not found in OCR map, but field is visually verified from image — accepted.");
                    continue; // Don't fail grounding for visually verified fields
                }
                warnings.Add($"{fieldName} references ungrounded observation ID '{id}'.");
                allGrounded = false;
                continue;
            }

            // Cross-side reference validation
            if (!string.IsNullOrEmpty(targetSide) && targetSide != "both" && targetSide != "none")
            {
                var obsSide = obs.CardSide?.Trim().ToLowerInvariant();
                if (!string.IsNullOrEmpty(obsSide) && obsSide != targetSide)
                {
                    warnings.Add($"Cross-side reference violation: {fieldName} declared on {targetSide} references observation '{id}' from opposite side '{obsSide}'.");
                    allGrounded = false;
                }
            }

            // Coordinate boundary check [0.0, 1.0]
            var b = obs.BoundingBox;
            if (b != null)
            {
                if (b.Top < 0.0 || b.Top > 1.0 || b.Bottom < 0.0 || b.Bottom > 1.0 ||
                    b.Left < 0.0 || b.Left > 1.0 || b.Right < 0.0 || b.Right > 1.0 ||
                    b.Top > b.Bottom || b.Left > b.Right)
                {
                    warnings.Add($"Observation '{id}' referenced by {fieldName} has invalid or out-of-bounds normalized bounding box [{b.Top:F2}, {b.Left:F2}, {b.Bottom:F2}, {b.Right:F2}].");
                    allGrounded = false;
                }
            }
        }
        return allGrounded;
    }

    private static string? GetLocalBaselineValue(AnalyzeBusinessCardRequest request, string fieldName)
    {
        var baseline = request.LocalBaseline;
        if (baseline == null) return null;
        return fieldName.ToLowerInvariant() switch
        {
            "fullname" => baseline.FullName,
            "company" => baseline.Company,
            "jobtitle" => baseline.JobTitle,
            "address" => baseline.Address,
            "website" => baseline.Website,
            _ => null
        };
    }

    private static void SyncFieldVerifications(AnalyzeBusinessCardResponse response)
    {
        if (response.FieldVerifications == null) return;

        void UpdateVer(string name, ExtractedFieldDto field)
        {
            if (response.FieldVerifications.TryGetValue(name, out var dto))
            {
                dto.ProposedValue = field.ProposedValue ?? field.Value;
                dto.Confidence = field.Confidence;
                dto.ReviewRequired = field.ReviewRequired;
                dto.WasCorrected = field.WasCorrected;
                dto.VerificationStatus = field.VerificationStatus ?? (field.ReviewRequired ? "reviewRequired" : "probable");
                dto.IsVisuallyVerified = response.VisualVerificationPerformed && field.IsVisuallyVerified;
            }
        }

        UpdateVer("fullName", response.FullName);
        UpdateVer("company", response.Company);
        UpdateVer("jobTitle", response.JobTitle);

        if (response.Address != null && response.FieldVerifications.TryGetValue("address", out var addrDto))
        {
            addrDto.ProposedValue = response.Address.ProposedValue ?? response.Address.FullAddress;
            addrDto.Confidence = response.Address.Confidence;
            addrDto.ReviewRequired = response.Address.ReviewRequired;
            addrDto.WasCorrected = response.Address.WasCorrected;
            addrDto.VerificationStatus = response.Address.VerificationStatus ?? (response.Address.ReviewRequired ? "reviewRequired" : "probable");
            addrDto.IsVisuallyVerified = response.VisualVerificationPerformed && response.Address.IsVisuallyVerified;
        }
    }
}

