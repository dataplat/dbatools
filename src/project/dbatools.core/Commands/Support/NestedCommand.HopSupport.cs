#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The hop-support helpers every ported cmdlet in this satellite shares: the $error de-dup a
/// merged-back hop record needs, and the bound-common-parameter carrier a hop body needs
/// because it cannot see the caller's $PSBoundParameters.
///
/// They used to be copy-pasted into each cmdlet file, which put one rule in hundreds of places
/// and made every fix an N-file sweep. They live on NestedCommand rather than on DbaBaseCmdlet
/// so they ship INSIDE this satellite: the base dbatools.dll is a separate, independently
/// installed assembly, and a satellite that called into a newer base would fail to load
/// against the base already on a user's machine.
/// </summary>
internal static partial class NestedCommand
{
    // An InnerException chain longer than this is a cycle or a pathological wrap; a
    // bookkeeping helper must never be the thing that hangs the pipeline.
    private const int MaximumExceptionChainDepth = 32;

    /// <summary>
    /// Drops $error[0] when it is the hop's own copy of the supplied record. A hop runs its
    /// body in a nested pipeline with 2&gt;&amp;1 merged, so a non-terminating failure lands in
    /// the runspace's $error AND arrives at the host as an output item; re-emitting it with
    /// WriteError would push a second copy and leave the caller with one more record than the
    /// retired function produced. Best effort: a runspace that denies $error access keeps the
    /// duplicate rather than failing the command.
    /// </summary>
    /// <param name="host">The cmdlet whose session state owns $error</param>
    /// <param name="record">The record about to be re-emitted through the host's error stream</param>
    internal static void RemoveDuplicateError(PSCmdlet host, ErrorRecord record)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        if (host is null || record is null)
        {
            return;
        }

        try
        {
            if (host.SessionState.PSVariable.GetValue("Error") is not ArrayList errorList || errorList.Count == 0)
            {
                return;
            }
            if (errorList[0] is not ErrorRecord first)
            {
                return;
            }
            if (IsSameFailure(first, record))
            {
                errorList.RemoveAt(0);
            }
        }
        catch
        {
            // Best-effort bookkeeping only.
        }
    }

    /// <summary>
    /// Removes one matching record from the hop-era portion of $error. The boundary is the same
    /// pre-hop head used by ErrorVariableBridge; scanning past it could delete session history
    /// and make the bridge misclassify that history as hop output.
    /// </summary>
    internal static void RemoveHopEraDuplicateError(PSCmdlet host, ErrorRecord record, object? hopEraBaselineHead)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        if (host is null || record is null)
        {
            return;
        }

        try
        {
            if (host.SessionState.PSVariable.GetValue("Error") is not ArrayList errorList || errorList.Count == 0)
            {
                return;
            }

            int limit = HopEraLimit(errorList, hopEraBaselineHead);
            for (int i = 0; i < limit; i++)
            {
                if (errorList[i] is ErrorRecord candidate && IsSameFailure(candidate, record))
                {
                    errorList.RemoveAt(i);
                    return;
                }
            }
        }
        catch
        {
            // Best-effort bookkeeping only.
        }
    }

    private static int HopEraLimit(ArrayList errorList, object? hopEraBaselineHead)
    {
        if (hopEraBaselineHead is null)
        {
            return errorList.Count;
        }
        for (int i = 0; i < errorList.Count; i++)
        {
            if (ReferenceEquals(errorList[i], hopEraBaselineHead))
            {
                return i;
            }
        }
        return errorList.Count;
    }

    /// <summary>
    /// Whether the record sitting on top of $error is the hop's own copy of the record the host
    /// is about to re-emit. Every arm is anchored to OBJECT IDENTITY.
    ///
    /// The rule used to fall back to comparing exception message TEXT, and that arm could
    /// dequeue a completely unrelated record: two instances both failing with dbatools' bare
    /// "Failure" message is the everyday case, and nothing in a text comparison ties the
    /// candidate to the failure this hop produced. The hop's own duplicate then stayed in
    /// $error while somebody else's diagnostic disappeared from it.
    /// </summary>
    /// <param name="first">The record currently at $error[0]</param>
    /// <param name="record">The record the host is about to re-emit</param>
    /// <returns>True when they are the same failure</returns>
    internal static bool IsSameFailure(ErrorRecord? first, ErrorRecord? record)
    {
        if (first is null || record is null)
        {
            return false;
        }
        if (ReferenceEquals(first, record))
        {
            return true;
        }

        Exception? firstException = first.Exception;
        Exception? recordException = record.Exception;
        if (firstException is null || recordException is null)
        {
            return false;
        }
        if (ReferenceEquals(firstException, recordException))
        {
            return true;
        }

        // A re-wrapped record still carries the original exception OBJECT in its chain -
        // Stop-Function builds new Exception(message, record.Exception) - so walking the chain
        // recognizes the duplicate without ever comparing text.
        return ChainContains(firstException, recordException)
            || ChainContains(recordException, firstException);
    }

    private static bool ChainContains(Exception outer, Exception target)
    {
        Exception? current = outer.InnerException;
        for (int depth = 0; current is not null && depth < MaximumExceptionChainDepth; depth++)
        {
            if (ReferenceEquals(current, target))
            {
                return true;
            }
            current = current.InnerException;
        }
        return false;
    }

    /// <summary>
    /// The bound truthiness of a common parameter (-Verbose/-Debug) for forwarding into a hop
    /// body: true or false when the caller bound it, null when they did not, so the hop can tell
    /// "explicitly off" from "not specified" - a distinction a plain bool loses.
    /// </summary>
    /// <param name="host">The cmdlet whose invocation carries the bound parameters</param>
    /// <param name="name">The common parameter name</param>
    /// <returns>The bound value's truthiness, or null when unbound</returns>
    internal static object? BoundCommonParameter(PSCmdlet host, string name)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        if (host.MyInvocation.BoundParameters.TryGetValue(name, out object? value))
        {
            return LanguagePrimitives.IsTrue(value);
        }
        return null;
    }

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
