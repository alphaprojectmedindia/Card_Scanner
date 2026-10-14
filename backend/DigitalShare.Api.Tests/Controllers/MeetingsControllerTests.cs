using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Availability;
using DigitalShare.Api.DTOs.Connections;
using DigitalShare.Api.DTOs.Meetings;
using DigitalShare.Api.DTOs.Profile;
using DigitalShare.Api.Tests.Helpers;

namespace DigitalShare.Api.Tests.Controllers;

public class MeetingsControllerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public MeetingsControllerTests(CustomWebApplicationFactory factory)
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

    private async Task ConnectUsersAsync(AuthResponse requesterAuth, ProfileResponse recipientProfile)
    {
        var connectReq = new HttpRequestMessage(HttpMethod.Post, "/api/connections")
        {
            Content = JsonContent.Create(new SaveConnectionRequest { ShareId = recipientProfile.ShareId })
        };
        connectReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", requesterAuth.Token);
        var connectRes = await _client.SendAsync(connectReq);
        Assert.Equal(HttpStatusCode.Created, connectRes.StatusCode);
    }

    private async Task SetupRecipientAvailabilityAsync(AuthResponse recipientAuth, string timezoneId, DayOfWeek day, string start, string end)
    {
        var putReq = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(new UpdateAvailabilityRequest
            {
                MeetingRequestsEnabled = true,
                TimeZoneId = timezoneId,
                Slots = new List<AvailabilitySlotDto>
                {
                    new() { DayOfWeek = day, StartTime = start, EndTime = end }
                }
            })
        };
        putReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", recipientAuth.Token);
        var res = await _client.SendAsync(putReq);
        res.EnsureSuccessStatusCode();
    }

    [Fact]
    public async Task Test12_RequestMeeting_WithoutConnection_ReturnsForbidden()
    {
        var (authA, _) = await RegisterAndGetProfileAsync($"no_conn_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"no_conn_b_{Guid.NewGuid()}@example.com");

        // Try to request meeting without connection
        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authB.UserId,
                StartAtUtc = DateTime.UtcNow.AddDays(2),
                EndAtUtc = DateTime.UtcNow.AddDays(2).AddMinutes(30),
                Title = "Test Meeting"
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var res = await _client.SendAsync(createReq);

        Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);
    }

    [Fact]
    public async Task Test13_RequestMeeting_WithSelf_ReturnsBadRequest()
    {
        var (authA, _) = await RegisterAndGetProfileAsync($"self_a_{Guid.NewGuid()}@example.com");

        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = DateTime.UtcNow.AddDays(1),
                EndAtUtc = DateTime.UtcNow.AddDays(1).AddMinutes(30)
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var res = await _client.SendAsync(createReq);

        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    [Fact]
    public async Task Test14_RequestMeeting_WhenRecipientDisabledMeetingRequests_ReturnsBadRequest()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"recip_dis_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"req_dis_{Guid.NewGuid()}@example.com");

        // Connect
        await ConnectUsersAsync(authB, profileA);

        // Recipient disables meeting requests
        var putReq = new HttpRequestMessage(HttpMethod.Put, "/api/availability/me")
        {
            Content = JsonContent.Create(new UpdateAvailabilityRequest
            {
                MeetingRequestsEnabled = false,
                TimeZoneId = "UTC",
                Slots = new List<AvailabilitySlotDto>()
            })
        };
        putReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        await _client.SendAsync(putReq);

        // Requester attempts to request meeting
        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = DateTime.UtcNow.AddDays(1),
                EndAtUtc = DateTime.UtcNow.AddDays(1).AddMinutes(30)
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var res = await _client.SendAsync(createReq);

        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    [Fact]
    public async Task Test17_RequestMeeting_InPast_ReturnsBadRequest()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"past_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"past_b_{Guid.NewGuid()}@example.com");

        await ConnectUsersAsync(authB, profileA);

        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = DateTime.UtcNow.AddHours(-2),
                EndAtUtc = DateTime.UtcNow.AddHours(-1)
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var res = await _client.SendAsync(createReq);

        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    [Fact]
    public async Task Test15_18_28_29_RequestInsideAvailability_Succeeds_CreatesPending_AndTimezoneCorrect()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"ansaf_tz_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"denil_tz_{Guid.NewGuid()}@example.com");

        await ConnectUsersAsync(authB, profileA);

        // Recipient (Ansaf) is in Asia/Kolkata (+05:30)
        // Next Monday, 14:00 - 17:00 IST
        // Let's compute a date that is a Monday in the future
        var now = DateTime.UtcNow;
        var daysUntilMonday = ((int)DayOfWeek.Monday - (int)now.DayOfWeek + 7) % 7;
        if (daysUntilMonday == 0) daysUntilMonday = 7;
        var nextMondayDate = now.AddDays(daysUntilMonday).Date;

        await SetupRecipientAvailabilityAsync(authA, "Asia/Kolkata", DayOfWeek.Monday, "14:00", "17:00");

        // 14:30 - 15:00 IST on that Monday corresponds to 09:00 - 09:30 UTC
        var tz = TimeZoneInfo.FindSystemTimeZoneById("Asia/Kolkata");
        var localStart = new DateTime(nextMondayDate.Year, nextMondayDate.Month, nextMondayDate.Day, 14, 30, 0);
        var localEnd = new DateTime(nextMondayDate.Year, nextMondayDate.Month, nextMondayDate.Day, 15, 0, 0);
        var utcStart = TimeZoneInfo.ConvertTimeToUtc(localStart, tz);
        var utcEnd = TimeZoneInfo.ConvertTimeToUtc(localEnd, tz);

        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = utcStart,
                EndAtUtc = utcEnd,
                Title = "Project Discussion",
                Note = "Let's review Phase 7"
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var res = await _client.SendAsync(createReq);

        Assert.Equal(HttpStatusCode.Created, res.StatusCode);
        var meeting = await res.Content.ReadFromJsonAsync<MeetingResponse>();
        Assert.NotNull(meeting);
        Assert.Equal("Pending", meeting.Status);
        Assert.Equal("Project Discussion", meeting.Title);
        Assert.Equal(utcStart, meeting.StartAtUtc);
        Assert.Equal(utcEnd, meeting.EndAtUtc);
        Assert.Equal(authB.UserId, meeting.RequesterUserId);
        Assert.Equal(authA.UserId, meeting.RecipientUserId);
    }

    [Fact]
    public async Task Test16_RequestOutsideAvailability_ReturnsBadRequest()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"ansaf_out_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"denil_out_{Guid.NewGuid()}@example.com");

        await ConnectUsersAsync(authB, profileA);

        var now = DateTime.UtcNow;
        var daysUntilMonday = ((int)DayOfWeek.Monday - (int)now.DayOfWeek + 7) % 7;
        if (daysUntilMonday == 0) daysUntilMonday = 7;
        var nextMondayDate = now.AddDays(daysUntilMonday).Date;

        // Slot is 14:00 - 17:00 UTC
        await SetupRecipientAvailabilityAsync(authA, "UTC", DayOfWeek.Monday, "14:00", "17:00");

        // Try to request 17:30 - 18:00 UTC (outside slot)
        var utcStart = new DateTime(nextMondayDate.Year, nextMondayDate.Month, nextMondayDate.Day, 17, 30, 0, DateTimeKind.Utc);
        var utcEnd = new DateTime(nextMondayDate.Year, nextMondayDate.Month, nextMondayDate.Day, 18, 0, 0, DateTimeKind.Utc);

        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = utcStart,
                EndAtUtc = utcEnd,
                Title = "Outside Availability"
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var res = await _client.SendAsync(createReq);

        Assert.Equal(HttpStatusCode.BadRequest, res.StatusCode);
    }

    [Fact]
    public async Task Test19_20_21_22_23_27_MeetingTransitions_Accept_Reject_Cancel_And_AuthRules()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"flow_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"flow_b_{Guid.NewGuid()}@example.com");
        var (authC, _) = await RegisterAndGetProfileAsync($"stranger_c_{Guid.NewGuid()}@example.com");

        await ConnectUsersAsync(authB, profileA);

        var now = DateTime.UtcNow;
        var daysUntilFriday = ((int)DayOfWeek.Friday - (int)now.DayOfWeek + 7) % 7;
        if (daysUntilFriday == 0) daysUntilFriday = 7;
        var fridayDate = now.AddDays(daysUntilFriday).Date;

        await SetupRecipientAvailabilityAsync(authA, "UTC", DayOfWeek.Friday, "09:00", "17:00");

        var utcStart = new DateTime(fridayDate.Year, fridayDate.Month, fridayDate.Day, 10, 0, 0, DateTimeKind.Utc);
        var utcEnd = new DateTime(fridayDate.Year, fridayDate.Month, fridayDate.Day, 10, 30, 0, DateTimeKind.Utc);

        // 1. Create meeting request from B to A
        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = utcStart,
                EndAtUtc = utcEnd,
                Title = "Flow Meeting"
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var createRes = await _client.SendAsync(createReq);
        Assert.Equal(HttpStatusCode.Created, createRes.StatusCode);
        var meeting = await createRes.Content.ReadFromJsonAsync<MeetingResponse>();
        Assert.NotNull(meeting);

        // 23. Stranger C cannot accept or reject
        var strangerAcceptReq = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting.Id}/accept");
        strangerAcceptReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authC.Token);
        var strangerRes = await _client.SendAsync(strangerAcceptReq);
        Assert.Equal(HttpStatusCode.Forbidden, strangerRes.StatusCode);

        // 23. Requester B cannot accept their own request (only recipient can accept)
        var reqAcceptReq = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting.Id}/accept");
        reqAcceptReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var reqAcceptRes = await _client.SendAsync(reqAcceptReq);
        Assert.Equal(HttpStatusCode.Forbidden, reqAcceptRes.StatusCode);

        // 19. Recipient A accepts
        var acceptReq = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting.Id}/accept");
        acceptReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var acceptRes = await _client.SendAsync(acceptReq);
        Assert.Equal(HttpStatusCode.OK, acceptRes.StatusCode);
        var acceptedMeeting = await acceptRes.Content.ReadFromJsonAsync<MeetingResponse>();
        Assert.NotNull(acceptedMeeting);
        Assert.Equal("Accepted", acceptedMeeting.Status);

        // 27. Invalid transition: Cannot reject already accepted meeting
        var rejectAcceptedReq = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting.Id}/reject");
        rejectAcceptedReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var rejectAcceptedRes = await _client.SendAsync(rejectAcceptedReq);
        Assert.Equal(HttpStatusCode.BadRequest, rejectAcceptedRes.StatusCode);

        // 22. Participant cancels Accepted meeting
        var cancelReq = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting.Id}/cancel");
        cancelReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var cancelRes = await _client.SendAsync(cancelReq);
        Assert.Equal(HttpStatusCode.OK, cancelRes.StatusCode);
        var cancelledMeeting = await cancelRes.Content.ReadFromJsonAsync<MeetingResponse>();
        Assert.NotNull(cancelledMeeting);
        Assert.Equal("Cancelled", cancelledMeeting.Status);

        // 27. Invalid transition: Cannot accept a cancelled meeting
        var reAcceptReq = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting.Id}/accept");
        reAcceptReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var reAcceptRes = await _client.SendAsync(reAcceptReq);
        Assert.Equal(HttpStatusCode.BadRequest, reAcceptRes.StatusCode);
    }

    [Fact]
    public async Task Test24_25_AcceptedOverlapConflict_Rejected_And_NonOverlapping_Accepted()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"conflict_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"conflict_b_{Guid.NewGuid()}@example.com");

        await ConnectUsersAsync(authB, profileA);

        var now = DateTime.UtcNow;
        var daysUntilTuesday = ((int)DayOfWeek.Tuesday - (int)now.DayOfWeek + 7) % 7;
        if (daysUntilTuesday == 0) daysUntilTuesday = 7;
        var tuesdayDate = now.AddDays(daysUntilTuesday).Date;

        await SetupRecipientAvailabilityAsync(authA, "UTC", DayOfWeek.Tuesday, "09:00", "17:00");

        // First meeting: 10:00 - 11:00 UTC
        var start1 = new DateTime(tuesdayDate.Year, tuesdayDate.Month, tuesdayDate.Day, 10, 0, 0, DateTimeKind.Utc);
        var end1 = new DateTime(tuesdayDate.Year, tuesdayDate.Month, tuesdayDate.Day, 11, 0, 0, DateTimeKind.Utc);

        var req1 = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = start1,
                EndAtUtc = end1,
                Title = "Meeting 1"
            })
        };
        req1.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var res1 = await _client.SendAsync(req1);
        Assert.Equal(HttpStatusCode.Created, res1.StatusCode);
        var meeting1 = await res1.Content.ReadFromJsonAsync<MeetingResponse>();
        Assert.NotNull(meeting1);

        // Accept meeting 1
        var acceptReq1 = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting1.Id}/accept");
        acceptReq1.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var acceptRes1 = await _client.SendAsync(acceptReq1);
        Assert.Equal(HttpStatusCode.OK, acceptRes1.StatusCode);

        // 24. Try to request overlapping meeting: 10:30 - 11:30 UTC -> Conflict (409)
        var startOverlap = new DateTime(tuesdayDate.Year, tuesdayDate.Month, tuesdayDate.Day, 10, 30, 0, DateTimeKind.Utc);
        var endOverlap = new DateTime(tuesdayDate.Year, tuesdayDate.Month, tuesdayDate.Day, 11, 30, 0, DateTimeKind.Utc);

        var reqOverlap = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = startOverlap,
                EndAtUtc = endOverlap,
                Title = "Overlapping Meeting"
            })
        };
        reqOverlap.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var resOverlap = await _client.SendAsync(reqOverlap);
        Assert.Equal(HttpStatusCode.Conflict, resOverlap.StatusCode);

        // 25. Non-overlapping meeting (11:00 - 12:00 UTC, adjacent) succeeds and can be accepted
        var start2 = new DateTime(tuesdayDate.Year, tuesdayDate.Month, tuesdayDate.Day, 11, 0, 0, DateTimeKind.Utc);
        var end2 = new DateTime(tuesdayDate.Year, tuesdayDate.Month, tuesdayDate.Day, 12, 0, 0, DateTimeKind.Utc);

        var req2 = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = start2,
                EndAtUtc = end2,
                Title = "Adjacent Meeting 2"
            })
        };
        req2.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var res2 = await _client.SendAsync(req2);
        Assert.Equal(HttpStatusCode.Created, res2.StatusCode);
        var meeting2 = await res2.Content.ReadFromJsonAsync<MeetingResponse>();
        Assert.NotNull(meeting2);

        var acceptReq2 = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting2.Id}/accept");
        acceptReq2.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var acceptRes2 = await _client.SendAsync(acceptReq2);
        Assert.Equal(HttpStatusCode.OK, acceptRes2.StatusCode);
    }

    [Fact]
    public async Task Test32_GetMeetings_Categorizes_Upcoming_Requests_History_Correctly()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"cat_a_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"cat_b_{Guid.NewGuid()}@example.com");

        await ConnectUsersAsync(authB, profileA);

        var now = DateTime.UtcNow;
        var daysUntilWed = ((int)DayOfWeek.Wednesday - (int)now.DayOfWeek + 7) % 7;
        if (daysUntilWed == 0) daysUntilWed = 7;
        var wedDate = now.AddDays(daysUntilWed).Date;

        await SetupRecipientAvailabilityAsync(authA, "UTC", DayOfWeek.Wednesday, "09:00", "17:00");

        var start = new DateTime(wedDate.Year, wedDate.Month, wedDate.Day, 10, 0, 0, DateTimeKind.Utc);
        var end = new DateTime(wedDate.Year, wedDate.Month, wedDate.Day, 10, 30, 0, DateTimeKind.Utc);

        // Create pending request
        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = start,
                EndAtUtc = end,
                Title = "Pending Categorized Meeting"
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var createRes = await _client.SendAsync(createReq);
        Assert.Equal(HttpStatusCode.Created, createRes.StatusCode);

        // Fetch meetings for Recipient A
        var getReq = new HttpRequestMessage(HttpMethod.Get, "/api/meetings");
        getReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var getRes = await _client.SendAsync(getReq);
        Assert.Equal(HttpStatusCode.OK, getRes.StatusCode);

        var list = await getRes.Content.ReadFromJsonAsync<MeetingListResponse>();
        Assert.NotNull(list);
        Assert.NotEmpty(list.Requests);
        Assert.Contains(list.Requests, m => m.Title == "Pending Categorized Meeting");
    }

    [Fact]
    public async Task Test28_MeetingInAmericaNewYorkTimezone_ValidatedAndAcceptedSuccessfully()
    {
        var (authA, profileA) = await RegisterAndGetProfileAsync($"ny_recip_{Guid.NewGuid()}@example.com");
        var (authB, _) = await RegisterAndGetProfileAsync($"ny_req_{Guid.NewGuid()}@example.com");

        await ConnectUsersAsync(authB, profileA);

        // Recipient A sets availability in America/New_York for Thursday 13:00 - 17:00
        await SetupRecipientAvailabilityAsync(authA, "America/New_York", DayOfWeek.Thursday, "13:00", "17:00");

        var now = DateTime.UtcNow;
        var daysUntilThursday = ((int)DayOfWeek.Thursday - (int)now.DayOfWeek + 7) % 7;
        if (daysUntilThursday == 0) daysUntilThursday = 7;
        var nextThursdayDate = now.AddDays(daysUntilThursday).Date;

        var nyTz = TimeZoneConverter.TZConvert.GetTimeZoneInfo("America/New_York");

        // 14:00 - 14:30 local New York time (inside 13:00 - 17:00 slot)
        var localStart = new DateTime(nextThursdayDate.Year, nextThursdayDate.Month, nextThursdayDate.Day, 14, 0, 0);
        var localEnd = new DateTime(nextThursdayDate.Year, nextThursdayDate.Month, nextThursdayDate.Day, 14, 30, 0);
        var utcStart = TimeZoneInfo.ConvertTimeToUtc(localStart, nyTz);
        var utcEnd = TimeZoneInfo.ConvertTimeToUtc(localEnd, nyTz);

        // Valid request inside slot
        var createReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = utcStart,
                EndAtUtc = utcEnd,
                Title = "NYC Strategy Sync"
            })
        };
        createReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var createRes = await _client.SendAsync(createReq);
        Assert.Equal(HttpStatusCode.Created, createRes.StatusCode);

        var meeting = await createRes.Content.ReadFromJsonAsync<MeetingResponse>();
        Assert.NotNull(meeting);

        // Recipient accepts meeting
        var acceptReq = new HttpRequestMessage(HttpMethod.Post, $"/api/meetings/{meeting.Id}/accept");
        acceptReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authA.Token);
        var acceptRes = await _client.SendAsync(acceptReq);
        Assert.Equal(HttpStatusCode.OK, acceptRes.StatusCode);

        // Request outside slot: 18:00 - 18:30 New York time
        var outsideLocalStart = new DateTime(nextThursdayDate.Year, nextThursdayDate.Month, nextThursdayDate.Day, 18, 0, 0);
        var outsideLocalEnd = new DateTime(nextThursdayDate.Year, nextThursdayDate.Month, nextThursdayDate.Day, 18, 30, 0);
        var outsideUtcStart = TimeZoneInfo.ConvertTimeToUtc(outsideLocalStart, nyTz);
        var outsideUtcEnd = TimeZoneInfo.ConvertTimeToUtc(outsideLocalEnd, nyTz);

        var outsideReq = new HttpRequestMessage(HttpMethod.Post, "/api/meetings")
        {
            Content = JsonContent.Create(new CreateMeetingRequest
            {
                RecipientUserId = authA.UserId,
                StartAtUtc = outsideUtcStart,
                EndAtUtc = outsideUtcEnd,
                Title = "Late Night NYC (Outside Slot)"
            })
        };
        outsideReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", authB.Token);
        var outsideRes = await _client.SendAsync(outsideReq);
        Assert.Equal(HttpStatusCode.BadRequest, outsideRes.StatusCode);
    }
}

