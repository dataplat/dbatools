#nullable enable

using System;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The hop-support helper that keeps a re-emitted error attributed to the command that actually
/// failed. It lives on NestedCommand rather than on DbaBaseCmdlet so it ships INSIDE this
/// satellite: the base dbatools.dll is a separate, independently installed assembly, and a
/// satellite calling into a newer base would fail to load against the base already on a user's
/// machine.
/// </summary>
internal static partial class NestedCommand
{

    // Write-Error -ErrorRecord sets this internal flag, which is why a PowerShell function
    // forwarding a record never loses the originating command from FullyQualifiedErrorId and a
    // compiled cmdlet calling WriteError does. Resolved once; a runtime that renames it leaves
    // the field null and the re-emission behaves as it did before.
    private static readonly System.Reflection.PropertyInfo? PreserveInvocationInfoOnceProperty =
        typeof(ErrorRecord).GetProperty(
            "PreserveInvocationInfoOnce",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Public);

    /// <summary>
    /// Marks a record the host did not create so that re-emitting it keeps the command that
    /// actually failed. Returns the same instance, so a call site reads
    /// <c>WriteError(NestedCommand.PreserveErrorIdentity(nestedError))</c>.
    ///
    /// Without it the runtime re-stamps the trailing half of FullyQualifiedErrorId with the
    /// re-emitting cmdlet's type name, so a nested failure the retired function reported against
    /// the command that actually failed arrives stamped with the porting cmdlet instead. The
    /// divergence reaches the caller's -ErrorVariable as well as the error stream, because
    /// WriteError re-stamps the record in place and the variable holds that same instance.
    ///
    /// Only for records that arrived from somewhere else. A record this cmdlet built itself
    /// SHOULD be stamped with this cmdlet - that is what the source's own Write-Error produced.
    /// </summary>
    /// <param name="record">The record about to be re-emitted through the host's error stream</param>
    internal static ErrorRecord PreserveErrorIdentity(ErrorRecord record)
    {
        if (record is null)
        {
            return record!;
        }

        try
        {
            PreserveInvocationInfoOnceProperty?.SetValue(record, true);
        }
        catch
        {
            // A record that cannot be marked is re-emitted exactly as it is today.
        }

        return record;
    }
}
