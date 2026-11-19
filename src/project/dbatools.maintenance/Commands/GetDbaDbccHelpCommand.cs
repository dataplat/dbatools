#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbccHelp.ps1 at refs/pins/dbatools-2026-10-22: the connect, DBCC HELP through what the nested
// Invoke-DbaQuery does with -MessagesToOutput, and the one object per instance of the pin.
/// <summary>Retrieves syntax help and parameter information for DBCC commands</summary>
/// <para>
/// Executes DBCC HELP against SQL Server to display syntax, parameters, and usage information for Database Console Commands. This saves you from having to look up DBCC command syntax in documentation, especially for complex commands like CHECKDB, CHECKTABLE, or SHRINKFILE. Supports both documented and undocumented DBCC commands when used with the IncludeUndocumented parameter.
/// </para>
/// <para>
/// Read more:
/// - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-help-transact-sql
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccHelp -SqlInstance SQLInstance -Statement FREESYSTEMCACHE -Verbose | Format-List
/// </code>
/// <para>
/// Runs the command DBCC HELP(FREESYSTEMCACHE) WITH NO_INFOMSGS against the SQLInstance SQL Server instance.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbccHelp -SqlInstance SQLInstance -Statement WritePage -IncludeUndocumented | Format-List
/// </code>
/// <para>
/// Sets Trace Flag 2588 on for the session and then runs the command DBCC HELP(WritePage) WITH NO_INFOMSGS against the SQLInstance SQL Server instance.
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
/// <seealso href="https://dbatools.io/Get-DbaDbccHelp" />
[Cmdlet(VerbsCommon.Get, "DbaDbccHelp")]
public sealed class GetDbaDbccHelpCommand : DbaInstanceCmdlet
{
    private const string QueryRunner = "Invoke-DbaQuery";
    private const string HelpTemplate = "DBCC HELP(#statement#) WITH NO_INFOMSGS;";
    private const string BoundHelp = "DBCC HELP(@statement) WITH NO_INFOMSGS;";

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
    /// Specifies the DBCC command name to get syntax help for. Provide only the command portion after "DBCC" (e.g., CHECKDB, CHECKTABLE, SHRINKFILE).
    /// Use this when you need to verify command syntax before running maintenance operations or troubleshooting database issues.
    /// Common commands include CHECKDB for database integrity, SHRINKFILE for file management, or FREEPROCCACHE for memory management.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string? Statement { get; set; }

    /// <para>
    /// Enables access to help for undocumented DBCC commands by setting trace flag 2588 for the session.
    /// Use this when troubleshooting advanced scenarios that require undocumented commands like WRITEPAGE or PAGE.
    /// Only works on SQL Server 2005 and higher, and should be used with caution as undocumented commands can affect system stability.
    /// </para>
    [Parameter]
    public SwitchParameter IncludeUndocumented { get; set; }

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
        if (!TestBound(nameof(Statement)))
        {
            StopFunction("You must specify a value for Statement");
            return;
        }
        WriteMessage(MessageLevel.Verbose, "Get Help Information for " + Statement);
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: -MinimumVersion 9 can no longer refuse anything: the connection layer refuses what is older than SQL Server 2008.
            // A failed connect writes the shared one line (harness-edits.md, "Script-scope preferences and the one-line connect warning", point 5).
            // Correction azure-refusal: the pin's connect lacks -AzureUnsupported, but DBCC HELP applies to SQL Server and Azure SQL Managed Instance only
            // (https://learn.microsoft.com/sql/t-sql/database-console-commands/dbcc-help-transact-sql), so Azure SQL Database is refused as -AzureUnsupported does.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;

            object? results;
            try
            {
                WriteMessage(MessageLevel.Verbose, "Query to run: " + PinnedBatchText());
                results = RunQuery(server);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction("Failure", target: server, errorRecord: new ErrorRecord(failure, "dbatools_Get-DbaDbccHelp", ErrorCategory.NotSpecified, server), continueLoop: true);
                continue;
            }

            PSObject result = new();
            result.Properties.Add(new PSNoteProperty("Operation", Statement ?? ""));
            result.Properties.Add(new PSNoteProperty("Cmd", "DBCC HELP(" + Statement + ")"));
            result.Properties.Add(new PSNoteProperty("Output", results));
            WriteObject(result);
        }
    }

    // PS: $server | Invoke-DbaQuery -Query $query -MessagesToOutput. It reuses the server's connection unless that connection runs as another
    // Windows user, and then opens its own, non-pooled. Called without -EnableException, so a failure stays its warning under this command's.
    private object? RunQuery(Server server)
    {
        DbaInstanceParameter source = new((object)server);
        ServerConnection serverConnection = server.ConnectionContext;
        bool reuse = PsString.Eq(serverConnection.ConnectAsUserName, "");
        ServerConnection connection = serverConnection;
        List<object> output = new();
        try
        {
            if (!reuse)
            {
                connection = serverConnection.Copy();
                connection.NonPooledConnection = true;
                connection.StatementTimeout = serverConnection.StatementTimeout;
                connection.Connect();
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction(QueryRunner, "Failure", target: source, errorRecord: new ErrorRecord(failure, QueryRunner, ErrorCategory.NotSpecified, null));
            return null;
        }

        SqlConnection sqlConnection = connection.SqlConnectionObject;
        sqlConnection.FireInfoMessageEventOnUserErrors = false;
        SqlInfoMessageEventHandler capture = (_, printed) => output.Add(printed.ToString());
        sqlConnection.InfoMessage += capture;
        try
        {
            using SqlCommand command = sqlConnection.CreateCommand();
            BindBatch(command);
            command.CommandTimeout = connection.StatementTimeout;
            using SqlDataAdapter adapter = new(command);
            DataSet tables = new();
            SetActiveCommand(command);
            adapter.Fill(tables);
            if (tables.Tables.Count != 0)
            {
                foreach (DataRow row in tables.Tables[0].Rows)
                    output.Add(row);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: Resolve-SqlError in the nested query drops the failure under the -ErrorAction this command was given.
            if (!QuietFailure())
            {
                WarnNestedStopFunction(QueryRunner, String.Format("[{0}] Failed during execution", source), target: source,
                    errorRecord: new ErrorRecord(failure, QueryRunner, ErrorCategory.NotSpecified, null));
            }
        }
        finally
        {
            SetActiveCommand(null);
            sqlConnection.InfoMessage -= capture;
            if (!reuse)
                connection.Disconnect();
        }
        return PipelineValue(output);
    }

    // Correction include-undocumented-false: the switch's value, where the pin's Test-Bound also counts -IncludeUndocumented:$false.
    private string TraceFlagText()
    {
        return IncludeUndocumented.ToBool() ? "DBCC TRACEON (2588) WITH NO_INFOMSGS;" : "";
    }

    // The batch as the pin writes it, for its verbose line. It runs only where it holds no caller text; see BindBatch.
    private string PinnedBatchText()
    {
        return TraceFlagText() + HelpTemplate.Replace("#statement#", Statement);
    }

    // Correction statement-injection: DBCC HELP reads the name from a variable, so no caller text reaches the batch. A bare ? and
    // an empty statement are not a name: their pinned text holds nothing of the caller's and keeps the engine's error for each.
    private void BindBatch(SqlCommand command)
    {
        string text = (Statement ?? "").Trim();
        if (text.Length == 0 || text == "?")
        {
            command.CommandText = TraceFlagText() + HelpTemplate.Replace("#statement#", text);
            return;
        }
        command.CommandText = TraceFlagText() + BoundHelp;
        command.Parameters.Add(new SqlParameter("@statement", SqlDbType.NVarChar) { Value = StatementName(text) });
    }

    // The name inside the forms the pin's batch read as one name: 'x', N'x', [x] and "x".
    private static string StatementName(string text)
    {
        char last = text[text.Length - 1];
        if (text.Length >= 2 && text[0] == '\'' && last == '\'')
            return text.Substring(1, text.Length - 2).Replace("''", "'");
        if (text.Length >= 3 && (text[0] == 'N' || text[0] == 'n') && text[1] == '\'' && last == '\'')
            return text.Substring(2, text.Length - 3).Replace("''", "'");
        if (text.Length >= 2 && text[0] == '[' && last == ']')
            return text.Substring(1, text.Length - 2).Replace("]]", "]");
        if (text.Length >= 2 && text[0] == '"' && last == '"')
            return text.Substring(1, text.Length - 2).Replace("\"\"", "\"");
        return text;
    }

    private bool QuietFailure()
    {
        return MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? bound)
            && bound is ActionPreference.SilentlyContinue or ActionPreference.Ignore;
    }

    // PS: an assignment from a pipeline holds $null, the one item, or an array of the items.
    private static object? PipelineValue(List<object> output)
    {
        if (output.Count < 2)
            return output.Count == 0 ? null : output[0];
        return output.ToArray();
    }
}
