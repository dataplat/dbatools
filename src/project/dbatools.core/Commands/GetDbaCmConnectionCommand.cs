#nullable enable

using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaCmConnection.ps1 at refs/pins/dbatools-2026-10-22: the begin and end
// Write-Message diagnostics and the per-name filter over the in-memory connection cache.
/// <summary>Retrieves cached Windows Management and CIM connections used by dbatools commands</summary>
/// <para>
/// Shows which remote computer connections are currently cached by dbatools for Windows Management and CIM operations. This helps you understand what authentication contexts are active and troubleshoot connection issues when running dbatools commands against remote SQL Server instances. Cached connections are automatically created when you run dbatools commands that need to access Windows services, registry, or file system on remote servers.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCmConnection
/// </code>
/// <para>
/// List all cached connections.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCmConnection sql2014
/// </code>
/// <para>
/// List the cached connection - if any - to the server sql2014.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaCmConnection -UserName "*charles*"
/// </code>
/// <para>
/// List all cached connection that use a username containing "charles" as default or override credentials.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: ComputerManagement, CIM
/// Author: Friedrich Weinmann (@FredWeinmann)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaCmConnection" />
[Cmdlet(VerbsCommon.Get, "DbaCmConnection")]
public sealed class GetDbaCmConnectionCommand : DbaBaseCmdlet
{
    // Positions follow the pinned function's automatic positional binding: every
    // non-switch parameter in declaration order.

    /// <para>
    /// Filters cached connections by computer name or server name. Supports wildcards for pattern matching.
    /// Use this to check connections to specific SQL Server hosts or to search for connections matching a pattern like "sql*prod*".
    /// </para>
    [Parameter(Position = 0, ValueFromPipeline = true)]
    [Alias("Filter")]
    public string[]? ComputerName { get; set; } = new[] { "*" };

    /// <para>
    /// Filters cached connections by the username in the stored credentials. Supports wildcards for pattern matching.
    /// Use this to find connections using specific service accounts or domain credentials. Will not match connections using integrated Windows authentication.
    /// </para>
    [Parameter(Position = 1)]
    public string? UserName { get; set; } = "*";

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void BeginProcessing()
    {
        WriteMessage(MessageLevel.InternalComment, "Starting");
        WriteMessage(MessageLevel.Verbose, "Bound parameters: " + string.Join(", ", MyInvocation.BoundParameters.Keys));
    }

    protected override void ProcessRecord()
    {
        // PS: foreach ($name in $ComputerName) over a [String[]] parameter; $null runs no iteration.
        if (ComputerName is null)
        {
            return;
        }

        // PS: [String]$UserName turns $null into an empty string.
        string userName = UserName ?? string.Empty;
        foreach (string? name in ComputerName)
        {
            string pattern = name ?? string.Empty;
            WriteMessage(MessageLevel.VeryVerbose, string.Format(CultureInfo.InvariantCulture,
                "Processing search. ComputerName: '{0}' | Username: '{1}'", pattern, userName));

            // PS: (ConnectionHost::Connections.Values | Where-Object { ($_.ComputerName -like $name) -and ($_.Credentials.UserName -like $UserName) })
            // An invalid pattern throws WildcardPatternException as -like does.
            // The pinned parentheses finish the search before emitting anything, so collect the matches
            // first: a downstream Remove-DbaCmConnection then cannot invalidate the cache enumerator
            // (on .NET Framework, Dictionary.Remove does; Windows PowerShell 5.1).
            var matches = new List<ManagementConnection>();
            foreach (ManagementConnection connection in ConnectionHost.Connections.Values)
            {
                if (Like(connection.ComputerName, pattern) && Like(connection.Credentials?.UserName, userName))
                {
                    matches.Add(connection);
                }
            }

            foreach (ManagementConnection connection in matches)
            {
                WriteObject(connection);
            }
        }
    }

    protected override void EndProcessing()
    {
        WriteMessage(MessageLevel.InternalComment, "Ending");
    }

    // PS: $value -like $pattern, case-insensitive; a $null value compares as an empty string.
    private static bool Like(string? value, string pattern)
    {
        return new WildcardPattern(pattern, WildcardOptions.IgnoreCase).IsMatch(value ?? string.Empty);
    }
}
