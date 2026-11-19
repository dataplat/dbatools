#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

// Port of public/Find-DbaBackup.ps1. The pin's Get-ChildItem $Path -Filter -File -Recurse runs here as a .NET directory
// walk that follows the engine's and the FileSystem provider's rules (path globbing, the recursion fix-up of a trailing
// '*', hidden items, links, per-edition ordering), and each match is returned as the FileSystem provider's own item, so
// PSPath, PSParentPath, PSDrive and the other provider properties stay what Get-ChildItem gives and Remove-Item binds.
/// <summary>Searches filesystem directories for SQL Server backup files based on age and extension criteria.</summary>
[Cmdlet(VerbsCommon.Find, "DbaBackup")]
public sealed class FindDbaBackupCommand : DbaBaseCmdlet
{
    /// <summary>Full path to the root level backup folder.</summary>
    [Parameter(Mandatory = true, Position = 0, HelpMessage = "Full path to the root level backup folder (ex. 'C:\\SQL\\Backups'")]
    [Alias("BackupFolder")]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>Backup file extension to find (ex. bak, trn, dif).</summary>
    [Parameter(Mandatory = true, Position = 1, HelpMessage = "Backup File extension to remove (ex. bak, trn, dif)")]
    [PsStringCast]
    public string? BackupFileExtension { get; set; }

    /// <summary>Backup retention period (ex. 24h, 7d, 4w, 6m).</summary>
    [Parameter(Mandatory = true, Position = 2, HelpMessage = "Backup retention period. (ex. 24h, 7d, 4w, 6m)")]
    [PsStringCast]
    public string? RetentionPeriod { get; set; }

    /// <summary>Only includes files whose Archive bit is clear (already backed up elsewhere).</summary>
    [Parameter]
    public SwitchParameter CheckArchiveBit { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void BeginProcessing()
    {
        // Ensure BackupFileExtension does not begin with a .
        if (BackupFileExtension is not null && BackupFileExtension.StartsWith(".", StringComparison.Ordinal))
            WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture,
                "Parameter -BackupFileExtension begins with a period '{0}'. A period is automatically prepended to -BackupFileExtension and need not be passed in.",
                BackupFileExtension));
        // Ensure Path is a proper path
        if (!TestPathContainer(Path ?? ""))
            StopFunction(String.Format(CultureInfo.InvariantCulture, "{0} not found", Path));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;
        WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Finding backups on {0}", Path));

        // A failed conversion stops the function without a return in the pin, so the enumeration below still runs and
        // matches nothing: LastWriteTime -lt $null is false.
        DateTime? retentionDate = null;
        try
        {
            retentionDate = ConvertRetention(RetentionPeriod ?? "");
            WriteMessage(MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Backup Retention Date set to {0}", retentionDate.Value));
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            ErrorRecord record = new(ex is RuntimeException ? ex : new RuntimeException(ex.Message, ex), "RuntimeException", ErrorCategory.OperationStopped, null);
            StopFunction("Failed to interpret retention time.", errorRecord: record);
        }

        if (CheckArchiveBit)
            WriteMessage(MessageLevel.Verbose, "Removing only archived files.");

        // Enumeration may take a while; files stream out as they are found (#970).
        List<ErrorRecord> enumErrors = new();
        string pattern = "*." + BackupFileExtension;
        try
        {
            // Correction (wildcard-path-finds-nothing): upstream globs a wildcard path while -File is in force, which
            // drops the matching directories, so it found nothing. Every directory the path resolves to is searched here
            // as Get-ChildItem searches a literal directory.
            string path = NormalizeForRecursion(Path ?? "");
            foreach (PathInfo root in SessionState.Path.GetResolvedPSPathFromPSPath(path))
            {
                CancellationToken.ThrowIfCancellationRequested();
                if (!String.Equals(root.Provider.Name, "FileSystem", StringComparison.OrdinalIgnoreCase))
                {
                    // Get-ChildItem has no -File outside the FileSystem provider; its binding error lands in EnumErrors.
                    enumErrors.Add(new ErrorRecord(new ParameterBindingException("A parameter cannot be found that matches parameter name 'File'."),
                        "NamedParameterNotFound", ErrorCategory.InvalidArgument, root.Path));
                    continue;
                }
                // BeginProcessing proved every match is a container.
                if (!Directory.Exists(root.ProviderPath))
                    continue;
                WalkLiteral(new DirectoryInfo(root.ProviderPath), root.Path, pattern, retentionDate, enumErrors);
            }
        }
        catch (Exception ex) when (ex is ItemNotFoundException || ex is System.Management.Automation.DriveNotFoundException || ex is ProviderNotFoundException ||
            ex is ProviderInvocationException || ex is NotSupportedException || ex is ArgumentException || ex is InvalidOperationException)
        {
            enumErrors.Add(ex is IContainsErrorRecord contained && contained.ErrorRecord is not null
                ? contained.ErrorRecord
                : new ErrorRecord(ex, ex.GetType().Name, ErrorCategory.ObjectNotFound, Path));
        }

        if (enumErrors.Count > 0)
            WriteEnumerationWarning(enumErrors);
    }

    // PS 7 engine, NormalizePathForChildItemRecursion: with -Recurse and -File, a path whose last element is '*' is
    // listed from its parent; Windows PowerShell has no such fix-up and globs it. The other branch (a leaf that is not a
    // container becomes -Include) cannot be reached here, because BeginProcessing stopped unless every item the path
    // resolves to is a container.
    private string NormalizeForRecursion(string path)
    {
        if (!PsFileSystem.TrailingStarFromParent)
            return path;
        if (path.EndsWith("\\", StringComparison.Ordinal) || path.EndsWith("/", StringComparison.Ordinal))
            return path;
        string childName = SessionState.Path.ParseChildName(path);
        if (String.Equals(childName, "*", StringComparison.OrdinalIgnoreCase) && path.Length > childName.Length)
            return path.Substring(0, path.Length - childName.Length);
        return path;
    }

    // PS FileSystemProvider.Dir for a literal path: the matching files of a directory (sorted by name on PowerShell 7,
    // in file system order on Windows PowerShell), then each subdirectory in file system order. Hidden items are
    // skipped, and so are links: every reparse point on Windows PowerShell, symbolic links and junctions on PowerShell 7.
    private void WalkLiteral(DirectoryInfo directory, string psDirectory, string pattern, DateTime? retentionDate, List<ErrorRecord> enumErrors)
    {
        CancellationToken.ThrowIfCancellationRequested();
        try
        {
            foreach (FileInfo file in PsFileSystem.MatchingFiles(directory, pattern))
            {
                if ((file.Attributes & FileAttributes.Hidden) != 0)
                    continue;
                Consider(file, SessionState.Path.Combine(psDirectory, file.Name), retentionDate, enumErrors);
            }
            foreach (DirectoryInfo child in directory.EnumerateDirectories())
            {
                CancellationToken.ThrowIfCancellationRequested();
                if ((child.Attributes & FileAttributes.Hidden) != 0 || PsFileSystem.IsSkippedLink(child))
                    continue;
                WalkLiteral(child, SessionState.Path.Combine(psDirectory, child.Name), pattern, retentionDate, enumErrors);
            }
        }
        catch (Exception ex) when (ex is ArgumentException || ex is IOException || ex is UnauthorizedAccessException)
        {
            enumErrors.Add(DirError(ex, directory));
        }
    }

    private static ErrorRecord DirError(Exception ex, DirectoryInfo directory)
    {
        if (ex is UnauthorizedAccessException)
            return new ErrorRecord(ex, "DirUnauthorizedAccessError", ErrorCategory.PermissionDenied, directory.FullName);
        if (ex is IOException)
            return new ErrorRecord(ex, "DirIOError", ErrorCategory.ReadError, directory.FullName);
        return new ErrorRecord(ex, "DirArgumentError", ErrorCategory.InvalidArgument, directory.FullName);
    }

    // PS: Where-Object LastWriteTime -lt $RetentionDate | DbaArchiveBitFilter
    private void Consider(FileInfo file, string psPath, DateTime? retentionDate, List<ErrorRecord> enumErrors)
    {
        if (retentionDate is null || !(file.LastWriteTime < retentionDate.Value))
            return;
        // PS: $_.Attributes -notmatch "Archive"
        if (CheckArchiveBit && (file.Attributes & FileAttributes.Archive) != 0)
            return;
        Collection<PSObject> items;
        try
        {
            items = SessionState.InvokeProvider.Item.Get(new[] { psPath }, false, true);
        }
        catch (Exception ex) when (ex is ItemNotFoundException || ex is ProviderInvocationException || ex is IOException || ex is UnauthorizedAccessException)
        {
            enumErrors.Add(new ErrorRecord(ex, "GetItemError", ErrorCategory.ReadError, psPath));
            return;
        }
        foreach (PSObject item in items)
            WriteObject(item);
    }

    // PS: Test-Path $Path -PathType 'Container' - the item exists and every item the path resolves to is a container;
    // the four exceptions Test-Path absorbs answer $false.
    private bool TestPathContainer(string path)
    {
        if (String.IsNullOrWhiteSpace(path))
            return false;
        try
        {
            bool exists = SessionState.InvokeProvider.Item.Exists(path);
            bool container = SessionState.InvokeProvider.Item.IsContainer(path);
            return exists && container;
        }
        catch (Exception ex) when (ex is PSNotSupportedException || ex is System.Management.Automation.DriveNotFoundException || ex is ProviderNotFoundException ||
            ex is ItemNotFoundException)
        {
            return false;
        }
    }

    // PS: the nested Convert-UserFriendlyRetentionToDatetime. Units and value are validated as the pin does, and the
    // value goes through PowerShell's unary minus on a string ([int]::TryParse accepts sign and surrounding spaces).
    private static DateTime ConvertRetention(string retention)
    {
        int length = retention.Length;
        string value = retention.Substring(0, length - 1);
        string units = retention.Substring(length - 1, 1).ToLowerInvariant();

        if (units != "h" && units != "d" && units != "w" && units != "m")
            throw new RuntimeException(String.Format(CultureInfo.InvariantCulture,
                "RetentionPeriod '{0}' units invalid! See Get-Help for correct formatting and examples.", retention));
        if (!Int32.TryParse(value, NumberStyles.Integer, CultureInfo.CurrentCulture, out int number))
            throw new RuntimeException(String.Format(CultureInfo.InvariantCulture,
                "RetentionPeriod '{0}' format invalid! See Get-Help for correct formatting and examples.", retention));

        double negated = -(double)number;
        DateTime now = DateTime.Now;
        switch (units)
        {
            case "h":
                return now.AddHours(negated);
            case "d":
                return now.AddDays(negated);
            case "w":
                return now.AddDays(negated * 7);
            default:
                return now.AddMonths(checked(-number));
        }
    }

    // PS: Write-Message "Errors encountered enumerating files." -Level Warning -ErrorRecord $EnumErrors
    private void WriteEnumerationWarning(List<ErrorRecord> enumErrors)
    {
        MessageService.MessageRequest request = new()
        {
            Level = MessageLevel.Warning,
            Message = "Errors encountered enumerating files.",
            FunctionName = MyInvocation.MyCommand.Name,
            ModuleName = "dbatools",
            ErrorRecord = enumErrors.ToArray(),
            EnableException = EnableException.ToBool(),
            File = MyInvocation.ScriptName,
            Line = MyInvocation.ScriptLineNumber
        };
        MessageService.Write(this, request);
    }
}
