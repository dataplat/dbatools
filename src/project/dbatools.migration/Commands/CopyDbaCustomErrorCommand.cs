#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Migrates custom error messages and their language translations between SQL Server instances
/// </summary>
/// <para>
/// Copies user-defined error messages from the source server's sys.messages system catalog to one or more destination servers. This is essential when migrating applications that rely on custom error numbers and messages, or when standardizing error handling across multiple SQL Server environments.
/// </para>
/// <para>
/// Custom errors created with sp_addmessage are automatically discovered and migrated, including all language translations. The English (us_english) version is always created first since SQL Server requires it as the base language before adding translations.
/// </para>
/// <para>
/// By default, existing custom errors on the destination are skipped to prevent conflicts. Use -Force to overwrite existing errors. If you drop the English version of a custom error, all language translations for that error ID are automatically dropped as well.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster
/// </code>
/// <para>
/// Copies all server custom errors from sqlserver2014a to sqlcluster using Windows credentials. If custom errors with the same name exist on sqlcluster, they will be skipped.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaCustomError -Source sqlserver2014a -SourceSqlCredential $scred -Destination sqlcluster -DestinationSqlCredential $dcred -CustomError 60000 -Force
/// </code>
/// <para>
/// Copies only the custom error with ID number 60000 from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster -ExcludeCustomError 60000 -Force
/// </code>
/// <para>
/// Copies all the custom errors found on sqlserver2014a except the custom error with ID number 60000 to sqlcluster. If a custom error with the same name exists on sqlcluster, it will be updated because -Force was used.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Copy-DbaCustomError -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force
/// </code>
/// <para>
/// Shows what would happen if the command were executed using force.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: Migration, CustomError
/// Author: Chrissy LeMaire (@cl), netnerds.net
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// <para>
/// Requires: sysadmin access on SQL Servers
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Copy-DbaCustomError" />
[Cmdlet(VerbsCommon.Copy, "DbaCustomError", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaCustomErrorCommand : DbaBaseCmdlet
{
    /// <para>
    /// Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.
    /// </para>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

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
    public PSCredential? SourceSqlCredential { get; set; }

    /// <para>
    /// Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.
    /// </para>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <para>
    /// Specifies which custom error message IDs to migrate from the source server. Only the specified error numbers will be copied to the destination.
    /// Use this when you need to migrate specific custom errors rather than all of them, such as when standardizing only certain application error codes across environments.
    /// </para>
    [Parameter(Position = 4)]
    public object[]? CustomError { get; set; }

    /// <para>
    /// Specifies which custom error message IDs to skip during migration. All custom errors except the excluded ones will be copied.
    /// Use this when you want to migrate most custom errors but exclude problematic ones, or when certain error IDs are environment-specific and shouldn't be copied.
    /// </para>
    [Parameter(Position = 5)]
    public object[]? ExcludeCustomError { get; set; }

    /// <para>
    /// Overwrites existing custom errors on the destination server by dropping and recreating them with source values.
    /// Use this when you need to update custom error messages that have changed on the source, or when synchronizing error definitions across environments.
    /// </para>
    [Parameter]
    public SwitchParameter Force { get; set; }

    private Server? _source;
    private readonly List<UserDefinedMessage> _messages = new List<UserDefinedMessage>();

    protected override void BeginProcessing()
    {
        _source = Connect(Source, SourceSqlCredential, false);
        if (_source is null) return;
        foreach (UserDefinedMessage message in _source.UserDefinedMessages)
            if (string.Equals(message.Language, "us_english", StringComparison.OrdinalIgnoreCase)) _messages.Add(message);
        foreach (UserDefinedMessage message in _source.UserDefinedMessages)
            if (!string.Equals(message.Language, "us_english", StringComparison.OrdinalIgnoreCase)) _messages.Add(message);
    }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || _source is null) return;
        foreach (DbaInstanceParameter destination in Destination)
        {
            Server? server = Connect(destination, DestinationSqlCredential, true);
            if (server is null) continue;
            foreach (UserDefinedMessage message in _messages)
            {
                CancellationToken.ThrowIfCancellationRequested();
                int id = message.ID;
                if ((LanguagePrimitives.IsTrue(CustomError) && !Includes(CustomError, id)) || Includes(ExcludeCustomError, id)) continue;
                string language = message.Language;
                DateTime timestamp = DateTime.Now;
                UserDefinedMessage? existing = FindCurrent(server, id, language);
                if (existing is not null)
                {
                    if (!Force)
                    {
                        string action = string.Format("Custom error {0} {1} exists at destination. Use -Force to drop and migrate.", id, language);
                        if (Approve(destination, action))
                        {
                            Emit(server, message, timestamp, "Skipped", "Already exists on destination");
                            WriteMessage(MessageLevel.Verbose, action);
                        }
                        continue;
                    }
                    if (Approve(destination, string.Format("Dropping custom error {0} {1} and recreating", id, language)))
                    {
                        try
                        {
                            WriteMessage(MessageLevel.Verbose, string.Format("Dropping custom error {0} (drops all languages for custom error {0})", id));
                            // Bypass SMO PostDrop, which can throw after SQL has already removed every translation.
                            string dropLanguage = string.Equals(language, "us_english", StringComparison.OrdinalIgnoreCase) ? "all" : language;
                            server.ConnectionContext.ExecuteNonQuery(string.Format(CultureInfo.InvariantCulture,
                                "EXEC master.sys.sp_dropmessage @msgnum = {0}, @lang = N'{1}';", id, dropLanguage.Replace("'", "''")));
                        }
                        catch (PipelineStoppedException) { throw; }
                        catch (Exception ex)
                        {
                            Emit(server, message, timestamp, "Failed", ex.Message);
                            WriteMessage(MessageLevel.Verbose, string.Format("Issue dropping custom error {0} {1} on {2} | {3}", id, language, destination, ex.Message));
                            continue;
                        }
                    }
                }
                if (!Approve(destination, string.Format("Creating custom error {0} {1}", id, language))) continue;
                try
                {
                    WriteMessage(MessageLevel.Verbose, string.Format("Copying custom error {0} {1}", id, language));
                    StringBuilder script = new StringBuilder();
                    foreach (string? batch in message.Script()) script.AppendLine(batch);
                    string sql = script.ToString();
                    WriteMessage(MessageLevel.Debug, sql);
                    server.ConnectionContext.ExecuteNonQuery(sql);
                    Emit(server, message, timestamp, "Successful", null);
                }
                catch (PipelineStoppedException) { throw; }
                catch (Exception ex)
                {
                    Emit(server, message, timestamp, "Failed", ex.Message);
                    WriteMessage(MessageLevel.Verbose, string.Format("Issue creating custom error {0} {1} on {2} | {3}", id, language, destination, ex.Message));
                }
            }
        }
    }

    private UserDefinedMessage? FindCurrent(Server server, int id, string language)
    {
        try
        {
            server.UserDefinedMessages.Refresh();
            return server.UserDefinedMessages[id, language];
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            // caller-try: terminate -- current ID/language existence is required before any drop/create decision.
            ThrowTerminatingError(new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.NotSpecified, server)); // style-ok: cs-raw-streams source collection discovery has no Stop-Function catch
            return null;
        }
    }

    private static bool Includes(object[]? filter, int id)
    {
        foreach (object value in filter ?? Array.Empty<object>())
            if (LanguagePrimitives.Equals(id, value, true)) return true;
        return false;
    }

    private Server? Connect(DbaInstanceParameter target, PSCredential? credential, bool continueLoop)
    {
        SmoConnectionRequest request = new SmoConnectionRequest
        {
            Instance = target, SqlCredential = credential, MinimumVersion = 9, AzureUnsupported = true,
            BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential", "MinimumVersion", "AzureUnsupported" },
            MessageCallback = (level, text) => WriteAttributedMessage("Connect-DbaInstance", level, text)
        };
        WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
        try
        {
            Server server = ConnectionService.GetServer(request);
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (PipelineStoppedException) { throw; }
        catch (Exception ex)
        {
            ErrorRecord record = new ErrorRecord(ex, "dbatools_Copy-DbaCustomError", ErrorCategory.ConnectionError, target);
            StopFunction("Failure", errorRecord: record, target: target, category: ErrorCategory.ConnectionError, continueLoop: continueLoop);
            return null;
        }
    }

    private bool Approve(DbaInstanceParameter target, string action)
    {
        return Force ? NativeConfirmation.WithConfirmationSuppressed(SessionState, () => ShouldProcess(target.ToString(), action))
            : ShouldProcess(target.ToString(), action);
    }

    private void Emit(Server destination, UserDefinedMessage message, DateTime timestamp, string status, string? notes)
    {
        PSObject result = new PSObject();
        string[] properties = { "SourceServer", "DestinationServer", "Type", "Name", "Status", "Notes", "DateTime" };
        object?[] values = { _source!.Name, destination.Name, "Custom error", message, status, notes, new DbaDateTime(timestamp) };
        for (int i = 0; i < properties.Length; i++) result.Properties.Add(new PSNoteProperty(properties[i], values[i]));
        OutputHelper.InsertTypeName(result, "MigrationObject");
        OutputHelper.SetDefaultDisplayPropertySet(result, "DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes");
        WriteObject(result);
    }
}
