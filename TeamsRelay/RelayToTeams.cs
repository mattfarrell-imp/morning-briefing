using System;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace TeamsRelay;

public class RelayToTeams
{
    private static readonly HttpClient _http = new();

    [Function("RelayToTeams")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
    {
        var webhookUrl = Environment.GetEnvironmentVariable("TEAMS_WEBHOOK_URL");
        if (string.IsNullOrEmpty(webhookUrl))
        {
            var error = req.CreateResponse(HttpStatusCode.InternalServerError);
            await error.WriteStringAsync("TEAMS_WEBHOOK_URL not configured");
            return error;
        }

        var body = await req.ReadAsStringAsync();
        if (string.IsNullOrEmpty(body))
        {
            var error = req.CreateResponse(HttpStatusCode.BadRequest);
            await error.WriteStringAsync("Empty request body");
            return error;
        }

        var content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");
        var result = await _http.PostAsync(webhookUrl, content);

        var response = req.CreateResponse(result.StatusCode);
        var resultBody = await result.Content.ReadAsStringAsync();
        await response.WriteStringAsync(resultBody);
        return response;
    }
}
