#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDeprecatedFeature.ps1 at refs/pins/dbatools-2026-10-22: the deprecated features' usage counters on the connection of each instance, one object per row.
// Expected values as the pin measured on both editions: evidence/pin-deprecated-20261104.txt, whose case names the comments below use.
/// <summary>Identifies deprecated SQL Server features currently in use with their usage counts from performance counters.</summary>
/// <para>
/// Queries the sys.dm_os_performance_counters system view to identify which deprecated SQL Server features have been used on your instances and how frequently they've been accessed. This information is essential for upgrade planning, as deprecated features may be removed in future SQL Server versions and could cause application failures.
/// </para>
/// <para>
/// The function returns only features that have been used (usage count greater than zero), helping you prioritize which code needs to be modernized before upgrading SQL Server. Common deprecated features include old JOIN syntax, legacy data types, and obsolete T-SQL functions.
/// </para>
/// <para>
/// More information: https://learn.microsoft.com/en-us/sql/relational-databases/performance-monitor/sql-server-deprecated-features-object
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDeprecatedFeature -SqlInstance sql2008, sqlserver2012
/// </code>
/// <para>
/// Get usage information relating to deprecated features on the servers sql2008 and sqlserver2012.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDeprecatedFeature -SqlInstance sql2008
/// </code>
/// <para>
/// Get usage information relating to deprecated features on server sql2008.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Deprecated, General
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDeprecatedFeature" />
[Cmdlet(VerbsCommon.Get, "DbaDeprecatedFeature")]
public sealed class GetDbaDeprecatedFeatureCommand : DbaInstanceCmdlet
{
    private const string Query = "SELECT LTRIM(RTRIM(instance_name)) AS DeprecatedFeature, cntr_value AS UsageCount FROM sys.dm_os_performance_counters WHERE object_name LIKE '%SQL%Deprecated Features%' AND cntr_value > 0";

    /// <para>
    /// The target SQL Server instance
    /// </para>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            Server? server = ConnectInstance(instance, "Failure", 9);
            if (server is null)
                continue;

            // Correction stale-rows: in the pin $usedDeprecatedFeatures keeps its value when the query faults, so the rows of the instance before go out again under this instance's name
            // (stale-good-then-low, stale-piped-good-then-low). An instance whose read failed has no rows here.
            if (!TryReadFeatures(server, out DataTable? features) || features is null)
                continue;

            foreach (DataRow feature in features.Rows)
            {
                PSObject output = new();
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("DeprecatedFeature", feature["DeprecatedFeature"]));
                output.Properties.Add(new PSNoteProperty("UsageCount", feature["UsageCount"]));
                WriteObject(output);
            }
        }
    }

    // PS: $server.Query(...), outside any try, on the connection as it stands.
    private bool TryReadFeatures(Server server, out DataTable? features)
    {
        features = null;
        ErrorRecord fault;
        try
        {
            DataSet tables = server.ConnectionContext.ExecuteWithResults(Query);
            features = tables.Tables.Count > 0 ? tables.Tables[0] : null;
            return true;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            fault = QueryRecord(failure);
        }
        ReportFault(fault);
        return false;
    }

    // Accepted differences kept by the keep-going section's point 3: -EnableException stops here with this record, where the pin writes it and goes on (low-ee); -ErrorAction Stop has the
    // effect PowerShell gives WriteError (low-stop). $ErrorActionPreference set in the caller's scope acts on this WriteError as for any compiled command, where the pin ignores it:
    // harness-edits.md, "Script-scope preferences and the one-line connect warning", points 1 and 2.
    private void ReportFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault of the pin, outside Stop-Function
        }

        // A plain call goes on; under a caller try the record stops the command, as the fault stops the pin's statement (low-plain, low-try).
        StatementFault.Surface(this, fault);
    }

    // PS: the record of a failed $server.Query: the script method's catch joins the messages of the exception chain and throws that text, which the method call reports as
    // "Exception calling "Query" ...", as the pin measured (low-plain).
    private static ErrorRecord QueryRecord(Exception failure)
    {
        StringBuilder joined = new();
        for (Exception? current = failure; current is not null; current = current.InnerException)
            joined.Append(current.Message);
        string message = joined.ToString();
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", message), new RuntimeException(message, new RuntimeException(message)));
        return new ErrorRecord(call, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
