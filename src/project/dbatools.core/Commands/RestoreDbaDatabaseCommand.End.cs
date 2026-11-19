#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

public sealed partial class RestoreDbaDatabaseCommand
{
    protected override void EndProcessing()
    {
        if (Interrupted || _skipEnd)
        {
            return;
        }
        // ($BackupHistory.Database | Sort-Object -Unique).count -gt 1 -and ('' -ne $DatabaseName)
        HashSet<string> uniqueDatabases = new(StringComparer.OrdinalIgnoreCase);
        foreach (object? history in _backupHistory)
            uniqueDatabases.Add(RestoreUtility.PsStringify(PsProperty.Get(history, "Database")));
        bool databaseNameTruthy = false;
        foreach (object? name in _databaseName ?? Array.Empty<object>())
        {
            if (!PsOps.Eq(name, ""))
            {
                databaseNameTruthy = true;
                break;
            }
        }
        if (uniqueDatabases.Count > 1 && databaseNameTruthy)
        {
            StopFunction("Multiple Databases' backups passed in, but only 1 name to restore them under. Stopping as cannot work out how to proceed", category: ErrorCategory.InvalidArgument);
            return;
        }
        if (!ParameterSetName.StartsWith("Restore", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (_backupHistory.Count == 0 && _restoreInstance!.VersionMajor != 8)
        {
            WriteMessage(MessageLevel.Warning, "No backups passed through. \n This could mean the SQL instance cannot see the referenced files, the file's headers could not be read or some other issue");
            return;
        }
        WriteMessage(MessageLevel.Verbose, $"Processing DatabaseName - {RestoreUtility.PsStringify(_databaseName)}");
        List<object?> filteredBackupHistory = new();
        if (TestBound("GetBackupInformation"))
        {
            WriteMessage(MessageLevel.Verbose, $"Setting {GetBackupInformation} to BackupHistory");
            // PS builds this one with += accumulation, so it is ALWAYS an array (unlike the
            // pipeline-assigned globals below — cross-model review 2026-07-07 finding B5).
            SessionState.InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__name, $__value) Set-Variable -Name $__name -Value $__value -Scope Global"), null, GetBackupInformation, _backupHistory.ToArray());
        }
        if (StopAfterGetBackupInformation.ToBool())
        {
            return;
        }
        string pathSep = RestoreUtility.GetPathSep(_restoreInstance);
        Hashtable formatParms = new()
        {
            ["DataFileDirectory"] = DestinationDataDirectory,
            ["LogFileDirectory"] = DestinationLogDirectory,
            ["DestinationFileStreamDirectory"] = DestinationFileStreamDirectory,
            ["DatabaseFileSuffix"] = DestinationFileSuffix,
            ["DatabaseFilePrefix"] = DestinationFilePrefix,
            ["DatabaseNamePrefix"] = RestoredDatabaseNamePrefix,
            ["ReplaceDatabaseName"] = _databaseName,
            ["Continue"] = Continue.ToBool(),
            ["ReplaceDbNameInFile"] = ReplaceDbNameInFile.ToBool(),
            ["FileMapping"] = FileMapping,
            ["PathSep"] = pathSep
        };
        List<object?> formatted = new();
        foreach (PSObject item in NestedCommand.Invoke(this, "Format-DbaBackupInformation", formatParms, _backupHistory.ToArray()))
            formatted.Add(item);
        _backupHistory.Clear();
        _backupHistory.AddRange(formatted);

        if (TestBound("FormatBackupInformation"))
        {
            SessionState.InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__name, $__value) Set-Variable -Name $__name -Value $__value -Scope Global"), null, FormatBackupInformation, ShapeForGlobal(_backupHistory));
        }
        if (StopAfterFormatBackupInformation.ToBool())
        {
            return;
        }
        if (VerifyOnly.ToBool())
        {
            filteredBackupHistory = new List<object?>(_backupHistory);
        }
        else
        {
            Hashtable selectParms = new()
            {
                ["RestoreTime"] = RestoreTime,
                // PS passes the never-assigned $IgnoreLogBackups here (note the trailing s) —
                // -IgnoreLogs:$null on the SCRIPT function bound FALSE. Compiled cmdlets bind
                // null-to-SwitchParameter as TRUE (engine inconsistency, lab-proven: null
                // dropped every log from composed restores), so the faithful translation of
                // the observable PS behavior is an explicit false.
                ["IgnoreLogs"] = false,
                ["IgnoreDiffs"] = IgnoreDiffBackup.ToBool(),
                ["ContinuePoints"] = _continuePoints,
                ["LastRestoreType"] = _lastRestoreType,
                ["DatabaseName"] = _databaseName
            };
            foreach (PSObject item in NestedCommand.Invoke(this, "Select-DbaBackupInformation", selectParms, _backupHistory.ToArray()))
                filteredBackupHistory.Add(item);
        }
        if (TestBound("SelectBackupInformation"))
        {
            WriteMessage(MessageLevel.Verbose, $"Setting {SelectBackupInformation} to FilteredBackupHistory");
            SessionState.InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__name, $__value) Set-Variable -Name $__name -Value $__value -Scope Global"), null, SelectBackupInformation, ShapeForGlobal(filteredBackupHistory));
        }
        if (StopAfterSelectBackupInformation.ToBool())
        {
            return;
        }
        try
        {
            WriteMessage(MessageLevel.Verbose, $"VerifyOnly = {PsBool.Text(VerifyOnly.ToBool())}");
            Hashtable testParms = new()
            {
                ["SqlInstance"] = _restoreInstance,
                ["WithReplace"] = _withReplace,
                ["Continue"] = Continue.ToBool(),
                ["VerifyOnly"] = VerifyOnly.ToBool(),
                ["EnableException"] = true,
                ["OutputScriptOnly"] = OutputScriptOnly.ToBool()
            };
            NestedCommand.Invoke(this, "Test-DbaBackupInformation", testParms, filteredBackupHistory.ToArray());
        }
        catch (Exception ex)
        {
            ErrorRecord record = new(ex, "dbatools_Restore-DbaDatabase", ErrorCategory.NotSpecified, null);
            StopFunction("Failure", errorRecord: record, continueLoop: true);
            return;
        }
        if (TestBound("TestBackupInformation"))
        {
            SessionState.InvokeCommand.InvokeScript(false, ScriptBlock.Create("param($__name, $__value) Set-Variable -Name $__name -Value $__value -Scope Global"), null, TestBackupInformation, ShapeForGlobal(filteredBackupHistory));
        }
        if (StopAfterTestBackupInformation.ToBool())
        {
            return;
        }
        List<object?> verified = new();
        List<object?> unverified = new();
        foreach (object? history in filteredBackupHistory)
        {
            // PS: Where-Object { $_.IsVerified -eq $True } / { $_.IsVerified -eq $False } —
            // entries with neither value fall into neither list, exactly like PS.
            if (PsOps.Eq(PsProperty.Get(history, "IsVerified"), true))
                verified.Add(history);
            else if (PsOps.Eq(PsProperty.Get(history, "IsVerified"), false))
                unverified.Add(history);
        }
        string dbVerified = JoinUniqueDatabases(verified);
        WriteMessage(MessageLevel.Verbose, $"{dbVerified} passed testing");
        if (verified.Count < filteredBackupHistory.Count)
        {
            string dbUnverified = JoinUniqueDatabases(unverified);
            // PS has no return after this Stop-Function: under -EnableException it throws,
            // otherwise the verified subset still restores below.
            StopFunction($"Database {dbUnverified} unable to be restored, see warnings for details");
        }
        if (ParameterSetName == "RestorePage")
        {
            HashSet<string> pageDatabases = new(StringComparer.OrdinalIgnoreCase);
            foreach (object? history in filteredBackupHistory)
                pageDatabases.Add(RestoreUtility.PsStringify(PsProperty.Get(history, "Database")));
            if (pageDatabases.Count != 1)
            {
                StopFunction("Must only 1 database passed in for Page Restore. Sorry");
                return;
            }
            else
            {
                _withReplace = false;
            }
        }
        WriteMessage(MessageLevel.Verbose, "Passing in to restore");

        if (ParameterSetName == "RestorePage" && _restoreInstance!.Edition.IndexOf("Enterprise", StringComparison.OrdinalIgnoreCase) < 0)
        {
            WriteMessage(MessageLevel.Verbose, "Taking Tail log backup for page restore for non-Enterprise");
            TakeTailBackup();
        }
        try
        {
            Hashtable restoreParms = new()
            {
                ["SqlInstance"] = _restoreInstance,
                ["WithReplace"] = _withReplace,
                ["RestoreTime"] = RestoreTime,
                ["StandbyDirectory"] = StandbyDirectory,
                ["NoRecovery"] = NoRecovery.ToBool(),
                ["Continue"] = Continue.ToBool(),
                ["OutputScriptOnly"] = OutputScriptOnly.ToBool(),
                ["BlockSize"] = BlockSize,
                ["MaxTransferSize"] = MaxTransferSize,
                ["BufferCount"] = BufferCount,
                ["KeepCDC"] = KeepCDC.ToBool(),
                ["ErrorBrokerConversations"] = ErrorBrokerConversations.ToBool(),
                ["VerifyOnly"] = VerifyOnly.ToBool(),
                ["PageRestore"] = PageRestore,
                ["StorageCredential"] = StorageCredential,
                ["KeepReplication"] = KeepReplication.ToBool(),
                ["StopMark"] = StopMark,
                ["StopAfterDate"] = StopAfterDate,
                ["StopBefore"] = StopBefore.ToBool(),
                ["StopAtLsn"] = StopAtLsn,
                ["ExecuteAs"] = ExecuteAs,
                ["Checksum"] = Checksum.ToBool(),
                ["Restart"] = Restart.ToBool(),
                ["EnableException"] = true
            };
            ForwardShouldProcessSwitches(restoreParms);
            NestedCommand.InvokeStreamed(this, "Invoke-DbaAdvancedRestore", restoreParms, verified);
        }
        catch (Exception ex)
        {
            ErrorRecord record = new(ex, "dbatools_Restore-DbaDatabase", ErrorCategory.NotSpecified, _restoreInstance);
            StopFunction("Failure", target: _restoreInstance, errorRecord: record, continueLoop: true);
            return;
        }
        if (ParameterSetName == "RestorePage")
        {
            if (_restoreInstance!.Edition.IndexOf("Enterprise", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                WriteMessage(MessageLevel.Verbose, "Taking Tail log backup for page restore for Enterprise");
                TakeTailBackup();
            }
            WriteMessage(MessageLevel.Verbose, "Restoring Tail log backup for page restore");
            Hashtable tailRestoreParms = new()
            {
                ["SqlInstance"] = _restoreInstance,
                ["TrustDbBackupHistory"] = true,
                ["NoRecovery"] = true,
                ["OutputScriptOnly"] = OutputScriptOnly.ToBool(),
                ["BlockSize"] = BlockSize,
                ["MaxTransferSize"] = MaxTransferSize,
                ["BufferCount"] = BufferCount,
                ["Continue"] = true
            };
            ForwardShouldProcessSwitches(tailRestoreParms);
            NestedCommand.InvokeStreamed(this, "Restore-DbaDatabase", tailRestoreParms, _tailBackup ?? new List<object?>());

            Hashtable recoverParms = new()
            {
                ["SqlInstance"] = _restoreInstance,
                ["Recover"] = true,
                ["DatabaseName"] = _databaseName,
                ["OutputScriptOnly"] = OutputScriptOnly.ToBool()
            };
            ForwardShouldProcessSwitches(recoverParms);
            foreach (PSObject recovered in NestedCommand.Invoke(this, "Restore-DbaDatabase", recoverParms))
                WriteObject(recovered);
        }
        // refresh the SMO as we probably used T-SQL, but only if we already got a SMO
        if (SqlInstance.InputObject is Server inputServer)
        {
            inputServer.Databases.Refresh();
        }
    }

    private List<object?>? _tailBackup;

    private void TakeTailBackup()
    {
        Hashtable backupParms = new()
        {
            ["SqlInstance"] = _restoreInstance,
            ["Database"] = _databaseName,
            ["Type"] = "Log",
            ["BackupDirectory"] = PageRestoreTailFolder,
            ["NoRecovery"] = true,
            ["CopyOnly"] = true
        };
        ForwardShouldProcessSwitches(backupParms);
        _tailBackup = new List<object?>();
        foreach (PSObject item in NestedCommand.Invoke(this, "Backup-DbaDatabase", backupParms))
            _tailBackup.Add(item);
    }

    // Deliberate deviation from the retired function, on a destructive path - NOT a parity fix.
    // Forwarding the caller's EFFECTIVE WhatIf/Confirm state into nested calls is deliberately
    // safer than the behavior it replaces, and the comment used to claim the opposite.
    //
    // Measured 2026-07-24: a module script function resolves $WhatIfPreference through its own
    // module scope chain, so a caller-local ambient value never reached the retired function's
    // nested calls at all. During -PageRestore the retired function therefore wrote a REAL
    // tail-log backup WITH NORECOVERY - a backup file on disk and the database left RESTORING -
    // in the middle of what the caller asked to be a dry run, under both an ambient
    // $WhatIfPreference = $true and a SupportsShouldProcess wrapper invoked with -WhatIf.
    // A bound -WhatIf was honored in both worlds; only the ambient and wrapper cases diverge.
    // Forwarding the effective dry-run state prevents that preview-time mutation here. The
    // source-side defect is registered upstream as U-24 and is not repaired by this deviation.
    private void ForwardShouldProcessSwitches(Hashtable parms)
    {
        if (TestBound("WhatIf"))
        {
            parms["WhatIf"] = MyInvocation.BoundParameters["WhatIf"];
        }
        else if (PsOps.IsTrue(GetVariableValue("WhatIfPreference", false)))
        {
            parms["WhatIf"] = new SwitchParameter(true);
        }

        if (TestBound("Confirm"))
        {
            parms["Confirm"] = MyInvocation.BoundParameters["Confirm"];
        }
        else
        {
            // Inheritance here is suppressing-only. An ambient ConfirmPreference of None is what
            // -Confirm:$false leaves in a caller's scope, so forwarding Confirm:$false prevents
            // nested prompts. Positive ambient values are deliberately not synthesized, because
            // that would ADD prompts. No claim is made about what the retired function's nested
            // calls observed.
            object? ambientConfirm = GetVariableValue("ConfirmPreference", null);
            if (ambientConfirm is PSObject wrapped)
            {
                ambientConfirm = wrapped.BaseObject;
            }
            if (ambientConfirm is ConfirmImpact impact && impact == ConfirmImpact.None)
            {
                parms["Confirm"] = new SwitchParameter(false);
            }
        }
    }

    // PS pipeline assignment shape: empty -> null (AutomationNull), one -> the scalar,
    // many -> object[] (cross-model review 2026-07-07 finding B5).
    private static object? ShapeForGlobal(List<object?> items)
    {
        if (items.Count == 0)
        {
            return null;
        }
        if (items.Count == 1)
        {
            return items[0];
        }
        return items.ToArray();
    }

    private static string JoinUniqueDatabases(List<object?> histories)
    {
        // (X | Sort-Object -Property Database -Unique).Database -join ','
        List<string> names = new();
        foreach (object? history in histories)
            names.Add(RestoreUtility.PsStringify(PsProperty.Get(history, "Database")));
        names.Sort(StringComparer.CurrentCultureIgnoreCase);
        List<string> unique = new();
        foreach (string name in names)
        {
            if (unique.Count == 0 || !string.Equals(unique[unique.Count - 1], name, StringComparison.CurrentCultureIgnoreCase))
                unique.Add(name);
        }
        return string.Join(",", unique);
    }
}
