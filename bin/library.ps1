
#region Source Code
$source = @'
using System;

namespace sqlcollective.dbatools
{
    namespace Configuration
    {
        using System.Collections;

        /// <summary>
        /// Configuration Manager as well as individual configuration object.
        /// </summary>
        [Serializable]
        public class Config
        {
            /// <summary>
            /// The central configuration store 
            /// </summary>
            public static Hashtable Cfg = new Hashtable();

            /// <summary>
            /// The hashtable containing the configuration handler scriptblocks.
            /// When registering a value to a configuration element, that value is stored in a hashtable.
            /// However these lookups can be expensive when done repeatedly.
            /// For greater performance, the most frequently stored values are stored in static fields instead.
            /// In order to facilitate this, an event can be reigstered - which is stored in this hashtable - that will accept the input value and copy it to the target field.
            /// </summary>
            public static Hashtable ConfigHandler = new Hashtable();

            /// <summary>
            /// The Name of the setting
            /// </summary>
            public string Name;

            /// <summary>
            /// The module of the setting. Helps being able to group configurations.
            /// </summary>
            public string Module;

            /// <summary>
            /// A description of the specific setting
            /// </summary>
            public string Description;

            /// <summary>
            /// The data type of the value stored in the configuration element.
            /// </summary>
            public string Type
            {
                get
                {
                    try { return Value.GetType().FullName; }
                    catch { return null; }
                }
                set { }
            }

            /// <summary>
            /// The value stored in the configuration element
            /// </summary>
            public Object Value;

            /// <summary>
            /// Setting this to true will cause the element to not be discovered unless using the '-Force' parameter on "Get-DbaConfig"
            /// </summary>
            public bool Hidden = false;
        }
    }

    namespace dbaSystem
    {
        using System.Collections.Concurrent;
        using System.Management.Automation;
        using System.Threading;
        
        /// <summary>
        /// An error record written by dbatools
        /// </summary>
        [Serializable]
        public class DbaErrorRecord
        {
            /// <summary>
            /// The category of the error
            /// </summary>
            public ErrorCategoryInfo CategoryInfo;

            /// <summary>
            /// The details on the error
            /// </summary>
            public ErrorDetails ErrorDetails;

            /// <summary>
            /// The actual exception thrown
            /// </summary>
            public Exception Exception;

            /// <summary>
            /// The specific error identity, used to identify the target
            /// </summary>
            public string FullyQualifiedErrorId;

            /// <summary>
            /// The details of how this was called.
            /// </summary>
            public object InvocationInfo;

            /// <summary>
            /// The script's stacktrace
            /// </summary>
            public string ScriptStackTrace;

            /// <summary>
            /// The object being processed
            /// </summary>
            public object TargetObject;

            /// <summary>
            /// The name of the function throwing the error
            /// </summary>
            public string FunctionName;

            /// <summary>
            /// When was the error thrown
            /// </summary>
            public DateTime Timestamp;

            /// <summary>
            /// The message that was written in a userfriendly manner
            /// </summary>
            public string Message;

            /// <summary>
            /// Create an empty record
            /// </summary>
            public DbaErrorRecord()
            {

            }

            /// <summary>
            /// Create a filled out error record
            /// </summary>
            /// <param name="Record">The original error record</param>
            /// <param name="FunctionName">The function that wrote the error</param>
            /// <param name="Timestamp">When was the error generated</param>
            /// <param name="Message">What message was passed when writing the error</param>
            public DbaErrorRecord(ErrorRecord Record, string FunctionName, DateTime Timestamp, string Message)
            {
                this.FunctionName = FunctionName;
                this.Timestamp = Timestamp;
                this.Message = Message;

                CategoryInfo = Record.CategoryInfo;
                ErrorDetails = Record.ErrorDetails;
                Exception = Record.Exception;
                FullyQualifiedErrorId = Record.FullyQualifiedErrorId;
                InvocationInfo = Record.InvocationInfo;
                ScriptStackTrace = Record.ScriptStackTrace;
                TargetObject = Record.TargetObject;
            }
        }

        /// <summary>
        /// Hosts static debugging values and methods
        /// </summary>
        public static class DebugHost
        {
            #region Defines
            /// <summary>
            /// The maximum numbers of error records maintained in-memory.
            /// </summary>
            public static int MaxErrorCount = 128;

            /// <summary>
            /// The maximum number of messages that can be maintained in the in-memory message queue
            /// </summary>
            public static int MaxMessageCount = 1024;

            /// <summary>
            /// The maximum size of a given logfile. When reaching this limit, the file will be abandoned and a new log created. Set to 0 to not limit the size.
            /// </summary>
            public static int MaxMessagefileBytes = 5242880; // 5MB

            /// <summary>
            /// The maximum number of logfiles maintained at a time. Exceeding this number will cause the oldest to be culled. Set to 0 to disable the limit.
            /// </summary>
            public static int MaxMessagefileCount = 5;

            /// <summary>
            /// The maximum size all error files combined may have. When this number is exceeded, the oldest entry is culled.
            /// </summary>
            public static int MaxErrorFileBytes = 20971520; // 20MB

            /// <summary>
            /// This is the upper limit of length all items in the log folder may have combined across all processes.
            /// </summary>
            public static int MaxTotalFolderSize = 104857600; // 100MB

            /// <summary>
            /// Path to where the logfiles live.
            /// </summary>
            public static string LoggingPath;

            /// <summary>
            /// Any logfile older than this will automatically be cleansed
            /// </summary>
            public static TimeSpan MaxLogFileAge = new TimeSpan(7, 0, 0, 0);

            /// <summary>
            /// Governs, whether a log file for the system messages is written
            /// </summary>
            public static bool MessageLogFileEnabled = true;

            /// <summary>
            /// Governs, whether a log of recent messages is kept in memory
            /// </summary>
            public static bool MessageLogEnabled = true;

            /// <summary>
            /// Governs, whether log files for errors are written
            /// </summary>
            public static bool ErrorLogFileEnabled = true;

            /// <summary>
            /// Governs, whether a log of recent errors is kept in memory
            /// </summary>
            public static bool ErrorLogEnabled = true;
            #endregion Defines

            #region Queues
            private static ConcurrentQueue<DbaErrorRecord> ErrorRecords = new ConcurrentQueue<DbaErrorRecord>();

            private static ConcurrentQueue<LogEntry> LogEntries = new ConcurrentQueue<LogEntry>();

            /// <summary>
            /// The outbound queue for errors. These will be processed and written to xml
            /// </summary>
            public static ConcurrentQueue<DbaErrorRecord> OutQueueError = new ConcurrentQueue<DbaErrorRecord>();

            /// <summary>
            /// The outbound queue for logs. These will be processed and written to logfile
            /// </summary>
            public static ConcurrentQueue<LogEntry> OutQueueLog = new ConcurrentQueue<LogEntry>();
            #endregion Queues

            #region Access Queues
            /// <summary>
            /// Retrieves a copy of the Error stack
            /// </summary>
            /// <returns>All errors thrown by dbatools functions</returns>
            public static DbaErrorRecord[] GetErrors()
            {
                DbaErrorRecord[] temp = new DbaErrorRecord[ErrorRecords.Count];
                ErrorRecords.CopyTo(temp, 0);
                return temp;
            }

            /// <summary>
            /// Retrieves a copy of the message log
            /// </summary>
            /// <returns>All messages logged this session.</returns>
            public static LogEntry[] GetLog()
            {
                LogEntry[] temp = new LogEntry[LogEntries.Count];
                LogEntries.CopyTo(temp, 0);
                return temp;
            }

            /// <summary>
            /// Write an error record to the log
            /// </summary>
            /// <param name="Record">The actual error record as powershell wrote it</param>
            /// <param name="FunctionName">The name of the function writing the error</param>
            /// <param name="Timestamp">When was the error written</param>
            /// <param name="Message">What message was passed to the user</param>
            public static void WriteErrorEntry(ErrorRecord Record, string FunctionName, DateTime Timestamp, string Message)
            {
                DbaErrorRecord temp = new DbaErrorRecord(Record, FunctionName, Timestamp, Message);
                if (ErrorLogFileEnabled) { OutQueueError.Enqueue(temp); }
                if (ErrorLogEnabled) { ErrorRecords.Enqueue(temp); }

                DbaErrorRecord tmp;
                while ((MaxErrorCount > 0) && (ErrorRecords.Count > MaxErrorCount))
                {
                    ErrorRecords.TryDequeue(out tmp);
                }
            }

            /// <summary>
            /// Write a new entry to the log
            /// </summary>
            /// <param name="Message">The message to log</param>
            /// <param name="Type">The type of the message logged</param>
            /// <param name="Timestamp">When was the message generated</param>
            /// <param name="FunctionName">What function wrote the message</param>
            /// <param name="Level">At what level was the function written</param>
            public static void WriteLogEntry(string Message, LogEntryType Type, DateTime Timestamp, string FunctionName, int Level)
            {
                LogEntry temp = new LogEntry(Message, Type, Timestamp, FunctionName, Level);
                if (MessageLogFileEnabled) { OutQueueLog.Enqueue(temp); }
                if (MessageLogEnabled) { LogEntries.Enqueue(temp); }

                LogEntry tmp;
                while ((MaxMessageCount > 0) && (LogEntries.Count > MaxMessageCount))
                {
                    LogEntries.TryDequeue(out tmp);
                }
            }
            #endregion Access Queues
        }

        /// <summary>
        /// An individual entry for the message log
        /// </summary>
        [Serializable]
        public class LogEntry
        {
            /// <summary>
            /// The message logged
            /// </summary>
            public string Message;

            /// <summary>
            /// What kind of entry was this?
            /// </summary>
            public LogEntryType Type;

            /// <summary>
            /// When was the message logged?
            /// </summary>
            public DateTime Timestamp;

            /// <summary>
            /// What function wrote the message
            /// </summary>
            public string FunctionName;

            /// <summary>
            /// What level was the message?
            /// </summary>
            public int Level;

            /// <summary>
            /// Creates an empty log entry
            /// </summary>
            public LogEntry()
            {

            }

            /// <summary>
            /// Creates a filled out log entry
            /// </summary>
            /// <param name="Message">The message that was logged</param>
            /// <param name="Type">The type(s) of message written</param>
            /// <param name="Timestamp">When was the message logged</param>
            /// <param name="FunctionName">What function wrote the message</param>
            /// <param name="Level">What level was the message written at.</param>
            public LogEntry(string Message, LogEntryType Type, DateTime Timestamp, string FunctionName, int Level)
            {
                this.Message = Message;
                this.Type = Type;
                this.Timestamp = Timestamp;
                this.FunctionName = FunctionName;
                this.Level = Level;
            }
        }

        /// <summary>
        /// The kind of information the logged entry was.
        /// </summary>
        [Flags]
        public enum LogEntryType
        {
            /// <summary>
            /// A message that was written to the current host equivalent, if available to the information stream instead
            /// </summary>
            Information = 1,

            /// <summary>
            /// A message that was written to the verbose stream
            /// </summary>
            Verbose = 2,

            /// <summary>
            /// A message that was written to the Debug stream
            /// </summary>
            Debug = 4,

            /// <summary>
            /// A message written to the warning stream
            /// </summary>
            Warning = 8
        }

        /// <summary>
        /// Hosts all functionality of the log writer
        /// </summary>
        public static class LogWriterHost
        {
            #region Logwriter
            private static ScriptBlock LogWritingScript;

            private static PowerShell LogWriter;

            /// <summary>
            /// Setting this to true should cause the script running in the runspace to selfterminate, allowing a graceful selftermination.
            /// </summary>
            public static bool LogWriterStopper
            {
                get { return _LogWriterStopper; }
            }
            private static bool _LogWriterStopper = false;

            /// <summary>
            /// Set the script to use as part of the log writer
            /// </summary>
            /// <param name="Script">The script to use</param>
            public static void SetScript(ScriptBlock Script)
            {
                LogWritingScript = Script;
            }

            /// <summary>
            /// Starts the logwriter.
            /// </summary>
            public static void Start()
            {
                if ((DebugHost.ErrorLogFileEnabled || DebugHost.MessageLogFileEnabled) && (LogWriter == null))
                {
                    _LogWriterStopper = false;
                    LogWriter = PowerShell.Create();
                    LogWriter.AddScript(LogWritingScript.ToString());
                    LogWriter.BeginInvoke();
                }
            }

            /// <summary>
            /// Gracefully stops the logwriter
            /// </summary>
            public static void Stop()
            {
                _LogWriterStopper = true;

                int i = 0;

                // Wait up to 30 seconds for the running script to notice and kill itself
                while ((LogWriter.Runspace.RunspaceAvailability != System.Management.Automation.Runspaces.RunspaceAvailability.Available) && (i < 300))
                {
                    i++;
                    Thread.Sleep(100);
                }

                Kill();
            }

            /// <summary>
            /// Very ungracefully kills the logwriter. Use only in the most dire emergency.
            /// </summary>
            public static void Kill()
            {
                LogWriter.Runspace.Close();
                LogWriter.Dispose();
                LogWriter = null;
            }
            #endregion Logwriter
        }

        /// <summary>
        /// Provides static resources to the messaging subsystem
        /// </summary>
        public static class MessageHost
        {
            #region Defines
            /// <summary>
            /// The maximum message level to still display to the user directly.
            /// </summary>
            public static int MaximumInformation = 3;

            /// <summary>
            /// The maxium message level where verbose information is still written.
            /// </summary>
            public static int MaximumVerbose = 6;

            /// <summary>
            /// The maximum message level where debug information is still written.
            /// </summary>
            public static int MaximumDebug = 9;

            /// <summary>
            /// The minimum required message level for messages that will be shown to the user.
            /// </summary>
            public static int MinimumInformation = 1;

            /// <summary>
            /// The minimum required message level where verbose information is written.
            /// </summary>
            public static int MinimumVerbose = 4;

            /// <summary>
            /// The minimum required message level where debug information is written.
            /// </summary>
            public static int MinimumDebug = 1;

            #endregion Defines
        }
    }
}
'@
#endregion Source Code

try { Add-Type $source -ErrorAction Stop }
catch
{
    throw
}