using DigitalShare.Api.DTOs.CardAnalysis;
using DigitalShare.Api.Services.Gemini;
using Xunit;

namespace DigitalShare.Api.Tests.Services;

public class CardAnalysisSemanticValidatorTests
{
    private readonly CardAnalysisSemanticValidator _validator = new();

    [Fact]
    public void ValidateAndNormalize_RejectsYearRangeMistakenAsPhoneNumber()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_1",
            ScanContentHash = "hash_1",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "2025-2027", Engine = "PaddleOCR" },
                new() { Id = "obs_2", Text = "+1 555 123 4567", Engine = "PaddleOCR" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            PhoneNumbers = new List<ExtractedPhoneDto>
            {
                new() { Number = "2025-2027", SourceObservationIds = new() { "obs_1" } },
                new() { Number = "+1 555 123 4567", SourceObservationIds = new() { "obs_2" } }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.Single(result.PhoneNumbers);
        Assert.Equal("+1 555 123 4567", result.PhoneNumbers[0].Number);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("2025-2027"));
    }

    [Fact]
    public void ValidateAndNormalize_FlagsIrregularPhoneDigitCount()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_2",
            ScanContentHash = "hash_2",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "12345", Engine = "Google ML Kit" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            PhoneNumbers = new List<ExtractedPhoneDto>
            {
                new() { Number = "12345", SourceObservationIds = new() { "obs_1" } }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.Single(result.PhoneNumbers);
        Assert.True(result.PhoneNumbers[0].ReviewRequired);
        Assert.True(result.RequiresManualReview);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("irregular digit count"));
    }

    [Fact]
    public void ValidateAndNormalize_DeduplicatesExactEmailsCaseInsensitively()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_3",
            ScanContentHash = "hash_3",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "contact@digitalshare.app", Engine = "PaddleOCR" },
                new() { Id = "obs_2", Text = "CONTACT@DIGITALSHARE.APP", Engine = "Google ML Kit" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            EmailAddresses = new List<ExtractedEmailDto>
            {
                new() { Email = "contact@digitalshare.app", SourceObservationIds = new() { "obs_1" } },
                new() { Email = "CONTACT@DIGITALSHARE.APP", SourceObservationIds = new() { "obs_2" } }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.Single(result.EmailAddresses);
        Assert.Equal("contact@digitalshare.app", result.EmailAddresses[0].NormalizedEmail);
    }

    [Fact]
    public void ValidateAndNormalize_NonDestructivelyFlagsAddressContaminatedWithName()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_4",
            ScanContentHash = "hash_4",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Alice Walker", Engine = "PaddleOCR" },
                new() { Id = "obs_2", Text = "Alice Walker 123 Tech Blvd, Suite 400", Engine = "PaddleOCR" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            FullName = new ExtractedFieldDto { Value = "Alice Walker", SourceObservationIds = new() { "obs_1" } },
            Address = new ExtractedAddressDto
            {
                FullAddress = "Alice Walker 123 Tech Blvd, Suite 400",
                SourceObservationIds = new() { "obs_2" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        // Crucial requirement: Do NOT delete address, mark ReviewRequired non-destructively
        Assert.NotNull(result.Address.FullAddress);
        Assert.True(result.Address.ReviewRequired);
        Assert.True(result.RequiresManualReview);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("Alice Walker"));
    }

    [Fact]
    public void ValidateAndNormalize_FlagsUngroundedFieldWhenObservationIdMissing()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_5",
            ScanContentHash = "hash_5",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_real", Text = "Jane Doe", Engine = "PaddleOCR" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            FullName = new ExtractedFieldDto
            {
                Value = "Hallucinated Company",
                SourceObservationIds = new() { "obs_non_existent" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.True(result.FullName.ReviewRequired);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("ungrounded"));
    }

    [Fact]
    public void ValidateAndNormalize_FlagsCorporateSuffixAssignedToPersonName_Rule2()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_6",
            ScanContentHash = "hash_6",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Apex Healthcare Services", Engine = "PaddleOCR" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            FullName = new ExtractedFieldDto
            {
                Value = "Apex Healthcare Services",
                Confidence = 0.95,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.True(result.FullName.ReviewRequired);
        Assert.True(result.RequiresManualReview);
        Assert.True(result.FullName.Confidence <= 0.30);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("Rule 2 violation"));
    }

    [Fact]
    public void ValidateAndNormalize_FlagsDesignationAssignedToCompany_Rule3()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_7",
            ScanContentHash = "hash_7",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Head of Client Services", Engine = "PaddleOCR" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            Company = new ExtractedFieldDto
            {
                Value = "Head of Client Services",
                Confidence = 0.90,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.True(result.Company.ReviewRequired);
        Assert.True(result.RequiresManualReview);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("Rule 3 violation"));
    }

    [Fact]
    public void ValidateAndNormalize_FlagsAddressAssignedToCompany_Rule4()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_8",
            ScanContentHash = "hash_8",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "123 Tech Park Road, Suite 400", Engine = "PaddleOCR" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            Company = new ExtractedFieldDto
            {
                Value = "123 Tech Park Road, Suite 400",
                Confidence = 0.88,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.True(result.Company.ReviewRequired);
        Assert.True(result.RequiresManualReview);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("Rule 4 violation"));
    }

    [Fact]
    public void ValidateAndNormalize_RejectsCrossSideObservationReference()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_cross_side",
            ScanContentHash = "hash_cross_side",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_front_1", Text = "Front Text", Engine = "PaddleOCR", CardSide = "front" },
                new() { Id = "obs_back_1", Text = "Back Text", Engine = "Google ML Kit", CardSide = "back" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            FullName = new ExtractedFieldDto
            {
                Value = "Back Text",
                Confidence = 0.92,
                SupportingCardSide = "front",
                SourceObservationIds = new() { "obs_back_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.True(result.FullName.ReviewRequired);
        Assert.True(result.RequiresManualReview);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("Cross-side reference violation"));
    }

    [Fact]
    public void ValidateAndNormalize_RejectsUnsupportedCorrection_RevertsToLocalCandidate()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_unsupported_corr",
            ScanContentHash = "hash_unsupported_corr",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Acme Corp", Engine = "PaddleOCR", CardSide = "front" }
            },
            LocalBaseline = new LocalParserBaselineDto
            {
                FullName = "Alexander Wright",
                Company = "Acme Corp"
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            FullName = new ExtractedFieldDto
            {
                Value = "Hallucinated Person Name",
                OriginalLocalParserValue = "Alexander Wright",
                Confidence = 0.95,
                WasCorrected = true,
                SourceObservationIds = new() { "non_existent_obs" } // Not grounded
            },
            Company = new ExtractedFieldDto
            {
                Value = "Acme Corp",
                Confidence = 0.95,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        // Individual field correction is rejected and reverted to local candidate
        Assert.Equal("Alexander Wright", result.FullName.Value);
        Assert.False(result.FullName.WasCorrected);
        Assert.True(result.FullName.ReviewRequired);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("Unsupported correction for FullName"));
        // Other fields remain valid
        Assert.Equal("Acme Corp", result.Company.Value);
    }

    [Fact]
    public void ValidateAndNormalize_ProtectsUserApprovedValue()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_user_prot",
            ScanContentHash = "hash_user_prot",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Misread Name", Engine = "PaddleOCR", CardSide = "front" }
            },
            LocalFieldEvidence = new Dictionary<string, FieldEvidenceDto>
            {
                ["fullName"] = new FieldEvidenceDto
                {
                    FieldName = "fullName",
                    OriginalOcrText = "Misread Name",
                    NormalizedValue = "Misread Name",
                    UserApprovedValue = "Confirmed Alice Cooper",
                    VerificationStatus = "verified",
                    VerificationSource = "userManualEdit"
                }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            FullName = new ExtractedFieldDto
            {
                Value = "AI Overwrite Name",
                Confidence = 0.99,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.Equal("Confirmed Alice Cooper", result.FullName.Value);
        Assert.False(result.FullName.WasCorrected);
        Assert.False(result.FullName.ReviewRequired);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("Protected user-approved value for FullName"));
    }

    [Fact]
    public void ValidateAndNormalize_EnforcesVisualVerificationPrerequisite()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_vis_prereq",
            ScanContentHash = "hash_vis_prereq",
            AnalysisMode = "TextAndLayout",
            OcrObservations = new List<OcrObservationDto>
            {
                new() { Id = "obs_1", Text = "Dr. John Smith", Engine = "PaddleOCR", CardSide = "front" }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            VisualVerificationPerformed = false,
            FullName = new ExtractedFieldDto
            {
                Value = "Dr. John Smith",
                Confidence = 0.95,
                VerificationStatus = "verified", // Falsely claimed verified without visual check
                IsVisuallyVerified = true,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.False(result.FullName.IsVisuallyVerified);
        Assert.Equal("probable", result.FullName.VerificationStatus);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("visual verification was not performed"));
    }

    [Fact]
    public void ValidateAndNormalize_FlagsInvalidBoundingBox()
    {
        var request = new AnalyzeBusinessCardRequest
        {
            ClientRequestId = "req_bad_box",
            ScanContentHash = "hash_bad_box",
            OcrObservations = new List<OcrObservationDto>
            {
                new()
                {
                    Id = "obs_1",
                    Text = "John Doe",
                    Engine = "PaddleOCR",
                    CardSide = "front",
                    BoundingBox = new NormalizedBoundingBoxDto { Top = -0.5, Left = 0.1, Bottom = 1.5, Right = 0.5 }
                }
            }
        };

        var response = new AnalyzeBusinessCardResponse
        {
            FullName = new ExtractedFieldDto
            {
                Value = "John Doe",
                Confidence = 0.95,
                SourceObservationIds = new() { "obs_1" }
            }
        };

        var result = _validator.ValidateAndNormalize(response, request);

        Assert.True(result.FullName.ReviewRequired);
        Assert.Contains(result.ReviewWarnings, w => w.Contains("out-of-bounds normalized bounding box"));
    }
}

