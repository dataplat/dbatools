#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Thrown when a ported private helper hits a Stop-Function site while running with
/// EnableException semantics. Carries the fully built error records so the catching call
/// site can reproduce its own Stop-Function -ErrorRecord shape byte-for-byte.
/// </summary>
internal sealed class InnerCommandException : Exception
{
    /// <summary>The error records the inner Stop-Function site built.</summary>
    public ErrorRecord[] Records { get; }

    public InnerCommandException(ErrorRecord[] records)
        : base(records.Length > 0 ? records[0].Exception.Message : "Unknown failure")
    {
        Records = records;
    }

    /// <summary>The first record, for -ErrorRecord $_ style call sites.</summary>
    public ErrorRecord FirstRecord
    {
        get { return Records[0]; }
    }
}

/// <summary>
/// Write-Message / Stop-Function parity for ported PRIVATE helpers (Test-DbaLsnChain,
/// Get-XpDirTreeRestoreFile, Convert-DbaLSN, ...) that execute inside a hosting cmdlet but
/// must keep their own FunctionName attribution and their own EnableException value —
/// exactly like the PS functions they replace. Routes through MessageService so
/// Get-DbatoolsLog output is indistinguishable from the PS implementation.
/// The hosting cmdlet's own call sites keep using DbaBaseCmdlet.WriteMessage/StopFunction.
/// </summary>
internal static class InnerCommand
{
    /// <summary>Write-Message parity for a private helper running inside a cmdlet.</summary>
    internal static void Message(PSCmdlet host, string functionName, bool enableException, MessageLevel level, string message, object? target = null, Exception? exception = null)
    {
        MessageService.MessageRequest request = new()
        {
            Level = level,
            Message = message,
            FunctionName = functionName,
            ModuleName = "dbatools",
            Target = target,
            Exception = exception,
            EnableException = enableException,
            File = host.MyInvocation.ScriptName,
            Line = host.MyInvocation.ScriptLineNumber
        };
        MessageService.Write(host, request);
    }

    /// <summary>
    /// Stop-Function parity for a private helper. Replicates the DbaBaseCmdlet.StopFunction
    /// flow (which itself replicates private/functions/flowcontrol/Stop-Function.ps1), but:
    /// under EnableException the terminating path THROWS InnerCommandException instead of
    /// ThrowTerminatingError — in PS the inner function's throw is a statement-terminating
    /// error the CALLER's try/catch observes, and that is exactly what the C# call sites do.
    /// In non-EnableException mode it writes the warning, silently inserts the record into
    /// $error, and returns true when the PS shape was a full stop (no -Continue); the call
    /// site carries the control flow, including the sites that deliberately fall through.
    /// </summary>
    internal static bool Stop(PSCmdlet host, string functionName, bool enableException, string message,
        object? target = null,
        ErrorRecord[]? errorRecords = null,
        Exception? exception = null,
        ErrorCategory category = ErrorCategory.NotSpecified,
        bool continueLoop = false)
    {
        MessageService.MessageRequest transformContext = new()
        {
            FunctionName = functionName,
            ModuleName = "dbatools"
        };

        object? displayTarget = target;
        if (displayTarget != null)
            displayTarget = MessageService.ResolveTarget(host, transformContext, displayTarget);

        if (exception != null)
            exception = MessageService.ResolveException(host, transformContext, exception);
        else if (errorRecords != null)
        {
            for (int n = 0; n < errorRecords.Length; n++)
            {
                Exception tempException = MessageService.ResolveException(host, transformContext, errorRecords[n].Exception);
                if (tempException != errorRecords[n].Exception)
                    errorRecords[n] = new ErrorRecord(tempException, errorRecords[n].FullyQualifiedErrorId, errorRecords[n].CategoryInfo.Category, errorRecords[n].TargetObject);
            }
        }

        List<ErrorRecord> records = new();
        bool messageOverridesException = false;

        if (errorRecords != null || exception != null)
        {
            if (errorRecords != null)
            {
                foreach (ErrorRecord record in errorRecords)
                {
                    string msg = MessageService.GetErrorMessage(record);
                    Exception newException = exception ?? new Exception(msg, record.Exception);

                    // PS: if ($record.CategoryInfo.Category) - NotSpecified (0) is falsy,
                    // so only a real category on the input record overrides the argument.
                    ErrorCategory effectiveCategory = category;
                    if (record.CategoryInfo.Category != ErrorCategory.NotSpecified)
                        effectiveCategory = record.CategoryInfo.Category;

                    records.Add(new ErrorRecord(newException, $"dbatools_{functionName}", effectiveCategory, displayTarget));
                }
            }
            else
            {
                records.Add(new ErrorRecord(exception!, $"dbatools_{functionName}", category, displayTarget));
            }
        }
        else
        {
            records.Add(new ErrorRecord(new Exception(message), $"dbatools_{functionName}", category, displayTarget));
            // The plain path always overrides: the message IS the exception text.
            messageOverridesException = true;
        }

        MessageService.MessageRequest request = new()
        {
            Level = MessageLevel.Warning,
            Message = message,
            FunctionName = functionName,
            ModuleName = "dbatools",
            Target = displayTarget,
            ErrorRecord = records.ToArray(),
            EnableException = enableException,
            OverrideExceptionMessage = messageOverridesException,
            // Stop-Function redirects the warning stream to null under EnableException (3>$null).
            SuppressWarningDisplay = enableException,
            FromStopFunction = true,
            File = host.MyInvocation.ScriptName,
            Line = host.MyInvocation.ScriptLineNumber
        };
        MessageService.Write(host, request);

        if (enableException)
        {
            // -Continue under EnableException STILL terminates (Stop-Function quirk): in PS the
            // inner function throws and the caller's try/catch decides what happens next.
            throw new InnerCommandException(records.ToArray());
        }

        // Non-EnableException mode: the record lands in $error without being displayed
        // (the PS source runs $null = Write-Error ... 2>&1).
        foreach (ErrorRecord record in records)
            InsertGlobalError(host, record);

        return !continueLoop;
    }

    /// <summary>Lands a record in $error without displaying it - the source's
    /// `$null = Write-Error ... 2>&amp;1`. Callable by a cmdlet that has to record an error the
    /// PS original never put on the error stream, since WriteError would display it under the
    /// default preference.</summary>
    internal static void InsertGlobalError(PSCmdlet host, ErrorRecord record)
    {
        try
        {
            if (host.SessionState.PSVariable.GetValue("Error") is not ArrayList errorList)
                return;
            errorList.Insert(0, record);

            int maximumErrorCount = 256;
            object maximumRaw = host.SessionState.PSVariable.GetValue("MaximumErrorCount");
            if (maximumRaw != null)
            {
                try { maximumErrorCount = Convert.ToInt32(maximumRaw); }
                catch { /* keep the engine default when the variable is malformed */ }
            }
            while (errorList.Count > maximumErrorCount)
                errorList.RemoveAt(errorList.Count - 1);
        }
        catch
        {
            // $error decoration is best-effort, mirroring DbaBaseCmdlet.InsertGlobalError.
        }
    }
}
