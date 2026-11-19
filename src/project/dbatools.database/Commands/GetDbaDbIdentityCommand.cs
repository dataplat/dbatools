#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaDbIdentity.ps1 at refs/pins/dbatools-2026-10-22: the connect, the database selection, DBCC CHECKIDENT NORESEED for each
// table through what the nested Invoke-DbaQuery does with -MessagesToOutput, and the values read from the message DBCC prints.
/// <summary>Retrieves current identity values from tables without reseeding using DBCC CHECKIDENT</summary>
/// <para>
/// Executes DBCC CHECKIDENT with the NORESEED option to retrieve current identity seed and column values from specified tables without modifying anything. This provides a safe way to inspect identity column status across multiple tables, databases, and instances simultaneously.
/// </para>
/// <para>
/// DBAs use this when troubleshooting identity gaps, planning bulk operations, or auditing identity column usage before performing maintenance tasks. Unlike running DBCC CHECKIDENT manually, this command structures the output into readable PowerShell objects that show both the current identity value and the actual highest value in the column.
/// </para>
/// <para>
/// The NORESEED option ensures no changes are made to your tables - it's purely informational. The function parses the DBCC output to extract specific identity metrics, making it ideal for scripted monitoring and reporting workflows.
/// </para>
/// <para>
/// Read more:
/// - https://docs.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkident-transact-sql
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaDbIdentity -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Table 'Production.ScrapReason'
/// </code>
/// <para>
/// Connects to AdventureWorks2014 on instance SqlServer2017 using Windows Authentication and runs the command DBCC CHECKIDENT('Production.ScrapReason', NORESEED) to return the current identity value.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $cred = Get-Credential sqladmin
/// PS C:\&gt; 'Sql1','Sql2/sqlexpress' | Get-DbaDbIdentity -SqlCredential $cred -Database AdventureWorks2014 -Table 'Production.ScrapReason'
/// </code>
/// <para>
/// Connects to AdventureWorks2014 on instances Sql1 and Sql2/sqlexpress using sqladmin credential and runs the command DBCC CHECKIDENT('Production.ScrapReason', NORESEED) to return the current identity value.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; $query = "SELECT QUOTENAME(SCHEMA_NAME(t.schema_id)) + '.' + QUOTENAME(t.name) AS TableName FROM sys.columns c INNER JOIN sys.tables t ON t.object_id = c.object_id WHERE is_identity = 1 AND is_memory_optimized = 0"
/// PS C:\&gt; $IdentityTables = Invoke-DbaQuery -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Query $query -As SingleValue
/// PS C:\&gt; Get-DbaDbIdentity -SqlInstance SQLServer2017 -Database AdventureWorks2014 -Table $IdentityTables
/// </code>
/// <para>
/// Checks the current identity value for all non memory optimized tables with an Identity in the AdventureWorks2014 database on the SQLServer2017 instance.
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
/// <seealso href="https://dbatools.io/Get-DbaDbIdentity" />
[Cmdlet(VerbsCommon.Get, "DbaDbIdentity", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(PSObject))]
public sealed class GetDbaDbIdentityCommand : DbaInstanceCmdlet
{
    // PS: the name the nested query's messages carry.
    private const string QueryRunner = "Invoke-DbaQuery";

    // PS begin block: $stringBuilder.Append(...), constant text.
    private const string Template = "DBCC CHECKIDENT(#options#, NORESEED)";

    // Each value DBCC prints: a whole number, or NULL for a table that has held no row.
    private static readonly Regex ReportedValue = new("-?[0-9]+|NULL", RegexOptions.CultureInvariant);

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
    /// Specifies which databases to check for identity column values. If not specified, all accessible databases on the instance are processed.
    /// Use this to focus on specific databases when you don't need identity information from every database on the server.
    /// </para>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <para>
    /// Specifies the table names to check for current identity seed and column values. Accepts schema-qualified names like 'Production.ScrapReason'.
    /// This parameter is required since DBCC CHECKIDENT must target specific tables. Use a query against sys.columns to find all tables with identity columns if needed.
    /// </para>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    /// <summary>Reports the identity values of each table in each selected database of each instance.</summary>
    protected override void ProcessRecord()
    {
        // PS: no Test-FunctionInterrupt here, so every piped instance gets this warning.
        if (!TestBound(nameof(Table)))
        {
            StopFunction("You must specify a table to execute against using -Table");
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            WriteMessage(MessageLevel.Verbose, String.Format("Attempting Connection to {0}", instance));
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            foreach (SmoDatabase db in SelectDatabases(server))
            {
                WriteMessage(MessageLevel.Verbose, String.Format("Processing {0} on {1}", db, instance));

                if (!db.IsAccessible)
                {
                    StopFunction(String.Format("The database {0} is not accessible. Skipping.", db), continueLoop: true);
                    continue;
                }

                foreach (string table in Table ?? Array.Empty<string>())
                    CheckTable(server, db, instance, table);
            }
        }
    }

    // PS: $dbs = $server.Databases, then under if ($Database): Where-Object Name -In $Database
    private List<SmoDatabase> SelectDatabases(Server server)
    {
        bool filtered = LanguagePrimitives.IsTrue(Database);
        List<SmoDatabase> selected = new();
        foreach (SmoDatabase db in server.Databases)
        {
            if (!filtered || PsString.In(db.Name, Database!))
                selected.Add(db);
        }
        return selected;
    }

    private void CheckTable(Server server, SmoDatabase db, DbaInstanceParameter instance, string table)
    {
        string query = Template;
        List<string> messages = new();
        string? identityValue = null;
        string? columnValue = null;
        try
        {
            query = Template.Replace("#options#", TableLiteral(TableIdentifier(table)));
            if (ShouldProcess(server.Name, String.Format("Execute the command {0} against {1}", query, instance)))
            {
                WriteMessage(MessageLevel.Verbose, "Query to run: " + query);
                messages = RunCheck(server, db, query);
                if (messages.Count > 0)
                {
                    // Correction message-language: the pin's word positions hold only in English, the values read the same in any language.
                    MatchCollection values = ReportedValue.Matches(messages[0]);
                    if (values.Count > 1)
                    {
                        identityValue = values[0].Value;
                        columnValue = values[1].Value;
                    }
                }
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: Stop-Function ... -ErrorRecord $_ -Exception $_.Exception -Continue; two spaces after "running" in the pinned text.
            StopFunction(String.Format("Error running  {0} against {1}", query, db), target: instance,
                errorRecord: new ErrorRecord(failure, "Get-DbaDbIdentity", ErrorCategory.NotSpecified, null), exception: failure, continueLoop: true);
            return;
        }

        if (!ShouldProcess("console", "Outputting object"))
            return;

        PSObject result = new();
        OutputHelper.AddInstanceProperties(result, server);
        result.Properties.Add(new PSNoteProperty("Database", db.Name));
        result.Properties.Add(new PSNoteProperty("Table", table));
        result.Properties.Add(new PSNoteProperty("Cmd", query));
        result.Properties.Add(new PSNoteProperty("IdentityValue", identityValue));
        result.Properties.Add(new PSNoteProperty("ColumnValue", columnValue));
        result.Properties.Add(new PSNoteProperty("Output", PipelineValue(messages)));
        WriteObject(result);
    }

    // PS: the bracketed name Get-ObjectNameParts splits out, or the text as given when it splits nothing.
    private static string TableIdentifier(string table)
    {
        ObjectNameParser.Split(table, out string? schema, out string? name);
        if (String.IsNullOrEmpty(name))
            return table;
        string escapedName = name!.Replace("]", "]]");
        if (String.IsNullOrEmpty(schema))
            return String.Format("[{0}]", escapedName);
        return String.Format("[{0}].[{1}]", schema!.Replace("]", "]]"), escapedName);
    }

    // Correction quoted-table-name: the text stays one string literal whatever it holds. Correction name-outside-code-page: N'' keeps a
    // character the varchar literal would lose; an ASCII name, which it cannot lose, keeps the pinned statement.
    private static string TableLiteral(string identifier)
    {
        string quoted = identifier.Replace("'", "''");
        foreach (char character in quoted)
        {
            if (character > 127)
                return String.Format("N'{0}'", quoted);
        }
        return String.Format("'{0}'", quoted);
    }

    // PS: $server | Invoke-DbaQuery -Query $query -Database $db.Name -MessagesToOutput. It keeps a connection already in that database and
    // otherwise opens its own there, non-pooled. Called without -EnableException, so a failure stays its warning under this command's -EnableException.
    private List<string> RunCheck(Server server, SmoDatabase db, string query)
    {
        DbaInstanceParameter source = new((object)server);
        ServerConnection serverConnection = server.ConnectionContext;
        bool sameDatabase = PsString.Eq(serverConnection.DatabaseName, db.Name) && PsString.Eq(serverConnection.ConnectAsUserName, "");
        ServerConnection connection = serverConnection;
        bool opened = false;
        List<string> messages = new();
        try
        {
            if (!sameDatabase)
            {
                ServerConnection copy = serverConnection.Copy();
                copy.NonPooledConnection = true;
                connection = copy.GetDatabaseConnection(db.Name, false);
                connection.StatementTimeout = serverConnection.StatementTimeout;
            }
            if (!connection.IsOpen)
            {
                connection.Connect();
                opened = true;
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction(QueryRunner, "Failure", target: source, errorRecord: new ErrorRecord(failure, QueryRunner, ErrorCategory.NotSpecified, null));
            return messages;
        }

        SqlConnection sqlConnection = connection.SqlConnectionObject;
        SqlInfoMessageEventHandler capture = (_, printed) =>
        {
            foreach (Microsoft.Data.SqlClient.SqlError error in printed.Errors)
                messages.Add(error.Message);
        };
        sqlConnection.InfoMessage += capture;
        try
        {
            using SqlCommand command = sqlConnection.CreateCommand();
            command.CommandText = query;
            command.CommandTimeout = connection.StatementTimeout;
            SetActiveCommand(command);
            command.ExecuteNonQuery();
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
            if (!sameDatabase || opened)
                connection.Disconnect();
        }
        return messages;
    }

    private bool QuietFailure()
    {
        return MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? bound)
            && bound is ActionPreference.SilentlyContinue or ActionPreference.Ignore;
    }

    // PS: an assignment from a pipeline holds $null, the one line, or an array of the lines.
    private static object? PipelineValue(List<string> messages)
    {
        if (messages.Count < 2)
            return messages.Count == 0 ? null : messages[0];
        return messages.ConvertAll<object>(message => message).ToArray();
    }
}
