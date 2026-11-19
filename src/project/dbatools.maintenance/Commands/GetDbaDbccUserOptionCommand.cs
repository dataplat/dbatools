#nullable enable

using System;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbccUserOption.ps1 at refs/pins/dbatools-2026-10-22: DBCC USEROPTIONS on the connection of each instance, and one object per row or per option asked for.
/// <summary>Retrieves current session-level SET options and connection settings from SQL Server instances</summary>
/// <para>
/// Executes DBCC USEROPTIONS against SQL Server instances to display current session settings including ANSI options, isolation levels, date formats, language, and timeout values. This is particularly useful when troubleshooting application connection issues or verifying that session-level defaults match across environments. You can filter results to specific options or retrieve all current settings to compare against expected configurations during deployments or performance investigations.
/// </para>
/// <para>
/// Read more:
/// - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-useroptions-transact-sql
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccUserOption -SqlInstance Server1
/// </code>
/// <para>
/// Get results of DBCC USEROPTIONS for Instance Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbccUserOption
/// </code>
/// <para>
/// Get results of DBCC USEROPTIONS for Instances Sql1 and Sql2/sqlexpress
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; Get-DbaDbccUserOption -SqlInstance Server1 -SqlCredential $cred
/// </code>
/// <para>
/// Connects using sqladmin credential and gets results of DBCC USEROPTIONS for Instance Server1
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccUserOption -SqlInstance Server1 -Option ansi_nulls, ansi_warnings, datefirst
/// </code>
/// <para>
/// Gets results of DBCC USEROPTIONS for Instance Server1. Only display results for the options ansi_nulls, ansi_warnings, datefirst
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: DBCC
/// Author: Patrick Flynn (@sqllensman)
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaDbccUserOption" />
[Cmdlet(VerbsCommon.Get, "DbaDbccUserOption")]
public sealed class GetDbaDbccUserOptionCommand : DbaInstanceCmdlet
{
    private const string Query = "DBCC USEROPTIONS WITH NO_INFOMSGS";

    /// <para>
    /// The target SQL Server instance or instances.
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

    /// <para>
    /// Filters results to show only specific session options instead of all DBCC USEROPTIONS output. Use this when troubleshooting specific connection settings like ANSI options, date formats, or isolation levels without seeing the full list of 13 available options.
    /// Accepts any values in set 'ansi_null_dflt_on', 'ansi_nulls', 'ansi_padding', 'ansi_warnings', 'arithabort', 'concat_null_yields_null', 'datefirst', 'dateformat', 'isolation level', 'language', 'lock_timeout', 'quoted_identifier', 'textsize'
    /// </para>
    [Parameter(Position = 2)]
    [ValidateSet("ansi_null_dflt_on", "ansi_nulls", "ansi_padding", "ansi_warnings", "arithabort", "concat_null_yields_null", "datefirst", "dateformat", "isolation level", "language", "lock_timeout", "quoted_identifier", "textsize")]
    public string[]? Option { get; set; }

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
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            DataTable? results;
            try
            {
                WriteMessage(MessageLevel.Verbose, "Query to run: " + Query);
                DataSet tables = server.ConnectionContext.ExecuteWithResults(Query);
                results = tables.Tables.Count > 0 ? tables.Tables[0] : null;
            }
            // No test reaches this catch, and its text and record are by reading the pin: the DBCC needs only the public role, and no form measured on the pin got past
            // Connect-DbaInstance's own SELECT and then failed here (evidence/pin-useroption3-20261104.txt: a disabled or denied caller fails at that SELECT, a killed one reconnects,
            // SHOWPLAN, NOEXEC, PARSEONLY, FMTONLY and EXECUTE AS sessions do not fault). The record follows Get-DbaDbccProcCache's measured one.
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction("Failure running " + Query + " against " + instance, target: server, errorRecord: QueryRecord(failure), continueLoop: true);
                continue;
            }

            if (results is null)
                continue;

            // The pin's row loop sits outside its try and holds only reads of the server and the row. No fault there showed in any case its pin measured on both editions
            // (evidence/pin-useroption-20261103.txt), and none is proven absent.
            foreach (DataRow row in results.Rows)
            {
                object? name = Cell(row, 0);
                if (TestBound(nameof(Option)) && !PsString.In(name?.ToString(), Option ?? Array.Empty<string>()))
                    continue;

                PSObject output = new();
                OutputHelper.AddInstanceProperties(output, server);
                output.Properties.Add(new PSNoteProperty("Option", name));
                output.Properties.Add(new PSNoteProperty("Value", Cell(row, 1)));
                WriteObject(output);
            }
        }
    }

    // PS: $row[n]; an ordinal past the last column reads $null.
    private static object? Cell(DataRow row, int ordinal)
    {
        return ordinal < row.Table.Columns.Count ? row[ordinal] : null;
    }

    // PS: $_ for a failed $server.Query: the script method's catch joins the messages of the exception chain and throws that
    // text, which the method call reports as "Exception calling "Query" ...".
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
