using Dataplat.Dbatools.Message;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Commands
{
    public partial class WriteMessageCommand
    {
        /// <summary>
        /// Processes the begin phase of the cmdlet
        /// </summary>
        protected override void BeginProcessing()
        {
            _timestamp = DateTime.Now;

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
                    File = callerFrame.ScriptName;

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

            _isDebug = (_callStack.Count() > 1) && _callStack.ElementAt(_callStack.Count() - 2).InvocationInfo.BoundParameters.ContainsKey("Debug") && ((SwitchParameter)_callStack.ElementAt(_callStack.Count() - 2).InvocationInfo.BoundParameters["Debug"]).ToBool();
        }

        /// <summary>
        /// Processes the process phase of the cmdlet
        /// </summary>
        protected override void ProcessRecord()
        {
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

            if (ErrorRecord != null)
            {
                if (!_fromStopFunction)
                    if (EnableException)
                        foreach (ErrorRecord record in ErrorRecord)
                            WriteError(record);

                LogHost.WriteErrorEntry(ErrorRecord, FunctionName, ModuleName, _Tags, _timestamp, _MessageSystem, System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId, Environment.MachineName);
            }

            LogEntryType channels = LogEntryType.None;

            if (Level == MessageLevel.Warning)
            {
                if (!_silent)
                {
                    if (!String.IsNullOrEmpty(Once))
                    {
                        string onceName = String.Format("MessageOnce.{0}.{1}", FunctionName, Once).ToLower();
                        if (!(Configuration.ConfigurationHost.Configurations.TryGetValue(onceName, out var existingConfig) && (bool)existingConfig.Value))
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

            if (!_silent)
            {
                if ((MessageHost.MaximumInformation >= (int)Level) && (MessageHost.MinimumInformation <= (int)Level))
                {
                    if (!String.IsNullOrEmpty(Once))
                    {
                        string onceName = String.Format("MessageOnce.{0}.{1}", FunctionName, Once).ToLower();
                        if (!(Configuration.ConfigurationHost.Configurations.TryGetValue(onceName, out var existingConfig) && (bool)existingConfig.Value))
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
                if ((_callStack.Count() > 1) && _callStack.ElementAt(_callStack.Count() - 2).InvocationInfo.BoundParameters.ContainsKey("Verbose") && ((SwitchParameter)_callStack.ElementAt(_callStack.Count() - 2).InvocationInfo.BoundParameters["Verbose"]).ToBool())
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
                        restoreInquire = (ActionPreference)GetVariableValue("DebugPreference") == ActionPreference.Inquire;
                        InvokeCommand.InvokeScript(false, ScriptBlock.Create(@"$DebugPreference = 'Continue'"), null, null);
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

            LogEntry entry = LogHost.WriteLogEntry(_MessageSystem, channels, _timestamp, FunctionName, ModuleName, _Tags, Level, System.Management.Automation.Runspaces.Runspace.DefaultRunspace.InstanceId, Environment.MachineName, File, Line, _callStack, String.Format("{0}\\{1}", Environment.UserDomainName, Environment.UserName), Target);

            foreach (MessageEventSubscription subscription in MessageHost.Events.Values)
                if (subscription.Applies(entry))
                {
                    try { InvokeCommand.InvokeScript(subscription.ScriptBlock.ToString(), entry); }
                    catch (Exception e) { WriteError(new ErrorRecord(e, "", ErrorCategory.NotSpecified, entry)); }
                }
        }
    }
}
