#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Port of public/Disable-DbaDbEncryption.ps1. The nested Get-DbaDatabase (SqlInstance feeder) and
// Remove-DbaDbEncryptionKey (key drop) calls are done here in C#, each reporting its failures the way the nested
// function does: without -EnableException, because the pinned function never passes it on.
/// <summary>Disables Transparent Data Encryption (TDE) on SQL Server databases and removes encryption keys</summary>
[Cmdlet(VerbsLifecycle.Disable, "DbaDbEncryption", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "Default")]
public sealed class DisableDbaDbEncryptionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Specifies which databases to disable TDE encryption on.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Accepts database objects from Get-DbaDatabase for pipeline processing.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public SmoDatabase[]? InputObject { get; set; }

    /// <summary>Prevents the Database Encryption Key (DEK) from being automatically dropped after disabling TDE.</summary>
    [Parameter]
    public SwitchParameter NoEncryptionKeyDrop { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Write-ProgressHelper called from Disable-DbaDbEncryption: the default branch of its Activity switch.
    private const string ProgressActivity = "Executing Disable-DbaDbEncryption";

    // Get-DbaDatabase's default -Status values; a database is listed when any of its status flags is one of them.
    private const DatabaseStatus ListedStatus = DatabaseStatus.EmergencyMode | DatabaseStatus.Normal |
        DatabaseStatus.Offline | DatabaseStatus.Recovering | DatabaseStatus.RecoveryPending | DatabaseStatus.Restoring |
        DatabaseStatus.Standby | DatabaseStatus.Suspect;

    protected override void ProcessRecord()
    {
        // The pinned process block has no Test-FunctionInterrupt: each record runs its own checks.
        IEnumerable<SmoDatabase> databases = InputObject ?? Array.Empty<SmoDatabase>();
        if (LanguagePrimitives.IsTrue(SqlInstance))
        {
            if (!LanguagePrimitives.IsTrue(Database))
            {
                StopFunction("You must specify Database or ExcludeDatabase when using SqlInstance");
                return;
            }
            // PS: $InputObject = Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
            databases = ListDatabases();
        }

        foreach (SmoDatabase? db in databases)
        {
            if (db is null)
                continue;
            CancellationToken.ThrowIfCancellationRequested();
            DisableEncryption(db);
        }
    }

    private void DisableEncryption(SmoDatabase db)
    {
        Server server = db.Parent;
        // The pinned texts as they are: the drop warning goes with -NoEncryptionKeyDrop.
        string action = NoEncryptionKeyDrop.ToBool()
            ? String.Format("Disabling encryption on {0} will also drop the database encryption key. Continue?", db.Name)
            : String.Format("Disabling encryption on {0}", db.Name);
        if (!ShouldProcess(server.Name, action))
            return;

        try
        {
            // Correction azure-tde-wait: on Azure SQL Database SMO never fills the key's EncryptionState (manager probe
            // 3c192283), so the pinned loop never ended there; the wait reads the state the engine reports instead, and
            // the service-managed key is not dropped.
            bool azureDatabase = server.DatabaseEngineEdition == DatabaseEngineEdition.SqlDatabase;
            db.EncryptionEnabled = false;
            db.Alter();
            int stepCounter = 0;
            DatabaseEncryptionState state;
            try
            {
                do
                {
                    // PS: Start-Sleep 1, which Ctrl+C interrupts.
                    CancellationToken.WaitHandle.WaitOne(1000);
                    CancellationToken.ThrowIfCancellationRequested();
                    db.Refresh();
                    WriteStep(stepCounter++, String.Format("Disabling encryption for {0} on {1}", db.Name, server.Name));
                    if (stepCounter == 100)
                        stepCounter = 0;
                    state = azureDatabase ? EngineEncryptionState(db) : db.DatabaseEncryptionKey.EncryptionState;
                    WriteMessage(MessageLevel.Verbose, String.Format("Database state for {0} on {1}: {2}", db.Name, server.Name, state));
                }
                while (!IsDecrypted(state));
            }
            finally
            {
                CompleteProgress();
            }

            if (!NoEncryptionKeyDrop.ToBool())
            {
                if (azureDatabase)
                {
                    // DROP DATABASE ENCRYPTION KEY does not apply to Azure SQL Database, whose key is service-managed.
                    WriteMessage(MessageLevel.Verbose, String.Format("Azure SQL Database manages the database encryption key of {0}; it is not dropped", db.Name));
                }
                else
                {
                    // PS: $null = $db.DatabaseEncryptionKey | Remove-DbaDbEncryptionKey
                    RemoveEncryptionKey(db.DatabaseEncryptionKey);
                }
            }

            // PS: $db | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, 'Name as DatabaseName', EncryptionEnabled
            PSObject result = PSObject.AsPSObject(db);
            result.Properties.Remove("DatabaseName");
            OutputHelper.AddAliasProperty(result, "DatabaseName", "Name");
            OutputHelper.SetDefaultDisplayPropertySet(result, "ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "EncryptionEnabled");
            WriteObject(result);
        }
        catch (Exception failure) when (failure is not PipelineStoppedException && failure is not OperationCanceledException)
        {
            StopFunction("Failure", errorRecord: RecordOf(failure), continueLoop: true);
        }
    }

    // PS: while ($db.DatabaseEncryptionKey.EncryptionState -notin "Unencrypted", "None")
    private static bool IsDecrypted(DatabaseEncryptionState state)
    {
        return state == DatabaseEncryptionState.Unencrypted || state == DatabaseEncryptionState.None;
    }

    // The database's encryption_state in sys.dm_database_encryption_keys, whose values are DatabaseEncryptionState's;
    // no row means no key (0, None).
    private static DatabaseEncryptionState EngineEncryptionState(SmoDatabase db)
    {
        System.Data.DataSet result = db.ExecuteWithResults("SELECT encryption_state FROM sys.dm_database_encryption_keys WHERE database_id = DB_ID()");
        if (result.Tables.Count == 0 || result.Tables[0].Rows.Count == 0)
            return DatabaseEncryptionState.None;
        return (DatabaseEncryptionState)Convert.ToInt32(result.Tables[0].Rows[0][0], System.Globalization.CultureInfo.InvariantCulture);
    }

    // Remove-DbaDbEncryptionKey's process block for the one piped key. Its own ShouldProcess runs under the caller's
    // WhatIf and Confirm preferences, as a nested advanced function inherits them.
    private void RemoveEncryptionKey(DatabaseEncryptionKey key)
    {
        SmoDatabase keyDatabase = key.Parent;
        Server keyServer = keyDatabase.Parent;
        if (!ShouldProcess(keyServer.Name, "Dropping the encryption key for database " + keyDatabase.ToString()))
            return;
        try
        {
            // PS: Invoke-DbaQuery -SqlInstance $server -Database $db.Name -Query "DROP DATABASE ENCRYPTION KEY" -EnableException
            keyDatabase.ExecuteNonQuery("DROP DATABASE ENCRYPTION KEY");
            WriteAttributedMessage("Remove-DbaDbEncryptionKey", MessageLevel.Verbose,
                String.Format("Successfully removed encryption key from the {0} database on {1}", keyDatabase.ToString(), keyServer.ToString()));
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: Stop-Function -Message "Failed to drop encryption key from $($db.Name) on $($server.Name)." -Target $db -ErrorRecord $_ -Continue
            WarnNestedStopFunction("Remove-DbaDbEncryptionKey", String.Format("Failed to drop encryption key from {0} on {1}.", keyDatabase.Name, keyServer.Name),
                keyDatabase, RecordOf(failure), ErrorCategory.NotSpecified);
        }
    }

    // Get-DbaDatabase -SqlInstance -SqlCredential -Database with every other parameter at its default: per instance, the
    // named databases (Name -in $Database) in sys.databases order, decorated with the instance triple.
    private List<SmoDatabase> ListDatabases()
    {
        List<SmoDatabase> listed = new();
        foreach (DbaInstanceParameter instance in SqlInstance!)
        {
            CancellationToken.ThrowIfCancellationRequested();
            Server server;
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "Starting process block");
            try
            {
                server = ConnectionService.GetServer(new SmoConnectionRequest
                {
                    Instance = instance,
                    SqlCredential = SqlCredential,
                    BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                    MessageCallback = (level, message) => WriteAttributedMessage("Connect-DbaInstance", level, message)
                });
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // PS (Get-DbaDatabase): Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                // The shared helper puts the record in $error and the caller's -ErrorVariable, as the pinned nested call does.
                ErrorRecord record = new(failure, "dbatools_Get-DbaDatabase", ErrorCategory.ConnectionError, instance);
                WarnNestedStopFunction("Get-DbaDatabase", "Failure", instance, record, ErrorCategory.ConnectionError);
                continue;
            }
            SetActiveConnection(server.ConnectionContext);
            WriteAttributedMessage("Connect-DbaInstance", MessageLevel.Debug, "We are finished with this instance");

            bool azure = server.DatabaseEngineType == DatabaseEngineType.SqlAzureDatabase;
            List<SmoDatabase> named = new();
            foreach (SmoDatabase db in server.Databases)
            {
                if (!IsNamed(db.Name))
                    continue;
                // The status filter applies to SQL Server only; the Azure branch has none.
                if (!azure && (db.Status & ListedStatus) == 0)
                    continue;
                named.Add(db);
            }
            named.Sort((first, second) => first.ID.CompareTo(second.ID));

            foreach (SmoDatabase db in named)
            {
                PSObject decorated = PSObject.AsPSObject(db);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                    decorated.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(decorated, server);
                listed.Add(db);
            }
        }
        return listed;
    }

    // $_.Name -in $Database
    private bool IsNamed(string name)
    {
        foreach (string? candidate in Database!)
        {
            if (String.Equals(candidate, name, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    private static ErrorRecord RecordOf(Exception failure)
    {
        if (failure is IContainsErrorRecord contained && contained.ErrorRecord is not null)
            return contained.ErrorRecord;
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // Write-ProgressHelper -StepNumber $step -Message $message -TotalSteps 100: bar 0, percent = step.
    private void WriteStep(int step, string message)
    {
        ProgressRecord record = new(0, ProgressActivity, message);
        record.PercentComplete = Math.Min(100, Math.Max(0, step));
        WriteProgress(record);
    }

    // Write-ProgressHelper -Completed
    private void CompleteProgress()
    {
        ProgressRecord record = new(0, ProgressActivity, "Processing");
        record.RecordType = ProgressRecordType.Completed;
        WriteProgress(record);
    }
}
