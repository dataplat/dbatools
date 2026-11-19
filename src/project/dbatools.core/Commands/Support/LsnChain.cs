#nullable enable

using System.Collections.Generic;
using System.Management.Automation;
using System.Numerics;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Port of private/functions/Test-DbaLsnChain.ps1: checks that a filtered array from
/// Get-FilteredRestore contains a restorabel chain of LSNs. Finds the anchoring Full backup
/// (or multiple if it's a striped set), filters to ensure that all the backups are from that
/// anchor point (LastLSN) and that they're all on the same RecoveryForkID, then checks that
/// we have either enough Diffs and T-log backups to get to where we want to go. And checks
/// that there is no break between LastLSN and FirstLSN in sequential files.
/// </summary>
internal static class LsnChain
{
    /// <summary>
    /// The chain test. Input objects are PSObject-wrapped history entries (BackupHistory or
    /// Read-DbaBackupHeader rows); property reads go through PSObject exactly like the PS
    /// dynamic member access did.
    /// </summary>
    internal static bool Test(PSCmdlet host, IReadOnlyList<PSObject> filteredRestoreFiles, bool continueRestore, bool enableException)
    {
        const string functionName = "Test-DbaLsnChain";

        if (continueRestore)
            return true;

        InnerCommand.Message(host, functionName, enableException, MessageLevel.Verbose, "Testing LSN Chain");

        // PS: if ($null -eq $TestHistory[0].BackupTypeDescription) { $TypeName = 'Type' }
        string typeName = PsProperty.Get(filteredRestoreFiles.Count > 0 ? filteredRestoreFiles[0] : null, "BackupTypeDescription") is null
            ? "Type"
            : "BackupTypeDescription";
        InnerCommand.Message(host, functionName, enableException, MessageLevel.VeryVerbose, $"Testing LSN Chain - Type {typeName}");

        List<PSObject> fullDbAnchor = new();
        foreach (PSObject entry in filteredRestoreFiles)
        {
            string entryType = RestoreUtility.PsStringify(PsProperty.Get(entry, typeName));
            if (PsString.In(entryType, "Database", "Full"))
                fullDbAnchor.Add(entry);
        }

        // PS: ($FullDBAnchor | Group-Object -Property FirstLSN | Measure-Object).Count -ne 1
        HashSet<string> distinctFirstLsn = new();
        foreach (PSObject entry in fullDbAnchor)
            distinctFirstLsn.Add(RestoreUtility.PsStringify(PsProperty.Get(entry, "FirstLSN")));

        if (distinctFirstLsn.Count != 1)
        {
            int cnt = distinctFirstLsn.Count;
            foreach (PSObject tFile in fullDbAnchor)
            {
                // PS reads $tfile.TypeName here (a property that does not exist) — preserved: it renders empty.
                InnerCommand.Message(host, functionName, enableException, MessageLevel.Debug, $"{RestoreUtility.PsStringify(PsProperty.Get(tFile, "FirstLsn"))} - {RestoreUtility.PsStringify(PsProperty.Get(tFile, "TypeName"))}");
            }
            InnerCommand.Message(host, functionName, enableException, MessageLevel.Verbose, $"db count = {cnt}");
            InnerCommand.Message(host, functionName, enableException, MessageLevel.Warning, "More than 1 full backup from a different LSN, or less than 1, neither supported");
            return false;
        }

        // If same multiple Full DB backup exist with Same FirstLSN, just select one
        PSObject anchor = fullDbAnchor[0];

        // Via LSN chain:
        BigInteger checkPointLsn = PsLsn.ToBigInt(PsProperty.Get(anchor, "CheckPointLsn"));
        BigInteger fullDbLastLsn = PsLsn.ToBigInt(PsProperty.Get(anchor, "LastLsn"));

        List<PSObject> backupWrongLsn = new();
        foreach (PSObject entry in filteredRestoreFiles)
        {
            if (PsLsn.ToBigInt(PsProperty.Get(entry, "DatabaseBackupLsn")) != checkPointLsn)
                backupWrongLsn.Add(entry);
        }
        // Should be 0 in there, if not, lets check that they're from during the full backup
        if (backupWrongLsn.Count > 0)
        {
            int earlier = 0;
            foreach (PSObject entry in backupWrongLsn)
            {
                if (PsLsn.ToBigInt(PsProperty.Get(entry, "LastLSN")) < fullDbLastLsn)
                    earlier++;
            }
            if (earlier > 0)
            {
                InnerCommand.Message(host, functionName, enableException, MessageLevel.Warning, "We have non matching LSNs - not supported");
                return false;
            }
        }

        List<PSObject> diffAnchor = new();
        foreach (PSObject entry in filteredRestoreFiles)
        {
            string entryType = RestoreUtility.PsStringify(PsProperty.Get(entry, typeName));
            if (PsString.In(entryType, "Database Differential", "Differential"))
                diffAnchor.Add(entry);
        }

        // Check for no more than a single Differential backup
        HashSet<string> diffFirstLsns = new();
        foreach (PSObject entry in diffAnchor)
            diffFirstLsns.Add(RestoreUtility.PsStringify(PsProperty.Get(entry, "FirstLSN")));

        PSObject tlogAnchor;
        if (diffFirstLsns.Count > 1)
        {
            InnerCommand.Message(host, functionName, enableException, MessageLevel.Warning, "More than 1 differential backup, not supported");
            return false;
        }
        else if (diffAnchor.Count == 1)
        {
            InnerCommand.Message(host, functionName, enableException, MessageLevel.VeryVerbose, "Found a diff file, setting Log Anchor");
            tlogAnchor = diffAnchor[0];
        }
        else
        {
            tlogAnchor = anchor;
        }

        // Check T-log LSNs form a chain.
        List<PSObject> tranLogBackups = new();
        foreach (PSObject entry in filteredRestoreFiles)
        {
            string entryType = RestoreUtility.PsStringify(PsProperty.Get(entry, typeName));
            bool isLogBackup = PsString.In(entryType, "Transaction Log", "Log");
            bool isBasedOnAnchor = PsLsn.ToBigInt(PsProperty.Get(entry, "DatabaseBackupLsn")) == checkPointLsn;
            bool hasGreaterLastLsn = PsLsn.ToBigInt(PsProperty.Get(entry, "LastLsn")) > checkPointLsn;

            InnerCommand.Message(host, functionName, enableException, MessageLevel.Verbose,
                $"Checking {RestoreUtility.PsStringify(PsProperty.Get(entry, "FullName"))} - isLogBackup {PsBool.Text(isLogBackup)}, isBasedOnAnchor {PsBool.Text(isBasedOnAnchor)}, hasGreaterLastLsn {PsBool.Text(hasGreaterLastLsn)}, FullDBAnchor.CheckPointLsn {RestoreUtility.PsStringify(PsProperty.Get(anchor, "CheckPointLsn"))}, DatabaseBackupLsn {RestoreUtility.PsStringify(PsProperty.Get(entry, "DatabaseBackupLsn"))}, FirstLsn {RestoreUtility.PsStringify(PsProperty.Get(entry, "FirstLsn"))} LastLsn {RestoreUtility.PsStringify(PsProperty.Get(entry, "LastLsn"))}");

            if (isLogBackup && (isBasedOnAnchor || hasGreaterLastLsn))
                tranLogBackups.Add(entry);
        }
        tranLogBackups.Sort((a, b) =>
        {
            int byLast = PsLsn.ToBigInt(PsProperty.Get(a, "LastLsn")).CompareTo(PsLsn.ToBigInt(PsProperty.Get(b, "LastLsn")));
            if (byLast != 0)
                return byLast;
            return PsLsn.ToBigInt(PsProperty.Get(a, "FirstLsn")).CompareTo(PsLsn.ToBigInt(PsProperty.Get(b, "FirstLsn")));
        });

        for (int i = 0; i < tranLogBackups.Count; i++)
        {
            InnerCommand.Message(host, functionName, enableException, MessageLevel.Debug, "looping t logs");
            if (i == 0)
            {
                if (PsLsn.ToBigInt(PsProperty.Get(tranLogBackups[i], "FirstLsn")) > PsLsn.ToBigInt(PsProperty.Get(tlogAnchor, "LastLsn")))
                {
                    InnerCommand.Message(host, functionName, enableException, MessageLevel.Warning,
                        $"Break in LSN Chain between {RestoreUtility.PsStringify(PsProperty.Get(tlogAnchor, "FullName"))} and {RestoreUtility.PsStringify(PsProperty.Get(tranLogBackups[i], "FullName"))} ");
                    InnerCommand.Message(host, functionName, enableException, MessageLevel.Verbose,
                        $"Anchor {RestoreUtility.PsStringify(PsProperty.Get(tlogAnchor, "LastLsn"))} - FirstLSN {RestoreUtility.PsStringify(PsProperty.Get(tranLogBackups[i], "FirstLsn"))}");
                    return false;
                }
            }
            else
            {
                // PS: ... -and ($TranLogBackups[$i] -ne $TranLogBackups[$i - 1]) — object identity.
                if (PsLsn.ToBigInt(PsProperty.Get(tranLogBackups[i - 1], "LastLsn")) != PsLsn.ToBigInt(PsProperty.Get(tranLogBackups[i], "FirstLsn"))
                    && !ReferenceEquals(tranLogBackups[i], tranLogBackups[i - 1]))
                {
                    InnerCommand.Message(host, functionName, enableException, MessageLevel.Warning,
                        $"Break in transaction log between {RestoreUtility.PsStringify(PsProperty.Get(tranLogBackups[i - 1], "FullName"))} and {RestoreUtility.PsStringify(PsProperty.Get(tranLogBackups[i], "FullName"))} ");
                    return false;
                }
            }
        }

        InnerCommand.Message(host, functionName, enableException, MessageLevel.VeryVerbose, "Passed LSN Chain checks");
        return true;
    }
}
