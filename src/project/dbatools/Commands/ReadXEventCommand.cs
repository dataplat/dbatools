using System;
using System.Threading;
using System.Threading.Tasks;
using System.Management.Automation;
using System.Collections.Concurrent;
using System.Runtime.ExceptionServices;
using Microsoft.SqlServer.XEvent.XELite;

namespace Dataplat.Dbatools.Commands
{
    /// <summary>
    /// Implements the <c>Read-XEvent</c> internal command
    /// </summary>
    [Cmdlet("Read", "XEvent", DefaultParameterSetName = "Default", RemotingCapability = RemotingCapability.PowerShell)]
    public class ReadXEvent : PSCmdlet
    {
        #region Parameters
        /// <summary>
        /// The FileName of the .XEL
        /// </summary>
        [Parameter(ValueFromPipeline = true)]
        [Alias("FullName")]
        public string FileName;

        /// <summary>
        /// The ConnectionString to to SQL Instance
        /// </summary>
        [Parameter()]
        public string ConnectionString;

        /// <summary>
        /// The session name of the XE
        /// </summary>
        [Parameter()]
        public string SessionName;
        #endregion Parameters

        #region Private Methods

        private readonly CancellationTokenSource CancelToken = new CancellationTokenSource();

        private void ParseFile(string FileName)
        {
            new XEFileEventStreamer(FileName).ReadEventStream(delegate ()
                {
                    return Task.CompletedTask;
                },
                delegate (IXEvent xevent)
                {
                    WriteObject(xevent);
                    return Task.CompletedTask;
                },
                CancelToken.Token
             ).Wait();
        }

        private void ParseStream(string ConnectionString, string SessionName)
        {
            XELiveEventStreamer XELiveEventStreamer = new XELiveEventStreamer(ConnectionString, SessionName);
            BlockingCollection<object> queue = new BlockingCollection<object>(255);
            
            Task task = XELiveEventStreamer.ReadEventStream(delegate ()
                {
                    queue.Add(null, CancelToken.Token);
                    return Task.CompletedTask;
                },
                delegate (IXEvent xevent)
                {
                    queue.Add(xevent, CancelToken.Token);
                    return Task.CompletedTask;
                },
                CancelToken.Token
             );

            task.ContinueWith(delegate (Task newtask)
                {
                    queue.CompleteAdding();
                }
            );

            while (true)
            {
                try
                {
                    object item = queue.Take(CancelToken.Token);

                    if (item != null)
                    {
                        WriteObject(item);
                    }
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (InvalidOperationException ex)
                {
                    if (!CancelToken.IsCancellationRequested)
                    {
                        ExceptionDispatchInfo.Capture(ex).Throw();
                    }
                    break;
                }
            }
        }

        #endregion Private Methods

        #region Command Implementation
        /// <summary>
        /// Implements the begin action of the command
        /// </summary>
        protected override void BeginProcessing()
        {

        }

        /// <summary>
        /// Implements the process action of the command
        /// </summary>
        protected override void ProcessRecord()
        {
            if (FileName != null)
            {
                ParseFile(FileName);
            }
            else
            {
                // ps checks to ensure both ConnectionString and SessionName exist
                ParseStream(ConnectionString, SessionName);
            }
        }

        /// <summary>
        /// Implements the end action of the command
        /// </summary>
        protected override void EndProcessing()
        {
        }
        #endregion Command Implementation
    }
}