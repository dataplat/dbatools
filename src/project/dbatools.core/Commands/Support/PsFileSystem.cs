#nullable enable

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The FileSystem provider's Get-ChildItem rules that differ between Windows PowerShell (net472) and PowerShell 7
/// (net8.0): filter matching, name ordering, which directory links a recursion skips, and the engine's fix-up of a
/// trailing '*' under -Recurse -File.
/// </summary>
internal static class PsFileSystem
{
#if NETFRAMEWORK
    /// <summary>Whether the engine lists a recursive -File path ending in '*' from its parent (PowerShell 7 only).</summary>
    internal static readonly bool TrailingStarFromParent = false;
#else
    /// <summary>Whether the engine lists a recursive -File path ending in '*' from its parent (PowerShell 7 only).</summary>
    internal static readonly bool TrailingStarFromParent = true;

    // FileSystemProvider._enumerationOptions: Win32 matching, case-insensitive, nothing skipped.
    private static readonly EnumerationOptions ProviderOptions = new()
    {
        MatchType = MatchType.Win32,
        MatchCasing = MatchCasing.CaseInsensitive,
        AttributesToSkip = 0
    };
#endif

    /// <summary>The files of a directory that match a provider -Filter, in the order Get-ChildItem writes them:
    /// file system order on Windows PowerShell, sorted by name (current culture, ignoring case) on PowerShell 7.</summary>
    internal static IEnumerable<FileInfo> MatchingFiles(DirectoryInfo directory, string filter)
    {
#if NETFRAMEWORK
        return directory.EnumerateFiles(filter);
#else
        return directory.EnumerateFiles(filter, ProviderOptions).OrderBy(static f => f.Name, StringComparer.CurrentCultureIgnoreCase);
#endif
    }

    /// <summary>Whether a recursive Get-ChildItem without -Force or -FollowSymlink skips this directory: every reparse
    /// point on Windows PowerShell, name-surrogate links (symbolic links, junctions, mount points) on PowerShell 7.</summary>
    internal static bool IsSkippedLink(DirectoryInfo directory)
    {
        if ((directory.Attributes & FileAttributes.ReparsePoint) == 0)
            return false;
#if NETFRAMEWORK
        return true;
#else
        return directory.LinkTarget is not null;
#endif
    }
}
