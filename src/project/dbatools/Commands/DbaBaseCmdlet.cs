using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using System.Text.RegularExpressions;
using System.Threading;
using Dataplat.Dbatools.Message;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// The mandatory base class for every ported dbatools cmdlet (BP-002). Provides the
    /// EnableException surface, the Interrupted stop flag, WriteMessage/StopFunction with
    /// exact Stop-Function parity, TestBound helpers and cooperative Ctrl-C cancellation.
    /// Contract: migration/specs/architecture.md section 2.
    /// </summary>
    public abstract class DbaBaseCmdlet : PSCmdlet, INestedCommandInterruptHost
    {
        /// <summary>By default, dbatools handles errors as friendly warnings. This switch enables terminating exceptions instead.
        /// Virtual so a port whose PS function declares EnableException PER PARAMETER SET can override
        /// it with the per-set [Parameter] attributes (the binder reads the most-derived declaration's
        /// attributes) while StopFunction/WriteMessage keep reading the bound value via virtual dispatch.</summary>
        [Parameter]
        public virtual SwitchParameter EnableException { get; set; }

        /// <summary>Set when StopFunction decided the cmdlet must stop. Guard ProcessRecord/EndProcessing with it. Never reset.</summary>
        protected bool Interrupted { get; private set; }

        void INestedCommandInterruptHost.InterruptFromNestedCommand()
        {
            Interrupted = true;
        }

        private readonly CancellationTokenSource _cancellationSource = new CancellationTokenSource();

        /// <summary>Cooperative cancellation token; long-running loops check it at iteration boundaries.</summary>
        protected CancellationToken CancellationToken
        {
            get { return _cancellationSource.Token; }
        }

        private volatile SqlCommand _activeCommand;
        private volatile ServerConnection _activeConnection;

        /// <summary>Registers (or clears, with null) the SqlCommand in flight so Ctrl-C can cancel it.</summary>
        /// <param name="command">The command about to execute, or null to clear</param>
        protected void SetActiveCommand(SqlCommand command)
        {
            _activeCommand = command;
        }

        /// <summary>Registers (or clears, with null) the ServerConnection in flight so Ctrl-C can cancel it.</summary>
        /// <param name="connection">The connection in use, or null to clear</param>
        protected void SetActiveConnection(ServerConnection connection)
        {
            _activeConnection = connection;
        }

        /// <summary>
        /// Sealed so derived cmdlets cannot break Ctrl-C: cancels the token and any in-flight
        /// SQL work registered through SetActiveCommand/SetActiveConnection.
        /// </summary>
        protected sealed override void StopProcessing()
        {
            _cancellationSource.Cancel();
            try
            {
                SqlCommand command = _activeCommand;
                if (command != null)
                    command.Cancel();
            }
            catch
            {
                // connection may already be gone
            }
            try
            {
                ServerConnection connection = _activeConnection;
                if (connection != null)
                    connection.Cancel();
            }
            catch
            {
                // ditto
            }
        }

        /// <summary>
        /// Single messaging entry point replacing Write-Message. Routes through
        /// MessageService so channel thresholds, formatting and Get-DbatoolsLog output are
        /// indistinguishable from the PS implementation, while warnings/verbose/debug emit
        /// through THIS cmdlet's streams (BP-606).
        /// </summary>
        /// <param name="level">The message level</param>
        /// <param name="message">The message text, verbatim from the PS source</param>
        /// <param name="target">The object the message is about</param>
        /// <param name="exception">An inner exception to log</param>
        /// <param name="tag">Message tags</param>
        protected void WriteMessage(MessageLevel level, string message, object target = null, Exception exception = null, string[] tag = null)
        {
            WriteAttributedMessage(GetCommandName(), level, message, target, exception, tag);
        }

        /// <summary>
        /// Routes a message through this cmdlet's streams while preserving the source helper's
        /// function attribution. Used by native service seams such as ConnectInstance, where the
        /// retired function emitted messages from Connect-DbaInstance.
        /// </summary>
        protected void WriteAttributedMessage(string functionName, MessageLevel level, string message,
            object target = null, Exception exception = null, string[] tag = null)
        {
            MessageService.MessageRequest request = new MessageService.MessageRequest();
            request.Level = level;
            request.Message = message;
            request.FunctionName = functionName;
            request.ModuleName = "dbatools";
            request.Target = target;
            request.Exception = exception;
            request.Tag = tag;
            request.EnableException = EnableException.ToBool();
            request.File = MyInvocation.ScriptName;
            request.Line = MyInvocation.ScriptLineNumber;
            MessageService.Write(this, request);
        }

        /// <summary>
        /// Replicates private/functions/flowcontrol/Stop-Function.ps1 exactly, including its
        /// quirks (truth table in migration/specs/architecture.md section 2.3). Never returns
        /// a value; every call site carries the control-flow statement the PS source shape
        /// dictates (return/continue), except under EnableException where the non-continue
        /// paths throw a terminating error.
        /// </summary>
        /// <param name="message">The user-facing failure message, verbatim from the PS source</param>
        /// <param name="target">The object being processed when the failure occurred</param>
        /// <param name="errorRecord">The caught error record, when called from a catch block</param>
        /// <param name="exception">An explicit inner exception; wins over errorRecord's exception</param>
        /// <param name="category">The error category the PS call site passed</param>
        /// <param name="continueLoop">The -Continue translation; call site runs continue;</param>
        /// <param name="silentlyContinue">The -SilentlyContinue translation; see truth table</param>
        /// <param name="overrideExceptionMessage">Disables appending exception text to the message</param>
        /// <param name="tag">Message tags</param>
        /// <param name="interruptCallerScope">
        /// False when the PS source calls Stop-Function from inside an ABSORBED PRIVATE HELPER
        /// rather than from the command body. Stop-Function sets its stop flag with
        /// Set-Variable -Scope 1, which is the HELPER's scope; Test-FunctionInterrupt reads
        /// -Scope 1 from the COMMAND's scope. When a helper stops, the flag is written to a
        /// scope nobody reads and dies with the helper — so in non-EnableException mode the
        /// command continues through begin AND process. Absorbing the helper into a private
        /// C# method loses that scope boundary, and the instance-level flag would wrongly
        /// halt the command. EnableException is unaffected: it throws terminating either way.
        /// </param>
        protected void StopFunction(string message,
            object target = null,
            ErrorRecord errorRecord = null,
            Exception exception = null,
            ErrorCategory category = ErrorCategory.NotSpecified,
            bool continueLoop = false,
            bool silentlyContinue = false,
            bool overrideExceptionMessage = false,
            string[] tag = null,
            bool interruptCallerScope = true)
        {
            StopAttributedFunction(GetCommandName(), message, target, errorRecord, exception, category,
                continueLoop, silentlyContinue, overrideExceptionMessage, tag, interruptCallerScope);
        }

        /// <summary>Preserves an absorbed native helper's Stop-Function attribution.</summary>
        protected void StopAttributedFunction(string functionName, string message,
            object target = null,
            ErrorRecord errorRecord = null,
            Exception exception = null,
            ErrorCategory category = ErrorCategory.NotSpecified,
            bool continueLoop = false,
            bool silentlyContinue = false,
            bool overrideExceptionMessage = false,
            string[] tag = null,
            bool interruptCallerScope = true)
        {
            bool enableException = EnableException.ToBool();
            List<ErrorRecord> records = WriteStopFunctionMessage(functionName, message, target, errorRecord, exception, category,
                overrideExceptionMessage, tag, enableException);

            if (enableException)
            {
                if (silentlyContinue)
                {
                    // Visible non-terminating errors; the call site continues the loop and
                    // Interrupted stays false.
                    foreach (ErrorRecord record in records)
                        WriteError(record);
                    return;
                }

                // -Continue under EnableException STILL terminates (quirk preserved).
                Interrupted = true;
                ThrowTerminatingError(records[0]);
            }

            // Non-EnableException mode: the record lands in $error without being displayed
            // (the PS source runs $null = Write-Error ... 2>&1).
            foreach (ErrorRecord record in records)
            {
                InsertGlobalError(record);
                CaptureErrorVariable(record);
            }

            if (continueLoop)
                return;

            // A Stop-Function inside an absorbed helper writes its flag to the helper's scope,
            // which the command never reads — warn-and-continue, not stop. See the parameter doc.
            if (!interruptCallerScope)
                return;

            // Make sure the function knows it should be stopping
            Interrupted = true;
        }

        /// <summary>
        /// Stop-Function under -EnableException inside an absorbed nested dbatools command whose
        /// PS caller catches the throw (try { Get-DbaX ... -EnableException } catch { ... }): the
        /// message is logged without display, the thrown record lands in $error as a caught
        /// terminating error does, and the record is returned for the caller's catch to use as $_.
        /// Nothing is thrown and Interrupted is untouched: the nested command's stop flag lives in
        /// its own scope.
        /// </summary>
        /// <param name="functionName">The nested command's name</param>
        /// <param name="message">The nested Stop-Function message, verbatim from the PS source</param>
        /// <param name="target">The nested Stop-Function -Target</param>
        /// <param name="errorRecord">The nested Stop-Function -ErrorRecord</param>
        /// <param name="category">The nested Stop-Function -Category</param>
        /// <param name="overrideExceptionMessage">The nested Stop-Function -OverrideExceptionMessage: the message
        /// is shown without the record's exception text after it</param>
        /// <returns>The record the nested Stop-Function throws</returns>
        protected ErrorRecord CaughtNestedStopFunction(string functionName, string message,
            object target = null,
            ErrorRecord errorRecord = null,
            ErrorCategory category = ErrorCategory.NotSpecified,
            bool overrideExceptionMessage = false)
        {
            List<ErrorRecord> records = WriteStopFunctionMessage(functionName, message, target, errorRecord, null, category,
                overrideExceptionMessage, null, true);
            InsertGlobalError(records[0]);
            CaptureErrorVariable(records[0]);
            return records[0];
        }

        /// <summary>
        /// Stop-Function -Continue inside an absorbed nested dbatools command the PS source calls
        /// without -EnableException: whatever this cmdlet's own -EnableException, the warning shows
        /// under the nested command's name and the record lands in $error. Nothing is thrown and
        /// Interrupted is untouched: the nested command's stop flag lives in its own scope.
        /// </summary>
        /// <param name="functionName">The nested command's name</param>
        /// <param name="message">The nested Stop-Function message, verbatim from the PS source</param>
        /// <param name="target">The nested Stop-Function -Target</param>
        /// <param name="errorRecord">The nested Stop-Function -ErrorRecord</param>
        /// <param name="category">The nested Stop-Function -Category</param>
        /// <param name="overrideExceptionMessage">The nested Stop-Function -OverrideExceptionMessage: the warning shows
        /// the message without the record's exception text after it; the record is kept</param>
        protected void WarnNestedStopFunction(string functionName, string message,
            object target = null,
            ErrorRecord errorRecord = null,
            ErrorCategory category = ErrorCategory.NotSpecified,
            bool overrideExceptionMessage = false)
        {
            List<ErrorRecord> records = WriteStopFunctionMessage(functionName, message, target, errorRecord, null, category,
                overrideExceptionMessage, null, false);
            foreach (ErrorRecord record in records)
            {
                InsertGlobalError(record);
                CaptureErrorVariable(record);
            }
        }

        /// <summary>A connection target's text for a message, with any connection-string password masked.</summary>
        /// <param name="target">The connection target; not null</param>
        /// <returns>The target's text</returns>
        protected static string MaskedTargetText(object target)
        {
            string text = target.ToString();
            if (Regex.IsMatch(text, "(?i)(password|pwd)\\s*="))
                text = Regex.Replace(text, "(?i)(password|pwd)(\\s*=\\s*)[^;]*", "$1$2****");
            return text;
        }

        // Stop-Function's record building and Write-Message call, shared by every stop path.
        private List<ErrorRecord> WriteStopFunctionMessage(string functionName, string message,
            object target,
            ErrorRecord errorRecord,
            Exception exception,
            ErrorCategory category,
            bool overrideExceptionMessage,
            string[] tag,
            bool enableException)
        {
            // Stop-Function hardcodes the module name for Get-DbatoolsLog parity.
            string moduleName = "dbatools";

            MessageService.MessageRequest transformContext = new MessageService.MessageRequest();
            transformContext.FunctionName = functionName;
            transformContext.ModuleName = moduleName;

            // Connect-*Instance failures mask connection-string targets before display.
            object displayTarget = target;
            string instanceText = null;
            if (target != null && Regex.IsMatch(functionName, "Connect-.*Instance"))
                instanceText = MaskedTargetText(target);

            if (displayTarget != null)
            {
                // Convert-DbaMessageTarget returns through the PowerShell pipeline before
                // Stop-Function assigns its result, collapsing zero/one/many outputs.
                displayTarget = MessageService.CollapseTarget(MessageService.ResolveTarget(this, transformContext, displayTarget));
            }

            ErrorRecord[] inputRecords = null;
            if (errorRecord != null)
                inputRecords = new ErrorRecord[] { errorRecord };

            if (exception != null)
                exception = MessageService.ResolveException(this, transformContext, exception);
            else if (inputRecords != null)
            {
                for (int n = 0; n < inputRecords.Length; n++)
                {
                    Exception tempException = MessageService.ResolveException(this, transformContext, inputRecords[n].Exception);
                    if (tempException != inputRecords[n].Exception)
                        inputRecords[n] = new ErrorRecord(tempException, inputRecords[n].FullyQualifiedErrorId, inputRecords[n].CategoryInfo.Category, inputRecords[n].TargetObject);
                }
            }

            List<ErrorRecord> records = new List<ErrorRecord>();
            bool messageOverridesException = overrideExceptionMessage;

            if (inputRecords != null || exception != null)
            {
                if (inputRecords != null)
                {
                    foreach (ErrorRecord record in inputRecords)
                    {
                        string msg = MessageService.GetErrorMessage(record);
                        if (instanceText != null)
                            msg = String.Format("Error connecting to [{0}]: {1}", instanceText, msg);
                        Exception newException;
                        if (exception == null)
                            newException = new Exception(msg, record.Exception);
                        else
                            newException = exception;

                        // PS: if ($record.CategoryInfo.Category) - NotSpecified (0) is falsy,
                        // so only a real category on the input record overrides the argument.
                        ErrorCategory effectiveCategory = category;
                        if (record.CategoryInfo.Category != ErrorCategory.NotSpecified)
                            effectiveCategory = record.CategoryInfo.Category;

                        records.Add(new ErrorRecord(newException, String.Format("{0}_{1}", moduleName, functionName), effectiveCategory, displayTarget));
                    }
                }
                else
                {
                    records.Add(new ErrorRecord(exception, String.Format("{0}_{1}", moduleName, functionName), category, displayTarget));
                }
            }
            else
            {
                records.Add(new ErrorRecord(new Exception(message), String.Format("dbatools_{0}", functionName), category, displayTarget));
                // The plain path always overrides: the message IS the exception text.
                messageOverridesException = true;
            }

            MessageService.MessageRequest request = new MessageService.MessageRequest();
            request.Level = MessageLevel.Warning;
            request.Message = message;
            request.FunctionName = functionName;
            request.ModuleName = moduleName;
            request.Tag = tag;
            request.Target = displayTarget;
            request.ErrorRecord = records.ToArray();
            request.EnableException = enableException;
            request.OverrideExceptionMessage = messageOverridesException;
            // Stop-Function redirects the warning stream to null under EnableException (3>$null).
            request.SuppressWarningDisplay = enableException;
            request.FromStopFunction = true;
            request.File = MyInvocation.ScriptName;
            request.Line = MyInvocation.ScriptLineNumber;
            MessageService.Write(this, request);
            return records;
        }

        /// <summary>Whether the named parameter was explicitly bound by the caller.</summary>
        /// <param name="parameterName">The parameter name</param>
        /// <returns>True when bound</returns>
        protected bool TestBound(string parameterName)
        {
            return MyInvocation.BoundParameters.ContainsKey(parameterName);
        }

        /// <summary>Whether ANY of the named parameters was explicitly bound.</summary>
        /// <param name="names">The parameter names</param>
        /// <returns>True when at least one is bound</returns>
        protected bool TestBound(params string[] names)
        {
            foreach (string name in names)
            {
                if (MyInvocation.BoundParameters.ContainsKey(name))
                    return true;
            }
            return false;
        }

        /// <summary>Whether ALL of the named parameters were explicitly bound.</summary>
        /// <param name="names">The parameter names</param>
        /// <returns>True when every one is bound</returns>
        protected bool TestBoundAll(params string[] names)
        {
            foreach (string name in names)
            {
                if (!MyInvocation.BoundParameters.ContainsKey(name))
                    return false;
            }
            return true;
        }

        private string GetCommandName()
        {
            if (MyInvocation != null && MyInvocation.MyCommand != null && !String.IsNullOrEmpty(MyInvocation.MyCommand.Name))
                return MyInvocation.MyCommand.Name;
            return GetType().Name;
        }

        private void CaptureErrorVariable(ErrorRecord record)
        {
            try
            {
                object binding;
                if (!MyInvocation.BoundParameters.TryGetValue("ErrorVariable", out binding) ||
                    !(binding is string name) || name.Length == 0)
                    return;
                // The engine initializes the capture list and preserves prior entries for +name.
                if (name[0] == '+')
                    name = name.Substring(1);
                if (name.Length == 0)
                    return;
                ArrayList captured = SessionState.PSVariable.GetValue(name) as ArrayList;
                if (captured == null || ReferenceEquals(captured, SessionState.PSVariable.GetValue("global:Error")))
                    return;
                // Capture only the native StopFunction record; never manufacture engine unwind records.
                captured.Add(record);
            }
            catch
            {
                // As with global error bookkeeping, constrained session state must not break the command.
            }
        }

        private void InsertGlobalError(ErrorRecord record)
        {
            try
            {
                // Write-Error appends to the global list; an unqualified lookup from a
                // module-scoped caller (Pester) resolves to that module's $Error instead.
                ArrayList errorList = SessionState.PSVariable.GetValue("global:Error") as ArrayList;
                if (errorList == null)
                    return;
                errorList.Insert(0, record);

                int maximumErrorCount = 256;
                object maximumRaw = SessionState.PSVariable.GetValue("MaximumErrorCount");
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
                // $error decoration is best-effort: constrained runspaces may deny access,
                // and failing the command over bookkeeping would be worse than the PS
                // behavior it mirrors.
            }
        }
    }
}
