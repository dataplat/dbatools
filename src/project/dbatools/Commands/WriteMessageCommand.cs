using Dataplat.Dbatools.Message;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Management.Automation;
using System.Text.RegularExpressions;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// Implements the <c>Write-Message</c> command, performing message handling and logging.
    /// </summary>
    [Cmdlet("Write", "Message")]
    public partial class WriteMessageCommand : PSCmdlet
    {
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

if ([Dataplat.Dbatools.Message.MessageHost]::DeveloperMode) { Write-HostColor -String $string -DefaultColor ([Dataplat.Dbatools.Message.MessageHost]::DeveloperColor) -ErrorAction Ignore }
else { Write-HostColor -String $string -DefaultColor ([Dataplat.Dbatools.Message.MessageHost]::InfoColor) -ErrorAction Ignore }
";

        /// <summary>
        /// List of tags to process
        /// </summary>
        private List<string> _Tags = new List<string>();

        /// <summary>
        /// Whether debug mode is enabled
        /// </summary>
        private bool _isDebug;

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
    }
}
