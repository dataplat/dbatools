#nullable enable

using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The AWS EC2 instance metadata service as Get-DbaComputerSystem -IncludeAws reads it: its
/// address, the paths the PS source queried, and reading members from the responses.
/// </summary>
internal static class AwsInstanceMetadata
{
    /// <summary>The link-local address of the instance metadata service.</summary>
    internal const string DefaultBaseAddress = "http://169.254.169.254";

    /// <summary>The PS source's -TimeoutSec for the probe of the metadata root.</summary>
    internal const int ProbeTimeoutSeconds = 15;

    /// <summary>The metadata category path, relative to the base address.</summary>
    internal const string MetadataPath = "/latest/meta-data/";

    /// <summary>IMDSv2: the session token path, relative to the base address.</summary>
    internal const string TokenPath = "/latest/api/token";

    /// <summary>IMDSv2: the header asking for a session token of the given lifetime.</summary>
    internal const string TokenTtlHeader = "X-aws-ec2-metadata-token-ttl-seconds";

    /// <summary>IMDSv2: the session token lifetime asked for, in seconds.</summary>
    internal const string TokenTtlSeconds = "21600";

    /// <summary>IMDSv2: the header that carries the session token on each request.</summary>
    internal const string TokenHeader = "X-aws-ec2-metadata-token";

    /// <summary>The service answers on the link-local address at once; a host without it should not wait long.</summary>
    internal const int TokenTimeoutSeconds = 2;

    /// <summary>Whether a response is an EC2 instance id (i- followed by 8 or 17 hex digits).</summary>
    internal static bool IsInstanceId(object? response)
    {
        return response is string text && Regex.IsMatch(text.Trim(), "^i-(?:[0-9a-f]{8}|[0-9a-f]{17})$");
    }

    // Test seam: the native tests aim the service at a local listener through reflection and put
    // the default back afterwards, so a red can show what an EC2 instance would answer. Nothing in
    // the module writes it.
    private static string baseAddress = DefaultBaseAddress; // style-ok: cs-static-state test seam for the native tests' local metadata listener; never written by the module

    /// <summary>The address requests go to: the metadata service, unless a native test redirected it.</summary>
    internal static string BaseAddress => baseAddress;

    /// <summary>
    /// A member of a response as Invoke-RestMethod returns it: a parsed object (remote), or the
    /// JSON text of a flat object of string members (in process).
    /// </summary>
    internal static object? ReadMember(object? response, string member)
    {
        if (response is null)
        {
            return null;
        }
        if (response is string json)
        {
            Match match = Regex.Match(json, "\"" + Regex.Escape(member) + "\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\"");
            return match.Success ? Regex.Unescape(match.Groups[1].Value) : null;
        }
        return PSObject.AsPSObject(response).Properties[member]?.Value;
    }
}
