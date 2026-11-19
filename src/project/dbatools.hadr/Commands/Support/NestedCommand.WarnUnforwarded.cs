#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Message;

namespace Dataplat.Dbatools.Commands;

internal static partial class NestedCommand
{
    /// <summary>
    /// Emits a nested-helper failure as WARN-ONLY, matching a retired PS function that invoked
    /// another dbatools command WITHOUT forwarding -EnableException (e.g. Get-DbaWsfcDisk calling
    /// Get-DbaWsfcResource, or Get-DbaWsfcResource calling Get-DbaWsfcCluster / Get-DbaCmObject).
    /// The inner command ran with its OWN EnableException = $false, so it warned and returned
    /// nothing REGARDLESS of the outer command's -EnableException.
    ///
    /// Routing this through the host's WriteMessage would instead read the OUTER command's
    /// EnableException and, when it is set, escalate the warning to a written error record
    /// (MessageService.Write: !FromStopFunction &amp;&amp; EnableException -&gt; WriteError) - surfacing an
    /// error the PS hop only ever warned for. Pinning EnableException = false here keeps the
    /// nested-unforwarded contract: the warning displays and lands in $error / Get-DbatoolsLog,
    /// but never rides the error stream.
    /// </summary>
    internal static void WarnUnforwarded(PSCmdlet host, string message, object? target, Exception? exception)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        // Match DbaBaseCmdlet.GetCommandName (private): the invocation name for Get-DbatoolsLog
        // parity, falling back to the CLR type name.
        string functionName = host.MyInvocation?.MyCommand?.Name is { Length: > 0 } name
            ? name
            : host.GetType().Name;

        MessageService.MessageRequest request = new MessageService.MessageRequest();
        request.Level = MessageLevel.Warning;
        request.Message = message;
        request.FunctionName = functionName;
        request.ModuleName = "dbatools";
        request.Target = target;
        request.Exception = exception;
        // The nested command ran EnableException = $false; the outer -EnableException must NOT
        // escalate its warning to an error (parity with the unforwarded PS call).
        request.EnableException = false;
        request.File = host.MyInvocation?.ScriptName;
        request.Line = host.MyInvocation?.ScriptLineNumber ?? 0;
        MessageService.Write(host, request);

        // The source's non-EnableException Stop-Function ALSO bookkeeps the record in $error
        // ($null = Write-Error ... 2>&1 - the DEF-013 hidden-record mechanism): the warning
        // displays, and the ErrorRecord lands in $error WITHOUT riding the error stream.
        // MessageService.Write logs to Get-DbatoolsLog but does NOT touch $error, so insert it
        // here to match. Mirrors DbaBaseCmdlet.InsertGlobalError (private): Insert at 0, trim to
        // $MaximumErrorCount; best-effort (a constrained runspace may deny $error access, and
        // failing the command over bookkeeping would be worse than the PS behavior it mirrors).
        if (exception is not null)
        {
            try
            {
                if (host.SessionState.PSVariable.GetValue("Error") is System.Collections.ArrayList errorList)
                {
                    ErrorRecord record = new ErrorRecord(exception, $"dbatools_{functionName}", ErrorCategory.NotSpecified, target);
                    errorList.Insert(0, record);

                    int maximumErrorCount = 256;
                    if (host.SessionState.PSVariable.GetValue("MaximumErrorCount") is object maximumRaw)
                    {
                        try { maximumErrorCount = Convert.ToInt32(maximumRaw); }
                        catch { /* keep the engine default when the variable is malformed */ }
                    }
                    while (errorList.Count > maximumErrorCount)
                        errorList.RemoveAt(errorList.Count - 1);
                }
            }
            catch
            {
                // $error decoration is best-effort, exactly as DbaBaseCmdlet.InsertGlobalError.
            }
        }
    }
}
