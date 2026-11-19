using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Runtime.CompilerServices;

namespace Dataplat.Dbatools.Message
{
    /// <summary>Captures diagnostic frames without the legacy engine-reflection fallback.</summary>
    internal static class NativeCallStack
    {
        internal static IEnumerable<CallStackFrame> Capture()
        {
            return CaptureFrames(ReadPublicFrames);
        }

        internal static IEnumerable<CallStackFrame> CaptureFrames(Func<IEnumerable<CallStackFrame>> readFrames)
        {
            try
            {
                return readFrames() ?? new CallStackFrame[0];
            }
            catch (MissingMethodException)
            {
                return new CallStackFrame[0];
            }
            catch (TypeLoadException)
            {
                return new CallStackFrame[0];
            }
        }

        // PS3 may fail to bind GetCallStack when this method is JIT-compiled.
        // Keep that failure inside CaptureFrames rather than its caller's JIT.
        [MethodImpl(MethodImplOptions.NoInlining)]
        private static IEnumerable<CallStackFrame> ReadPublicFrames()
        {
            var current = System.Management.Automation.Runspaces.Runspace.DefaultRunspace;
            if (current == null || current.Debugger == null)
                return new CallStackFrame[0];
            return current.Debugger.GetCallStack();
        }
    }
}
