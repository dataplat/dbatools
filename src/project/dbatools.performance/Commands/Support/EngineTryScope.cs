#nullable enable

using System;
using System.Management.Automation;
using System.Reflection;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Reproduces a PS function's OWN try{} block around an engine hop: while a try body
/// executes, the engine sets ExecutionContext.PropagateExceptionsToEnclosingStatementBlock,
/// and every statement fault at ANY depth under it (e.g. inside a nested module function
/// like Invoke-Command2) UNWINDS instead of writing-and-continuing (the W1-044/W1-045
/// statement-fault-conditional lab facts). A C# try around an InvokeScript hop is invisible
/// to that machinery, so this scope sets the engine's own flag for the hop's duration -
/// the reflected-engine-internals precedent (CallerFlow). A missing member degrades to a
/// no-op scope (the fault then surfaces non-terminating, the pre-fix behavior).
/// </summary>
internal sealed class EngineTryScope : IDisposable
{
    private readonly object? _context;
    private readonly PropertyInfo? _flag;
    private readonly object? _saved;

    private EngineTryScope(object? context, PropertyInfo? flag, object? saved)
    {
        _context = context;
        _flag = flag;
        _saved = saved;
    }

    /// <summary>Marks the engine as inside a try body until disposed.</summary>
    internal static EngineTryScope Enter(PSCmdlet host)
    {
        Dataplat.Dbatools.Connection.NativeExecutionGuard.Check(host);
        try
        {
            PropertyInfo? contextProperty = typeof(System.Management.Automation.Internal.InternalCommand).GetProperty("Context", BindingFlags.NonPublic | BindingFlags.Instance);
            object? context = contextProperty?.GetValue(host);
            PropertyInfo? flag = context?.GetType().GetProperty("PropagateExceptionsToEnclosingStatementBlock", BindingFlags.NonPublic | BindingFlags.Instance);
            if (context is null || flag is null || !flag.CanWrite)
                return new EngineTryScope(null, null, null);
            object? saved = flag.GetValue(context);
            flag.SetValue(context, true);
            return new EngineTryScope(context, flag, saved);
        }
        catch
        {
            return new EngineTryScope(null, null, null);
        }
    }

    public void Dispose()
    {
        try
        {
            if (_context is not null && _flag is not null)
                _flag.SetValue(_context, _saved);
        }
        catch
        {
            // restoring a reflected engine flag is best-effort by construction
        }
    }
}
