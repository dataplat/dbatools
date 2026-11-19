using System;
using System.Management.Automation;
using System.Reflection;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// Surfaces a statement-terminating fault with the ENGINE's conditional semantics
    /// (lab-pinned 2026-07-13, the W1-044 S08-vs-S09 split): the record is written and
    /// execution continues with the next statement, UNLESS a caller try/trap encloses the
    /// invocation - then the command unwinds at the faulting statement. The engine consults
    /// its internal PropagateExceptionsToEnclosingStatementBlock flag for that decision; the
    /// same reflected flag is read here (the CallerFlow engine-internals precedent).
    /// </summary>
    internal static class StatementFault
    {
        /// <summary>Surfaces the record: WriteError normally, terminating under a caller try.</summary>
        internal static void Surface(PSCmdlet host, ErrorRecord record)
        {
            if (CallerHasEnclosingTry(host))
                host.ThrowTerminatingError(record);
            else
                host.WriteError(record);
        }

        /// <summary>Exception flavor: rebuilds the engine-shaped record first (a flattened
        /// ParentContainsErrorRecordException record keeps its errorId/category/target but the
        /// visible exception is a plain RuntimeException wrap, the engine's own shape).</summary>
        internal static void Surface(PSCmdlet host, Exception fault, string fallbackErrorId)
        {
            Surface(host, Record(fault, fallbackErrorId));
        }

        /// <summary>Builds the statement-fault record for a caught exception.</summary>
        internal static ErrorRecord Record(Exception fault, string fallbackErrorId)
        {
            ErrorRecord inner = (fault as IContainsErrorRecord)?.ErrorRecord;
            if (inner != null && !(inner.Exception is ParentContainsErrorRecordException))
                return inner;
            if (inner != null)
                return new ErrorRecord(new RuntimeException(fault.Message, fault), FirstErrorIdComponent(inner.FullyQualifiedErrorId, fallbackErrorId), inner.CategoryInfo.Category, inner.TargetObject);
            return new ErrorRecord(fault, fallbackErrorId, ErrorCategory.NotSpecified, null);
        }

        /// <summary>Whether a caller try/trap encloses the invocation (the engine's own
        /// decision flag, reflected). A missing member reads false - the no-try default.</summary>
        internal static bool CallerHasEnclosingTry(PSCmdlet host)
        {
            try
            {
                PropertyInfo contextProperty = typeof(System.Management.Automation.Internal.InternalCommand).GetProperty("Context", BindingFlags.NonPublic | BindingFlags.Instance);
                object context = contextProperty?.GetValue(host);
                PropertyInfo flag = context?.GetType().GetProperty("PropagateExceptionsToEnclosingStatementBlock", BindingFlags.NonPublic | BindingFlags.Instance);
                if (context is null || flag is null)
                    return false;
                return flag.GetValue(context) is bool value && value;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>Whether both reflected members resolve: InternalCommand's non-public instance property
        /// Context, and the non-public instance bool property PropagateExceptionsToEnclosingStatementBlock on
        /// that property's type. False means every Surface writes and goes on, whatever the caller's try; the
        /// engine checks (dbatools.Tests StatementFaultEngineTest and tests/native/StatementFault.Engine.Native.Tests.ps1)
        /// fail on it.</summary>
        internal static bool EngineFlagAvailable()
        {
            PropertyInfo contextProperty = typeof(System.Management.Automation.Internal.InternalCommand).GetProperty("Context", BindingFlags.NonPublic | BindingFlags.Instance);
            PropertyInfo flag = contextProperty?.PropertyType.GetProperty("PropagateExceptionsToEnclosingStatementBlock", BindingFlags.NonPublic | BindingFlags.Instance);
            return !(flag is null) && flag.PropertyType == typeof(bool);
        }

        private static string FirstErrorIdComponent(string fullyQualifiedErrorId, string fallbackErrorId)
        {
            if (string.IsNullOrEmpty(fullyQualifiedErrorId))
                return fallbackErrorId;
            int comma = fullyQualifiedErrorId.IndexOf(',');
            return comma < 0 ? fullyQualifiedErrorId : fullyQualifiedErrorId.Substring(0, comma);
        }
    }
}
