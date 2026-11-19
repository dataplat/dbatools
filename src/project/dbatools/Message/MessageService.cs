using System;
using Dataplat.Dbatools.Exceptions;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Message
{
    /// <summary>
    /// The shared message-processing engine behind both the Write-Message cmdlet and
    /// DbaBaseCmdlet.WriteMessage/StopFunction. It replicates the Write-Message pipeline
    /// (level resolution, transforms, formatting, channel routing, LogHost writes, message
    /// events) while emitting through the ACTING cmdlet's own streams so that
    /// -WarningVariable/-WarningAction bind to the cmdlet the user called (BP-606).
    /// </summary>
    public static class MessageService
    {
        /// <summary>
        /// A single message write request. FunctionName/ModuleName identify the logical
        /// dbatools command for Get-DbatoolsLog parity.
        /// </summary>
        public class MessageRequest
        {
            /// <summary>The message level; Warning routes to the warning channel.</summary>
            public MessageLevel Level = MessageLevel.Verbose;

            /// <summary>The message text (color tags allowed, stripped for logs).</summary>
            public string Message;

            /// <summary>The logical command name, e.g. Get-DbaMaxMemory.</summary>
            public string FunctionName = "<Unknown>";

            /// <summary>The logical module name; Stop-Function parity hardcodes dbatools.</summary>
            public string ModuleName = "dbatools";

            /// <summary>Message tags for filtering.</summary>
            public string[] Tag;

            /// <summary>The object the message is about.</summary>
            public object Target;

            /// <summary>Optional inner exception.</summary>
            public Exception Exception;

            /// <summary>Optional error records to log alongside the message.</summary>
            public ErrorRecord[] ErrorRecord;

            /// <summary>Whether the calling command runs with exceptions enabled.</summary>
            public bool EnableException;

            /// <summary>When true, exception text is not appended to the message.</summary>
            public bool OverrideExceptionMessage;

            /// <summary>
            /// Replicates the 3&gt;$null redirection Stop-Function applies under
            /// EnableException: the warning is logged but not written to the warning stream.
            /// </summary>
            public bool SuppressWarningDisplay;

            /// <summary>
            /// True when the request comes from StopFunction: transforms were already applied
            /// and error records are the caller's responsibility, matching the PS behavior of
            /// Write-Message when called by Stop-Function.
            /// </summary>
            public bool FromStopFunction;

            /// <summary>Source file for the log entry.</summary>
            public string File;

            /// <summary>Source line for the log entry.</summary>
            public int Line;
        }

        /// <summary>
        /// Processes one message request in the context of the acting cmdlet: applies
        /// transforms, unifies exception/error records, routes to the warning/host/verbose/
        /// debug channels through the cmdlet's own APIs, writes LogHost entries and fires
        /// message event subscriptions. Mirrors WriteMessageCommand.ProcessRecord.
        /// </summary>
        /// <param name="cmdlet">The cmdlet whose streams receive the output</param>
        /// <param name="request">The message request</param>
        public static void Write(PSCmdlet cmdlet, MessageRequest request)
        {
            if (cmdlet == null)
                throw new ArgumentNullException("cmdlet");
            if (request == null)
                throw new ArgumentNullException("request");

            DateTime timestamp = DateTime.Now;
            List<string> tags = new List<string>();
            if (request.Tag != null)
                tags.AddRange(request.Tag);

            bool silent = MessageHost.DisableVerbosity;

            if (!request.FromStopFunction && request.Target != null)
                request.Target = ResolveTarget(cmdlet, request, request.Target);

            if (!request.FromStopFunction)
            {
                if (request.Exception != null)
                    request.Exception = ResolveException(cmdlet, request, request.Exception);
                else if (request.ErrorRecord != null)
                {
                    for (int n = 0; n < request.ErrorRecord.Length; n++)
                    {
                        Exception tempException = ResolveException(cmdlet, request, request.ErrorRecord[n].Exception);
                        if (tempException != request.ErrorRecord[n].Exception)
                            request.ErrorRecord[n] = new ErrorRecord(tempException, request.ErrorRecord[n].FullyQualifiedErrorId, request.ErrorRecord[n].CategoryInfo.Category, request.ErrorRecord[n].TargetObject);
                    }
                }
            }

            MessageLevel level = request.Level;
            if (level != MessageLevel.Warning)
                level = ResolveLevel(level, request, tags);

            // Unify exception input into an error record, exactly as Write-Message does.
            if (request.ErrorRecord == null && request.Exception != null)
            {
                request.ErrorRecord = new ErrorRecord[1];
                request.ErrorRecord[0] = new ErrorRecord(request.Exception, String.Format("{0}_{1}", request.ModuleName, request.FunctionName), ErrorCategory.NotSpecified, request.Target);
            }

            string messageSimple = GetMessageSimple(request);
            string messageStreams = GetMessage(request, timestamp, messageSimple);

            Guid runspaceId = Guid.Empty;
            if (System.Management.Automation.Runspaces.Runspace.DefaultRunspace != null)
                runspaceId = System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId;

            if (request.ErrorRecord != null)
            {
                // From cmdlets the EnableException error-record write is StopFunction's job
                // (FromStopFunction is always true on that path), so only logging happens here.
                if (!request.FromStopFunction && request.EnableException)
                    foreach (ErrorRecord record in request.ErrorRecord)
                        cmdlet.WriteError(record);

                LogHost.WriteErrorEntry(request.ErrorRecord, request.FunctionName, request.ModuleName, tags, timestamp, messageSimple, runspaceId, Environment.MachineName);
            }

            LogEntryType channels = LogEntryType.None;

            if (request.Level == MessageLevel.Warning)
            {
                if (!silent)
                {
                    if (request.SuppressWarningDisplay)
                    {
                        // Stop-Function under EnableException calls Write-Message with 3>$null:
                        // the record never DISPLAYS, but every enclosing -WarningVariable still
                        // captures it (lab-proven, ConvertTo-DbaDataTable S10 smoke). Writing
                        // under a temporary WarningPreference swap reproduces both halves; a
                        // caller-bound -WarningAction overrides the variable either way, which
                        // matches the record being suppressed-but-captured there too.
                        object oldWarningPreference = cmdlet.SessionState.PSVariable.GetValue("WarningPreference");
                        try
                        {
                            cmdlet.SessionState.PSVariable.Set("WarningPreference", ActionPreference.SilentlyContinue);
                            cmdlet.WriteWarning(messageStreams);
                        }
                        finally
                        {
                            cmdlet.SessionState.PSVariable.Set("WarningPreference", oldWarningPreference);
                        }
                    }
                    else
                    {
                        cmdlet.WriteWarning(messageStreams);
                    }
                    // The PS Write-Message cannot see the caller's redirect, so the Warning
                    // channel is logged in both modes.
                    channels = channels | LogEntryType.Warning;
                }
                WriteDebugWithoutInquire(cmdlet, messageStreams);
                channels = channels | LogEntryType.Debug;
            }

            if (!silent)
            {
                if ((MessageHost.MaximumInformation >= (int)level) && (MessageHost.MinimumInformation <= (int)level))
                {
                    try
                    {
                        cmdlet.Host.UI.WriteLine(MessageHost.InfoColor, cmdlet.Host.UI.RawUI.BackgroundColor, messageStreams);
                    }
                    catch
                    {
                        // Hosts without a UI (runspaces, jobs) cannot take information lines;
                        // the message still reaches the log below, matching -ErrorAction Ignore
                        // on the PS Write-HostColor call.
                    }
                    channels = channels | LogEntryType.Information;
                }
            }

            if ((MessageHost.MaximumVerbose >= (int)level) && (MessageHost.MinimumVerbose <= (int)level))
            {
                cmdlet.WriteVerbose(messageStreams);
                channels = channels | LogEntryType.Verbose;
            }

            if ((MessageHost.MaximumDebug >= (int)level) && (MessageHost.MinimumDebug <= (int)level))
            {
                WriteDebugWithoutInquire(cmdlet, messageStreams);
                channels = channels | LogEntryType.Debug;
            }

            IEnumerable<CallStackFrame> callStack = NativeCallStack.Capture();

            LogEntry entry = LogHost.WriteLogEntry(messageSimple, channels, timestamp, request.FunctionName, request.ModuleName, tags, level, runspaceId, Environment.MachineName, request.File, request.Line, callStack, String.Format("{0}\\{1}", Environment.UserDomainName, Environment.UserName), request.Target);

            foreach (MessageEventSubscription subscription in MessageHost.Events.Values)
                if (subscription.Applies(entry))
                {
                    var error = new NotSupportedException(String.Format(
                        "Native message processing does not support script event '{0}' for {1} in module {2}.",
                        subscription.Name, request.FunctionName, request.ModuleName));
                    cmdlet.WriteError(new ErrorRecord(error, "NativeMessageEventNotSupported", ErrorCategory.InvalidOperation, subscription.Name));
                }
        }

        private static void WriteDebugWithoutInquire(PSCmdlet cmdlet, string message)
        {
            cmdlet.WriteDebug(message);
        }

        /// <summary>
        /// Walks the inner-exception chain of an error record, deepest first (capped at five
        /// levels like the PS original), returning the first non-empty message. Replicates
        /// private/functions/Get-ErrorMessage.ps1.
        /// </summary>
        /// <param name="record">The error record to interpret</param>
        /// <returns>The deepest meaningful exception message</returns>
        public static string GetErrorMessage(ErrorRecord record)
        {
            if (record == null || record.Exception == null)
                return null;

            List<Exception> chain = new List<Exception>();
            Exception current = record.Exception;
            while (current != null && chain.Count < 6)
            {
                chain.Add(current);
                current = current.InnerException;
            }
            for (int i = chain.Count - 1; i >= 0; i--)
            {
                if (!String.IsNullOrEmpty(chain[i].Message))
                    return chain[i].Message;
            }
            // The pinned helper finally returns the outer message, including an empty string.
            return record.Exception.Message;
        }

        /// <summary>
        /// Applies the registered target transforms for a message context. Public because
        /// StopFunction applies transforms itself before building records, mirroring the PS
        /// division of labor between Stop-Function and Write-Message.
        /// </summary>
        /// <param name="cmdlet">The acting cmdlet; retained for source compatibility</param>
        /// <param name="request">The message request supplying function/module names</param>
        /// <param name="item">The target to transform</param>
        /// <returns>The transformed target, or the input when no transform applies</returns>
        public static object ResolveTarget(PSCmdlet cmdlet, MessageRequest request, object item)
        {
            if (item == null)
                return null;

            string lowTypeName = item.GetType().FullName.ToLower();
            // Library-owned legacy defaults are ignored; a matching caller registration is rejected.
            if (LegacyTransformOwnership.HasCallerRegistration(TransformType.Target, lowTypeName, request.ModuleName, request.FunctionName))
                throw new NotSupportedException(String.Format(
                    "Native message target transforms do not support script registrations for type {0}, function {1}, module {2}. Remove the matching legacy registration or use the explicit legacy frontend.",
                    lowTypeName, request.FunctionName, request.ModuleName));

            NativeMessageTransform descriptor;
            if (!MessageHost.NativeTargetTransforms.TryGetValue(lowTypeName, out descriptor))
            {
                NativeTransformCondition condition = MessageHost.NativeTargetTransformList.Get(lowTypeName, request.ModuleName, request.FunctionName);
                if (condition == null)
                    return item;
                descriptor = condition.Transform;
            }

            Guid runspaceId = Guid.Empty;
            if (System.Management.Automation.Runspaces.Runspace.DefaultRunspace != null)
                runspaceId = System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId;
            try { return BuiltinMessageTransforms.TransformTarget(descriptor, item); }
            catch (Exception e) when (!NativeMetadataException.IsInChain(e))
            {
                MessageHost.WriteTransformError(new ErrorRecord(e, "Write-Message", ErrorCategory.OperationStopped, null), request.FunctionName, request.ModuleName, item, TransformType.Target, runspaceId);
                return item;
            }
        }

        /// <summary>
        /// Collapses a resolved target the way Stop-Function's pipeline assignment of
        /// Convert-DbaMessageTarget does: no output becomes null, one output is unwrapped,
        /// several become an array. Untransformed targets are returned unchanged.
        /// </summary>
        /// <param name="target">The value returned by ResolveTarget</param>
        /// <returns>The collapsed target</returns>
        public static object CollapseTarget(object target)
        {
            System.Collections.ObjectModel.Collection<PSObject> outputs = target as System.Collections.ObjectModel.Collection<PSObject>;
            if (outputs == null)
                return target;
            if (outputs.Count == 0)
                return null;
            if (outputs.Count == 1)
                return UnwrapTarget(outputs[0]);
            object[] targets = new object[outputs.Count];
            for (int index = 0; index < targets.Length; index++)
                targets[index] = UnwrapTarget(outputs[index]);
            return targets;
        }

        private static object UnwrapTarget(PSObject item)
        {
            if (item == null)
                return null;
            // A custom object's properties live on its wrapper, not its placeholder base.
            return item.BaseObject is PSCustomObject ? item : item.BaseObject;
        }

        /// <summary>
        /// Applies the registered exception transforms for a message context. Public because
        /// StopFunction applies transforms itself before building records (FromStopFunction
        /// requests skip the transform pass here), mirroring the PS division of labor.
        /// </summary>
        /// <param name="cmdlet">The acting cmdlet; retained for source compatibility</param>
        /// <param name="request">The message request supplying function/module names</param>
        /// <param name="item">The exception to transform</param>
        /// <returns>The transformed exception, or the input when no transform applies</returns>
        public static Exception ResolveException(PSCmdlet cmdlet, MessageRequest request, Exception item)
        {
            if (item == null)
                return null;

            string lowTypeName = item.GetType().FullName.ToLower();
            // Library-owned legacy defaults are ignored; a matching caller registration is rejected
            // and the original exception stays attached for diagnosis.
            if (LegacyTransformOwnership.HasCallerRegistration(TransformType.Exception, lowTypeName, request.ModuleName, request.FunctionName))
                throw new NotSupportedException(String.Format(
                    "Native message exception transforms do not support script registrations for type {0}, function {1}, module {2}. Remove the matching legacy registration or use the explicit legacy frontend.",
                    lowTypeName, request.FunctionName, request.ModuleName), item);

            NativeMessageTransform descriptor;
            if (!MessageHost.NativeExceptionTransforms.TryGetValue(lowTypeName, out descriptor))
            {
                NativeTransformCondition condition = MessageHost.NativeExceptionTransformList.Get(lowTypeName, request.ModuleName, request.FunctionName);
                if (condition == null)
                    return item;
                descriptor = condition.Transform;
            }

            Guid runspaceId = Guid.Empty;
            if (System.Management.Automation.Runspaces.Runspace.DefaultRunspace != null)
                runspaceId = System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId;
            try { return BuiltinMessageTransforms.TransformException(descriptor, item); }
            catch (Exception e) when (!NativeMetadataException.IsInChain(e))
            {
                MessageHost.WriteTransformError(new ErrorRecord(e, "Write-Message", ErrorCategory.OperationStopped, null), request.FunctionName, request.ModuleName, item, TransformType.Exception, runspaceId);
                return item;
            }
        }

        private static MessageLevel ResolveLevel(MessageLevel level, MessageRequest request, List<string> tags)
        {
            int tempLevel = (int)level;

            // NestedLevelDecrement operates on PS callstack depth; binary cmdlets have no
            // meaningful PS stack depth of their own, so a cmdlet message counts as depth 0.
            if (MessageHost.MessageLevelModifiers.Count > 0)
                foreach (MessageLevelModifier modifier in MessageHost.MessageLevelModifiers.Values)
                    if (modifier.AppliesTo(request.FunctionName, request.ModuleName, tags))
                        tempLevel = tempLevel + modifier.Modifier;

            if (tempLevel > 9)
                tempLevel = 9;
            if (tempLevel < 1)
                tempLevel = 1;

            return (MessageLevel)tempLevel;
        }

        private static string GetErrorQualifiedMessage(MessageRequest request)
        {
            if (request.ErrorRecord == null || request.ErrorRecord.Length == 0)
                return request.Message;
            if (request.OverrideExceptionMessage)
                return request.Message;
            if (request.ErrorRecord[0].Exception == null)
                return request.Message;
            if (Regex.IsMatch(request.Message ?? "", Regex.Escape(request.ErrorRecord[0].Exception.Message)))
                return request.Message;
            return String.Format("{0} | {1}", request.Message, request.ErrorRecord[0].Exception.Message);
        }

        private static string GetMessageSimple(MessageRequest request)
        {
            string baseMessage = GetErrorQualifiedMessage(request) ?? "";
            foreach (Match match in Regex.Matches(baseMessage, "<c=[\"'](.*?)[\"']>(.*?)</c>"))
                baseMessage = Regex.Replace(baseMessage, Regex.Escape(match.Value), match.Groups[2].Value);
            return baseMessage;
        }

        private static string GetMessage(MessageRequest request, DateTime timestamp, string messageSimple)
        {
            // Breadcrumbs need a PS callstack; cmdlet-originated messages use the
            // timestamp/command prefixes only, matching the non-breadcrumb formats.
            if (MessageHost.EnableMessageTimestamp && MessageHost.EnableMessageDisplayCommand)
                return String.Format("[{0}][{1}] {2}", timestamp.ToString("HH:mm:ss"), request.FunctionName, messageSimple);
            if (MessageHost.EnableMessageTimestamp)
                return String.Format("[{0}] {1}", timestamp.ToString("HH:mm:ss"), messageSimple);
            if (MessageHost.EnableMessageDisplayCommand)
                return String.Format("[{0}] {1}", request.FunctionName, messageSimple);
            return messageSimple;
        }
    }
}
