using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Availability;
using DigitalShare.Api.DTOs.Connections;
using DigitalShare.Api.DTOs.Profile;
using DigitalShare.Api.Tests.Helpers;

namespace DigitalShare.Api.Tests.Controllers;

public class AvailabilityControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public AvailabilityControllerTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    private async Task<(AuthResponse Auth, ProfileResponse Profile)> RegisterAndGetProfileAsync(string email)
    {
        var registerRequest = new RegisterRequest
        {
            Email = email,
            Password = "Password123!",
            ConfirmPassword = "Password123!"
        };

        var regResponse = await _client.PostAsJsonAsync("/api/auth/register", registerRequest);
        regResponse.EnsureSuccessStatusCode();
        var auth = await regResponse.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);

        var profileRequest = new HttpRequestMessage(HttpMethod.Get, "/api/profile/me");
        profileRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var profileResponse = await _client.SendAsync(profileRequest);
        profileResponse.EnsureSuccessStatusCode();

        var profile = await profileResponse.Content.ReadFromJsonAsync<ProfileResponse>();
        Assert.NotNull(profile);
        return (auth, profile);
    }

    [Fact]
    public async Task Test01_GetOwnAvailability_WhenNewUser_ReturnsDefaultSettings()
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"avail_new_{Guid.NewGuid()}@example.com");

        var request = new HttpRequestMessage(HttpMethod.Get, "/api/availability/me");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var availability = await response.Content.ReadFromJsonAsync<AvailabilityResponse>();
        Assert.NotNull(availability);
        Assert.True(availability.MeetingRequestsEnabled);
        Assert.Equal("UTC", availability.TimeZoneId);
        Assert.Empty(availability.Slots);
    }

    [Fact]
    public async Task Test02_03_04_SaveAvailability_WithMultipleSlotsAndWeekdays_SavesSuccessfully()
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"avail_save_{Guid.NewGuid()}@example.com");

        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = true,
            TimeZoneId = "Asia/Kolkata",
            Slots = new List<AvailabilitySlotDto>
            {
                new() { DayOfWeek = DayOfWeek.Monday, StartTime = "09:00", EndTime = "12:00" },
                new() { DayOfWeek = DayOfWeek.Monday, StartTime = "14:00", EndTime = "17:00" },
                new() { DayOfWeek = DayOfWeek.Tuesday, StartTime = "10:00", EndTime = "16:00" }
            }
        };

        var putRequest = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(putRequest);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<AvailabilityResponse>();
        Assert.NotNull(result);
        Assert.True(result.MeetingRequestsEnabled);
        Assert.Equal("Asia/Kolkata", result.TimeZoneId);
        Assert.Equal(3, result.Slots.Count);

        // Verify Monday has 2 slots
        var mondaySlots = result.Slots.Where(s => s.DayOfWeek == DayOfWeek.Monday).ToList();
        Assert.Equal(2, mondaySlots.Count);
        Assert.Equal("09:00", mondaySlots[0].StartTime);
        Assert.Equal("12:00", mondaySlots[0].EndTime);
        Assert.Equal("14:00", mondaySlots[1].StartTime);
        Assert.Equal("17:00", mondaySlots[1].EndTime);
    }

    [Fact]
    public async Task Test05_RejectOverlappingSlots_OnSameWeekday_ReturnsBadRequest()
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"avail_overlap_{Guid.NewGuid()}@example.com");

        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = true,
            TimeZoneId = "UTC",
            Slots = new List<AvailabilitySlotDto>
            {
                new() { DayOfWeek = DayOfWeek.Monday, StartTime = "09:00", EndTime = "13:00" },
                new() { DayOfWeek = DayOfWeek.Monday, StartTime = "12:00", EndTime = "16:00" }
            }
        };

        var putRequest = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(putRequest);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Test06_AllowAdjacentSlots_OnSameWeekday_SavesSuccessfully()
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"avail_adj_{Guid.NewGuid()}@example.com");

        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = true,
            TimeZoneId = "UTC",
            Slots = new List<AvailabilitySlotDto>
            {
                new() { DayOfWeek = DayOfWeek.Monday, StartTime = "09:00", EndTime = "12:00" },
                new() { DayOfWeek = DayOfWeek.Monday, StartTime = "12:00", EndTime = "15:00" }
            }
        };

        var putRequest = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(putRequest);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<AvailabilityResponse>();
        Assert.NotNull(result);
        Assert.Equal(2, result.Slots.Count);
    }

    [Fact]
    public async Task Test07_StartBeforeEndValidation_WhenStartTimeNotBeforeEndTime_ReturnsBadRequest()
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"avail_inv_{Guid.NewGuid()}@example.com");

        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = true,
            TimeZoneId = "UTC",
            Slots = new List<AvailabilitySlotDto>
            {
                new() { DayOfWeek = DayOfWeek.Wednesday, StartTime = "17:00", EndTime = "09:00" }
            }
        };

        var putRequest = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(putRequest);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Test08_MeetingRequestsEnableDisable_PersistsToggleState()
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"avail_toggle_{Guid.NewGuid()}@example.com");

        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = false,
            TimeZoneId = "America/New_York",
            Slots = new List<AvailabilitySlotDto>()
        };

        var putRequest = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var putResponse = await _client.SendAsync(putRequest);
        Assert.Equal(HttpStatusCode.OK, putResponse.StatusCode);

        // Fetch back to verify persistence
        var getReq = new HttpRequestMessage(HttpMethod.Get, "/api/availability/me");
        getReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var getResponse = await _client.SendAsync(getReq);
        var result = await getResponse.Content.ReadFromJsonAsync<AvailabilityResponse>();

        Assert.NotNull(result);
        Assert.False(result.MeetingRequestsEnabled);
        Assert.Equal("America/New_York", result.TimeZoneId);
    }

    [Fact]
    public async Task Test09_UserCannotEditAnotherAvailability_JWTIsAuthoritative()
    {
        var (authA, _) = await RegisterAndGetProfileAsync($"user_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"user_b_{Guid.NewGuid()}@example.com");

        // User A sets slots
        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = true,
            TimeZoneId = "UTC",
            Slots = new List<AvailabilitySlotDto>
            {
                new() { DayOfWeek = DayOfWeek.Friday, StartTime = "09:00", EndTime = "17:00" }
            }
        };

        var putRequest = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        await _client.SendAsync(putRequest);

        // User B fetches their own availability: User B's settings remain untouched
        var getB = new HttpRequestMessage(HttpMethod.Get, "/api/availability/me");
        getB.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var resB = await _client.SendAsync(getB);
        var availB = await resB.Content.ReadFromJsonAsync<AvailabilityResponse>();

        Assert.NotNull(availB);
        Assert.Empty(availB.Slots);
    }

    [Fact]
    public async Task Test10_ConnectedUser_CanViewAvailability()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"ansaf_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"denil_{Guid.NewGuid()}@example.com");

        // Ansaf sets availability
        var putAnsaf = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(new UpdateAvailabilityRequest
            {
                MeetingRequestsEnabled = true,
                TimeZoneId = "Asia/Kolkata",
                Slots = new List<AvailabilitySlotDto>
                {
                    new() { DayOfWeek = DayOfWeek.Monday, StartTime = "09:00", EndTime = "12:00" }
                }
            })
        };
        putAnsaf.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        await _client.SendAsync(putAnsaf);

        // Denil connects with Ansaf (saves Ansaf's profile)
        var connectReq = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = profileA.ShareId })
        };
        connectReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var connectRes = await _client.SendAsync(connectReq);
        Assert.Equal(HttpStatusCode.Created, connectRes.StatusCode);

        // Denil views Ansaf's availability using Ansaf's UserId
        var viewReq = new HttpRequestMessage(HttpMethod.Get, $"/api/availability/{authA.UserId}");
        viewReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var viewRes = await _client.SendAsync(viewReq);

        Assert.Equal(HttpStatusCode.OK, viewRes.StatusCode);
        var publicAvail = await viewRes.Content.ReadFromJsonAsync<PublicAvailabilityResponse>();
        Assert.NotNull(publicAvail);
        Assert.Equal(authA.UserId, publicAvail.UserId);
        Assert.Equal("Asia/Kolkata", publicAvail.TimeZoneId);
        Assert.Single(publicAvail.Slots);
    }

    [Fact]
    public async Task Test11_UnconnectedUser_CannotViewAvailability_ReturnsForbidden()
    {
        var (authA, _) = await RegisterAndGetProfileAsync($"stranger_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"stranger_b_{Guid.NewGuid()}@example.com");

        // User B attempts to view User A's availability without a connection
        var viewReq = new HttpRequestMessage(HttpMethod.Get, $"/api/availability/{authA.UserId}");
        viewReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var viewRes = await _client.SendAsync(viewReq);

        Assert.Equal(HttpStatusCode.Forbidden, viewRes.StatusCode);
    }

    [Fact]
    public async Task Test31_PublicShareEndpoint_DoesNotExposeMeetingOrAvailabilityData()
    {
        var (auth, profile) = await RegisterAndGetProfileAsync($"public_user_{Guid.NewGuid()}@example.com");

        // Set availability
        var putReq = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(new UpdateAvailabilityRequest
            {
                MeetingRequestsEnabled = true,
                TimeZoneId = "Asia/Kolkata",
                Slots = new List<AvailabilitySlotDto>
                {
                    new() { DayOfWeek = DayOfWeek.Monday, StartTime = "09:00", EndTime = "12:00" }
                }
            })
        };
        putReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        await _client.SendAsync(putReq);

        // Fetch unauthenticated public profile via shareId
        var publicRes = await _client.GetAsync($"/api/share/{profile.ShareId}");
        Assert.Equal(HttpStatusCode.OK, publicRes.StatusCode);

        var json = await publicRes.Content.ReadAsStringAsync();
        Assert.DoesNotContain("meeting", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("availability", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("slots", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Test11_SetAmericaNewYorkTimeZone_SavesAndNormalizesSuccessfully()
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"ny_avail_{Guid.NewGuid()}@example.com");

        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = true,
            TimeZoneId = "America/New_York",
            Slots = new List<AvailabilitySlotDto>
            {
                new() { DayOfWeek = DayOfWeek.Wednesday, StartTime = "09:00", EndTime = "17:00" }
            }
        };

        var putReq = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(putReq);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<AvailabilityResponse>();
        Assert.NotNull(result);
        Assert.Equal("America/New_York", result.TimeZoneId);
    }

    [Fact]
    public async Task Test12_SetInvalidTimeZone_ReturnsBadRequest()
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"invalid_tz_{Guid.NewGuid()}@example.com");

        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = true,
            TimeZoneId = "Mars/Olympus_Mons",
            Slots = new List<AvailabilitySlotDto>()
        };

        var putReq = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(putReq);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Theory]
    [InlineData("Europe/London")]
    [InlineData("Asia/Dubai")]
    [InlineData("Asia/Singapore")]
    [InlineData("Australia/Sydney")]
    public async Task Test13_SetVariousIanaTimezones_SavesSuccessfully(string timeZoneId)
    {
        var (auth, _) = await RegisterAndGetProfileAsync($"various_tz_{Guid.NewGuid()}@example.com");

        var updateReq = new UpdateAvailabilityRequest
        {
            MeetingRequestsEnabled = true,
            TimeZoneId = timeZoneId,
            Slots = new List<AvailabilitySlotDto>()
        };

        var putReq = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(updateReq)
        };
        putReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", auth.Token);
        var response = await _client.SendAsync(putReq);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var result = await response.Content.ReadFromJsonAsync<AvailabilityResponse>();
        Assert.NotNull(result);
        Assert.Equal(timeZoneId, result.TimeZoneId);
    }
}

