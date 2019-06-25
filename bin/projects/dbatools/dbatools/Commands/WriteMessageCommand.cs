using Sqlcollaborative.Dbatools.Message;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Sqlcollaborative.Dbatools.Commands
{
    /// <summary>
    /// Implements the Write-Message command, performing message handling and loggin
    /// </summary>
    [Cmdlet("Write", "Message")]
    public class WriteMessageCommand : PSCmdlet
    {
        #region Parameters
        /// <summary>
        /// This parameter represents the verbosity of the message. The lower the number, the more important it is for a human user to read the message.
        /// By default, the levels are distributed like this:
        /// - 1-3 Direct verbose output to the user (using Write-Host)
        /// - 4-6 Output only visible when requesting extra verbosity (using Write-Verbose)
        /// - 1-9 Debugging information, written using Write-Debug
        /// 
        /// In addition, it is possible to select the level "Warning" which moves the message out of the configurable range:
        /// The user will always be shown this message, unless he silences the entire verbosity.
        /// 
        /// Possible levels:
        /// Critical (1), Important / Output / Host (2), Significant (3), VeryVerbose (4), Verbose (5), SomewhatVerbose (6), System (7), Debug (8), InternalComment (9), Warning (666)
        /// Either one of the strings or its respective number will do as input.
        /// </summary>
        [Parameter()]
        public MessageLevel Level = MessageLevel.Verbose;

        /// <summary>
        /// The message to write/log. The function name and timestamp will automatically be prepended.
        /// </summary>
        [Parameter(Mandatory = true, Position = 0)]
        [AllowEmptyString]
        [AllowNull]
        public string Message;

        /// <summary>
        /// Tags to add to the message written.
		/// This allows filtering and grouping by category of message, targeting specific messages.
        /// </summary>
        [Parameter()]
        public string[] Tag;

        /// <summary>
        /// The name of the calling function.
		/// Will be automatically set, but can be overridden when necessary.
        /// </summary>
        [Parameter()]
        public string FunctionName;

        /// <summary>
        /// The name of the module, the calling function is part of.
		/// Will be automatically set, but can be overridden when necessary.
        /// </summary>
        [Parameter()]
        public string ModuleName;

        /// <summary>
        /// The file in which Write-Message was called.
		/// Will be automatically set, but can be overridden when necessary.
        /// </summary>
        [Parameter()]
        public string File;

        /// <summary>
        /// The line on which Write-Message was called.
		/// Will be automatically set, but can be overridden when necessary.
        /// </summary>
        [Parameter()]
        public int Line;

        /// <summary>
        /// If an error record should be noted with the message, add the full record here.
		/// Especially designed for use with Warning-mode, it can legally be used in either mode.
        /// The error will be added to the $Error variable and enqued in the logging/debugging system.
        /// </summary>
        [Parameter()]
        public ErrorRecord[] ErrorRecord;

        /// <summary>
        /// Allows specifying an inner exception as input object. This will be passed on to the logging and used for messages.
		/// When specifying both ErrorRecord AND Exception, Exception wins, but ErrorRecord is still used for record metadata.
        /// </summary>
        [Parameter()]
        public Exception Exception;

        /// <summary>
        /// Setting this parameter will cause this function to write the message only once per session.
		/// The string passed here and the calling function's name are used to create a unique ID, which is then used to register the action in the configuration system.
		/// Thus will the lockout only be written if called once and not burden the system unduly.
        /// This lockout will be written as a hidden value, to see it use Get-DbaConfig -Force.
        /// </summary>
        [Parameter()]
        public string Once;

        /// <summary>
        /// Disables automatic appending of exception messages.
		/// Use in cases where you already have a speaking message interpretation and do not need the original message.
        /// </summary>
        [Parameter()]
        public SwitchParameter OverrideExceptionMessage;

        /// <summary>
        /// Add the object the message is all about, in order to simplify debugging / troubleshooting.
		/// For example, when calling this from a function targeting a remote computer, the computername could be specified here, allowing all messages to easily be correlated to the object processed.
        /// </summary>
        [Parameter()]
        public object Target;

        /// <summary>
        /// This parameters disables user-friendly warnings and enables the throwing of exceptions.
		/// This is less user friendly, but allows catching exceptions in calling scripts.
        /// </summary>
        [Parameter()]
        public bool EnableException;

        /// <summary>
        /// Enables breakpoints on the current message. By default, setting '-Debug' will NOT cause an interrupt on the current position.
        /// </summary>
        [Parameter()]
        public SwitchParameter Breakpoint;
        #endregion Parameters

        #region Private fields
        /// <summary>
        /// The start time of the cmdlet
        /// </summary>
        private DateTime _timestamp;

        /// <summary>
        /// Whether this cmdlet is run in silent mode
        /// </summary>
        private bool _silent = false;

        /// <summary>
        /// Whether this cmdlet was called by Stop-Function
        /// </summary>
        private bool _fromStopFunction = false;

        /// <summary>
        /// The current callstack
        /// </summary>
        private IEnumerable<CallStackFrame> _callStack = null;

        /// <summary>
        /// How many items exist on the callstack
        /// </summary>
        private int _stackDepth;

        /// <summary>
        /// The message to write
        /// </summary>
        private string _message;

        /// <summary>
        /// The message simplified without timestamps. Used for logging.
        /// </summary>
        private string _messageSimple;

        /// <summary>
        /// The message to write in color
        /// </summary>
        private string _messageColor;

        /// <summary>
        /// Non-colored version of developermode
        /// </summary>
        private string _messageDeveloper;

        /// <summary>
        /// Colored version of developermode
        /// </summary>
        private string _messageDeveloperColor;

        /// <summary>
        /// Scriptblock that writes the host messages
        /// </summary>
        private static string _writeHostScript = @"
param ( $string )

if ([Sqlcollaborative.Dbatools.Message.MessageHost]::DeveloperMode) { Write-HostColor -String $string -DefaultColor ([Sqlcollaborative.Dbatools.Message.MessageHost]::DeveloperColor) -ErrorAction Ignore }
else { Write-HostColor -String $string -DefaultColor ([Sqlcollaborative.Dbatools.Message.MessageHost]::InfoColor) -ErrorAction Ignore }
";

        /// <summary>
        /// List of tags to process
        /// </summary>
        private List<string> _Tags = new List<string>();

        /// <summary>
        /// Whether debug mode is enabled
        /// </summary>
        private bool _isDebug;
        #endregion Private fields

        #region Private properties
        /// <summary>
        /// The input message with the error content included if desired
        /// </summary>
        private string _errorQualifiedMessage
        {
            get
            {
                if (ErrorRecord == null)
                    return Message;

                if (ErrorRecord.Length == 0)
                    return Message;

                if (OverrideExceptionMessage.ToBool())
                    return Message;

                if (Regex.IsMatch(Message, Regex.Escape(ErrorRecord[0].Exception.Message)))
                    return Message;

                return String.Format("{0} | {1}", Message, ErrorRecord[0].Exception.Message);
            }
        }

        /// <summary>
        /// The final message to use for internal logging
        /// </summary>
        private string _MessageSystem
        {
            get
            {
                return GetMessageSimple();
            }
        }

        /// <summary>
        /// The final message to use for writing to streams, such as verbose or warning
        /// </summary>
        private string _MessageStreams
        {
            get
            {
                if (MessageHost.DeveloperMode)
                    return GetMessageDeveloper();
                else
                    return GetMessage();
            }
        }

        /// <summary>
        /// The final message to use for host messages (write using Write-HostColor)
        /// </summary>
        private string _MessageHost
        {
            get
            {
                if (MessageHost.DeveloperMode)
                    return GetMessageDeveloperColor();
                else
                    return GetMessageColor();
            }
        }

        /// <summary>
        /// Provide breadcrumb queue of the callstack
        /// </summary>
        private string _BreadCrumbsString
        {
            get
            {
                string crumbs = String.Join(" > ", _callStack.Select(name => name.FunctionName).Where(name => name != "Write-Message" && name != "Stop-Function" && name != "<ScriptBlock>").Reverse().ToList());
                if (crumbs.EndsWith(FunctionName))
                    return String.Format("[{0}]\n    ", crumbs);
                return String.Format("[{0}] [{1}]\n    ", crumbs, FunctionName);
            }
        }

        /// <summary>
        /// Provide a breadcrumb queue of the callstack in color tags
        /// </summary>
        private string _BreadCrumbsStringColored
        {
            get
            {
                string crumbs = String.Join("</c> > <c='sub'>", _callStack.Select(name => name.FunctionName).Where(name => name != "Write-Message" && name != "Stop-Function" && name != "<ScriptBlock>").Reverse().ToList());
                if (crumbs.EndsWith(FunctionName))
                    return String.Format("[<c='sub'>{0}</c>]\n    ", crumbs);
                return String.Format("[<c='sub'>{0}</c>] [<c='sub'>{1}</c>]\n    ", crumbs, FunctionName);
            }
        }
        #endregion Private properties

        #region Cmdlet Implementation
        /// <summary>
        /// Processes the begin phase of the cmdlet
        /// </summary>
        protected override void BeginProcessing()
        {
            _timestamp = DateTime.Now;

            #region Resolving Meta Information
            _callStack = Utility.UtilityHost.Callstack;
            CallStackFrame callerFrame = null;
            if (_callStack.Count() > 0)
                callerFrame = _callStack.First();
            _stackDepth = _callStack.Count();

            if (callerFrame != null)
            {
                if (String.IsNullOrEmpty(FunctionName))
                {
                    if (callerFrame.InvocationInfo == null)
                        FunctionName = callerFrame.FunctionName;
                    else if (callerFrame.InvocationInfo.MyCommand == null)
                        FunctionName = callerFrame.InvocationInfo.InvocationName;
                    else if (callerFrame.InvocationInfo.MyCommand.Name != "")
                        FunctionName = callerFrame.InvocationInfo.MyCommand.Name;
                    else
                        FunctionName = callerFrame.FunctionName;
                }

                if (String.IsNullOrEmpty(ModuleName))
                    if ((callerFrame.InvocationInfo != null) && (callerFrame.InvocationInfo.MyCommand != null))
                        ModuleName = callerFrame.InvocationInfo.MyCommand.ModuleName;

                if (String.IsNullOrEmpty(File))
                    File = callerFrame.Position.File;

                if (Line <= 0)
                    Line = callerFrame.Position.EndLineNumber;

                if (callerFrame.FunctionName == "Stop-Function")
                    _fromStopFunction = true;
            }

            if (String.IsNullOrEmpty(FunctionName))
                FunctionName = "<Unknown>";
            if (String.IsNullOrEmpty(ModuleName))
                ModuleName = "<Unknown>";

            if (MessageHost.DisableVerbosity)
                _silent = true;

            if (Tag != null)
                foreach (string item in Tag)
                    _Tags.Add(item);

            _isDebug = (_callStack.Count() > 1) && _callStack.ElementAt(_callStack.Count() - 2).InvocationInfo.BoundParameters.ContainsKey("Debug");
            #endregion Resolving Meta Information
        }

        /// <summary>
        /// Processes the process phase of the cmdlet
        /// </summary>
        protected override void ProcessRecord()
        {
            #region Perform Transforms
            if ((!_fromStopFunction) && (Target != null))
                Target = ResolveTarget(Target);

            if (!_fromStopFunction)
            {
                if (Exception != null)
                    Exception = ResolveException(Exception);
                else if (ErrorRecord != null)
                {
                    Exception tempException = null;
                    for (int n = 0; n < ErrorRecord.Length; n++)
                    {
                        // If both Exception and ErrorRecord are specified, override the first error record's exception.
                        if ((n == 0) && (Exception != null))
                            tempException = Exception;
                        else
                            tempException = ResolveException(ErrorRecord[n].Exception);
                        if (tempException != ErrorRecord[n].Exception)
                            ErrorRecord[n] = new ErrorRecord(tempException, ErrorRecord[n].FullyQualifiedErrorId, ErrorRecord[n].CategoryInfo.Category, ErrorRecord[n].TargetObject);
                    }
                }
            }

            if (Level != MessageLevel.Warning)
                Level = ResolveLevel(Level);
            #endregion Perform Transforms

            #region Exception Integration
            /*
                While conclusive error handling must happen after message handling,
                in order to integrate the exception message into the actual message,
                it becomes necessary to first integrate the exception and error record parameters into a uniform view
	
                Note: Stop-Function never specifies this parameter, thus it is not necessary to check,
                whether this function was called from Stop-Function.
             */
            if ((ErrorRecord == null) && (Exception != null))
            {
                ErrorRecord = new ErrorRecord[1];
                ErrorRecord[0] = new ErrorRecord(Exception, String.Format("{0}_{1}", ModuleName, FunctionName), ErrorCategory.NotSpecified, Target);
            }
            #endregion Exception Integration

            #region Error handling
            if (ErrorRecord != null)
            {
                if (!_fromStopFunction)
                    if (EnableException)
                        foreach (ErrorRecord record in ErrorRecord)
                            WriteError(record);

                LogHost.WriteErrorEntry(ErrorRecord, FunctionName, ModuleName, _Tags, _timestamp, _MessageSystem, System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId, Environment.MachineName);
            }
            #endregion Error handling

            LogEntryType channels = LogEntryType.None;

            #region Warning handling
            if (Level == MessageLevel.Warning)
            {
                if (!_silent)
                {
                    if (!String.IsNullOrEmpty(Once))
                    {
                        string onceName = String.Format("MessageOnce.{0}.{1}", FunctionName, Once).ToLower();
                        if (!(Configuration.ConfigurationHost.Configurations.ContainsKey(onceName) && (bool)Configuration.ConfigurationHost.Configurations[onceName].Value))
                        {
                            WriteWarning(_MessageStreams);
                            channels = channels | LogEntryType.Warning;

                            Configuration.Config cfg = new Configuration.Config();
                            cfg.Module = "messageonce";
                            cfg.Name = String.Format("{0}.{1}", FunctionName, Once).ToLower();
                            cfg.Hidden = true;
                            cfg.Description = "Locking setting that disables further display of the specified message";
                            cfg.Value = true;

                            Configuration.ConfigurationHost.Configurations[onceName] = cfg;
                        }
                    }
                    else
                    {
                        WriteWarning(_MessageStreams);
                        channels = channels | LogEntryType.Warning;
                    }
                }
                WriteDebug(_MessageStreams);
                channels = channels | LogEntryType.Debug;
            }
            #endregion Warning handling

            #region Message handling
            if (!_silent)
            {
                if ((MessageHost.MaximumInformation >= (int)Level) && (MessageHost.MinimumInformation <= (int)Level))
                {
                    if (!String.IsNullOrEmpty(Once))
                    {
                        string onceName = String.Format("MessageOnce.{0}.{1}", FunctionName, Once).ToLower();
                        if (!(Configuration.ConfigurationHost.Configurations.ContainsKey(onceName) && (bool)Configuration.ConfigurationHost.Configurations[onceName].Value))
                        {
                            InvokeCommand.InvokeScript(false, ScriptBlock.Create(_writeHostScript), null, _MessageHost);
                            channels = channels | LogEntryType.Information;

                            Configuration.Config cfg = new Configuration.Config();
                            cfg.Module = "messageonce";
                            cfg.Name = String.Format("{0}.{1}", FunctionName, Once).ToLower();
                            cfg.Hidden = true;
                            cfg.Description = "Locking setting that disables further display of the specified message";
                            cfg.Value = true;

                            Configuration.ConfigurationHost.Configurations[onceName] = cfg;
                        }
                    }
                    else
                    {
                        //InvokeCommand.InvokeScript(_writeHostScript, _MessageHost);
                        InvokeCommand.InvokeScript(false, ScriptBlock.Create(_writeHostScript), null, _MessageHost);
                        channels = channels | LogEntryType.Information;
                    }
                }
            }

            if ((MessageHost.MaximumVerbose >= (int)Level) && (MessageHost.MinimumVerbose <= (int)Level))
            {
                if ((_callStack.Count() > 1) && _callStack.ElementAt(_callStack.Count() - 2).InvocationInfo.BoundParameters.ContainsKey("Verbose"))
                    InvokeCommand.InvokeScript(@"$VerbosePreference = 'Continue'");
                //SessionState.PSVariable.Set("VerbosePreference", ActionPreference.Continue);

                WriteVerbose(_MessageStreams);
                channels = channels | LogEntryType.Verbose;
            }

            if ((MessageHost.MaximumDebug >= (int)Level) && (MessageHost.MinimumDebug <= (int)Level))
            {
                bool restoreInquire = false;
                if (_isDebug)
                {
                    if (Breakpoint.ToBool())
                        InvokeCommand.InvokeScript(false, ScriptBlock.Create(@"$DebugPreference = 'Inquire'"), null, null);
                    else
                    {
                        InvokeCommand.InvokeScript(false, ScriptBlock.Create(@"$DebugPreference = 'Continue'"), null, null);
                        restoreInquire = true;
                    }
                    WriteDebug(String.Format("{0} | {1}", Line, _MessageStreams));
                    channels = channels | LogEntryType.Debug;
                }
                else
                {
                    WriteDebug(_MessageStreams);
                    channels = channels | LogEntryType.Debug;
                }

                if (restoreInquire)
                    InvokeCommand.InvokeScript(false, ScriptBlock.Create(@"$DebugPreference = 'Inquire'"), null, null);
            }
            #endregion Message handling

            #region Logging
            LogEntry entry = LogHost.WriteLogEntry(_MessageSystem, channels, _timestamp, FunctionName, ModuleName, _Tags, Level, System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId, Environment.MachineName, File, Line, _callStack, String.Format("{0}\\{1}", Environment.UserDomainName, Environment.UserName), Target);
            #endregion Logging

            foreach (MessageEventSubscription subscription in MessageHost.Events.Values)
                if (subscription.Applies(entry))
                {
                    try { InvokeCommand.InvokeScript(subscription.ScriptBlock.ToString(), entry); }
                    catch (Exception e) { WriteError(new ErrorRecord(e, "", ErrorCategory.NotSpecified, entry)); }
                }
        }
        #endregion Cmdlet Implementation

        #region Helper methods
        /// <summary>
        /// Processes the target transform rules on an input object
        /// </summary>
        /// <param name="Item">The item to transform</param>
        /// <returns>The transformed object</returns>
        private object ResolveTarget(object Item)
        {
            if (Item == null)
                return null;

            string lowTypeName = Item.GetType().FullName.ToLower();

            if (MessageHost.TargetTransforms.ContainsKey(lowTypeName))
            {
                try { return InvokeCommand.InvokeScript(false, ScriptBlock.Create(MessageHost.TargetTransforms[lowTypeName].ToString()), null, Item); }
                catch (Exception e)
                {
                    MessageHost.WriteTransformError(new ErrorRecord(e, "Write-Message", ErrorCategory.OperationStopped, null), FunctionName, ModuleName, Item, TransformType.Target, System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId);
                    return Item;
                }
            }

            TransformCondition transform = MessageHost.TargetTransformlist.Get(lowTypeName, ModuleName, FunctionName);
            if (transform != null)
            {
                try { return InvokeCommand.InvokeScript(false, ScriptBlock.Create(transform.ScriptBlock.ToString()), null, Item); }
                catch (Exception e)
                {
                    MessageHost.WriteTransformError(new ErrorRecord(e, "Write-Message", ErrorCategory.OperationStopped, null), FunctionName, ModuleName, Item, TransformType.Target, System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId);
                    return Item;
                }
            }

            return Item;
        }

        /// <summary>
        /// Processes the specified exception specified
        /// </summary>
        /// <param name="Item">The exception to process</param>
        /// <returns>The transformed exception</returns>
        private Exception ResolveException(Exception Item)
        {
            if (Item == null)
                return Item;

            string lowTypeName = Item.GetType().FullName.ToLower();

            if (MessageHost.ExceptionTransforms.ContainsKey(lowTypeName))
            {
                try { return (Exception)InvokeCommand.InvokeScript(false, ScriptBlock.Create(MessageHost.ExceptionTransforms[lowTypeName].ToString()), null, Item)[0].BaseObject; }
                catch (Exception e)
                {
                    MessageHost.WriteTransformError(new ErrorRecord(e, "Write-Message", ErrorCategory.OperationStopped, null), FunctionName, ModuleName, Item, TransformType.Exception, System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId);
                    return Item;
                }
            }

            TransformCondition transform = MessageHost.ExceptionTransformList.Get(lowTypeName, ModuleName, FunctionName);
            if (transform != null)
            {
                try { return (Exception)InvokeCommand.InvokeScript(false, ScriptBlock.Create(transform.ScriptBlock.ToString()), null, Item)[0].BaseObject; }
                catch (Exception e)
                {
                    MessageHost.WriteTransformError(new ErrorRecord(e, "Write-Message", ErrorCategory.OperationStopped, null), FunctionName, ModuleName, Item, TransformType.Exception, System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId);
                    return Item;
                }
            }

            return Item;
        }

        /// <summary>
        /// Processs the input level and apply policy and rules
        /// </summary>
        /// <param name="Level">The original level of the message</param>
        /// <returns>The processed level</returns>
        private MessageLevel ResolveLevel(MessageLevel Level)
        {
            int tempLevel = (int)Level;

            if (MessageHost.NestedLevelDecrement > 0)
            {
                int depth = _stackDepth - 2;
                if (_fromStopFunction)
                    depth--;
                tempLevel = tempLevel + depth * MessageHost.NestedLevelDecrement;
            }

            if (MessageHost.MessageLevelModifiers.Count > 0)
                foreach (MessageLevelModifier modifier in MessageHost.MessageLevelModifiers.Values)
                    if (modifier.AppliesTo(FunctionName, ModuleName, _Tags))
                        tempLevel = tempLevel + modifier.Modifier;

            if (tempLevel > 9)
                tempLevel = 9;
            if (tempLevel < 1)
                tempLevel = 1;

            return (MessageLevel)tempLevel;
        }

        /// <summary>
        /// Builds the message item for display of Verbose, Warning and Debug streams
        /// </summary>
        /// <returns>The message to return</returns>
        private string GetMessage()
        {
            if (!String.IsNullOrEmpty(_message))
                return _message;
            if (MessageHost.EnableMessageTimestamp && MessageHost.EnableMessageBreadcrumbs)
                _message = String.Format("[{0}]{1}{2}", _timestamp.ToString("HH:mm:ss"), _BreadCrumbsString, GetMessageSimple());
            else if (MessageHost.EnableMessageTimestamp && MessageHost.EnableMessageDisplayCommand)
                _message = String.Format("[{0}][{1}] {2}", _timestamp.ToString("HH:mm:ss"), FunctionName, GetMessageSimple());
            else if (MessageHost.EnableMessageTimestamp)
                _message = String.Format("[{0}] {1}", _timestamp.ToString("HH:mm:ss"), GetMessageSimple());
            else if (MessageHost.EnableMessageBreadcrumbs)
                _message = String.Format("{0}{1}", _BreadCrumbsString, GetMessageSimple());
            else if (MessageHost.EnableMessageDisplayCommand)
                _message = String.Format("[{0}] {1}", FunctionName, GetMessageSimple());
            else
                _message = GetMessageSimple();

            return _message;
        }

        /// <summary>
        /// Builds the base message for internal system use.
        /// </summary>
        /// <returns>The message to return</returns>
        private string GetMessageSimple()
        {
            if (!String.IsNullOrEmpty(_messageSimple))
                return _messageSimple;

            string baseMessage = _errorQualifiedMessage;
            foreach (Match match in Regex.Matches(baseMessage, "<c=[\"'](.*?)[\"']>(.*?)</c>"))
                baseMessage = Regex.Replace(baseMessage, Regex.Escape(match.Value), match.Groups[2].Value);
            _messageSimple = baseMessage;

            return _messageSimple;
        }

        /// <summary>
        /// Builds the message item if needed and returns it
        /// </summary>
        /// <returns>The message to return</returns>
        private string GetMessageColor()
        {
            if (!String.IsNullOrEmpty(_messageColor))
                return _messageColor;

            if (MessageHost.EnableMessageTimestamp && MessageHost.EnableMessageBreadcrumbs)
                _messageColor = String.Format("[<c='sub'>{0}</c>]{1} {2}", _timestamp.ToString("HH:mm:ss"), _BreadCrumbsStringColored, _errorQualifiedMessage);
            else if (MessageHost.EnableMessageTimestamp && MessageHost.EnableMessageDisplayCommand)
                _messageColor = String.Format("[<c='sub'>{0}</c>][<c='sub'>{1}</c>] {2}", _timestamp.ToString("HH:mm:ss"), FunctionName, _errorQualifiedMessage);
            else if (MessageHost.EnableMessageTimestamp)
                _messageColor = String.Format("[<c='sub'>{0}</c>] {1}", _timestamp.ToString("HH:mm:ss"), _errorQualifiedMessage);
            else if (MessageHost.EnableMessageBreadcrumbs)
                _messageColor = String.Format("{0}{1}", _BreadCrumbsStringColored, _errorQualifiedMessage);
            else if (MessageHost.EnableMessageDisplayCommand)
                _messageColor = String.Format("[<c='sub'>{0}</c>] {1}", FunctionName, _errorQualifiedMessage);
            else
                _messageColor = _errorQualifiedMessage;

            return _messageColor;
        }

        /// <summary>
        /// Non-host output in developermode
        /// </summary>
        /// <returns>The string to write on messages that don't go straight to Write-HostColor</returns>
        private string GetMessageDeveloper()
        {
            if (!String.IsNullOrEmpty(_messageDeveloper))
                return _messageDeveloper;

            string targetString = "";
            if (Target != null)
            {
                if (Target.ToString() != Target.GetType().FullName)
                    targetString = String.Format(" [T: {0}] ", Target.ToString());
                else
                    targetString = String.Format(" [T: <{0}>] ", Target.GetType().Name);
            }

            List<string> channelList = new List<string>();
            if (!_silent)
            {
                if (Level == MessageLevel.Warning)
                    channelList.Add("Warning");
                if ((MessageHost.MaximumInformation >= (int)Level) && (MessageHost.MinimumInformation <= (int)Level))
                    channelList.Add("Information");
            }
            if ((MessageHost.MaximumVerbose >= (int)Level) && (MessageHost.MinimumVerbose <= (int)Level))
                channelList.Add("Verbose");
            if ((MessageHost.MaximumDebug >= (int)Level) && (MessageHost.MinimumDebug <= (int)Level))
                channelList.Add("Debug");

            _messageDeveloper = String.Format(@"[{0}][{1}][L: {2}]{3}[C: {4}][EE: {5}][O: {6}]
    {7}", _timestamp.ToString("HH:mm:ss"), FunctionName, Level, targetString, String.Join(",", channelList), EnableException, (!String.IsNullOrEmpty(Once)), GetMessageSimple());

            return _messageDeveloper;
        }

        /// <summary>
        /// Host output in developermode
        /// </summary>
        /// <returns>The string to write on messages that go straight to Write-HostColor</returns>
        private string GetMessageDeveloperColor()
        {
            if (!String.IsNullOrEmpty(_messageDeveloperColor))
                return _messageDeveloperColor;

            string targetString = "";
            if (Target != null)
            {
                if (Target.ToString() != Target.GetType().FullName)
                    targetString = String.Format(" [<c='sub'>T:</c> <c='em'>{0}</c>] ", Target.ToString());
                else
                    targetString = String.Format(" [<c='sub'>T:</c> <c='em'><{0}></c>] ", Target.GetType().Name);
            }

            List<string> channelList = new List<string>();
            if (!_silent)
            {
                if (Level == MessageLevel.Warning)
                    channelList.Add("Warning");
                if ((MessageHost.MaximumInformation >= (int)Level) && (MessageHost.MinimumInformation <= (int)Level))
                    channelList.Add("Information");
            }
            if ((MessageHost.MaximumVerbose >= (int)Level) && (MessageHost.MinimumVerbose <= (int)Level))
                channelList.Add("Verbose");
            if ((MessageHost.MaximumDebug >= (int)Level) && (MessageHost.MinimumDebug <= (int)Level))
                channelList.Add("Debug");

            _messageDeveloperColor = String.Format(@"[<c='sub'>{0}</c>][<c='sub'>{1}</c>][<c='sub'>L:</c> <c='em'>{2}</c>]{3}[<c='sub'>C: <c='em'>{4}</c>][<c='sub'>EE: <c='em'>{5}</c>][<c='sub'>O: <c='em'>{6}</c>]
    {7}", _timestamp.ToString("HH:mm:ss"), FunctionName, Level, targetString, String.Join(",", channelList), EnableException, (!String.IsNullOrEmpty(Once)), _errorQualifiedMessage);

            return _messageDeveloperColor;
        }
        #endregion Helper methods
    }
}
